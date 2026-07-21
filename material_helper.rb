# ML Cabinets - Material Helper
# Resolves material preset IDs to SketchUp::Material objects.
# Supports both built-in presets (color-only) and library presets (PNG texture).

require 'sketchup.rb'
require 'json'

module MLCabinets
  module MaterialHelper

    # Built-in material presets ΓÇö mirrors constants.js MATERIAL_PRESETS.
    # Only color is needed; no texture file.
    BUILTIN_PRESETS = {
      'MT-G01' => { name: 'Clear Glass',     color: [0xD6, 0xEA, 0xF0], alpha: 0.3 },
      'MT-G02' => { name: 'Frosted Glass',   color: [0xE8, 0xEE, 0xF0], alpha: 0.5 },
      'MT-G03' => { name: 'Smoked Glass',    color: [0x4A, 0x55, 0x68], alpha: 0.6 },
    }.freeze unless defined?(BUILTIN_PRESETS)

    # Cache of resolved SketchUp::Material objects (per-model session).
    # Cleared when a new model is opened.
    @material_cache = {} unless defined?(@material_cache)
    @cache_model_id = nil unless defined?(@cache_model_id)

    # ----------------------------------------------------------------
    # Resolve a preset ID to a SketchUp::Material.
    # Returns nil if the ID is nil or cannot be resolved.
    # ----------------------------------------------------------------

    def self.resolve(model, preset_id, grain = 'vertical')
      return nil unless preset_id && !preset_id.to_s.strip.empty?

      # Invalidate cache if the model changed
      mid = model.object_id
      if @cache_model_id != mid
        @material_cache = {}
        @cache_model_id = mid
      end

      cache_key = "#{preset_id}_#{grain}"
      if @material_cache.key?(cache_key)
        cached = @material_cache[cache_key]
        return cached if material_alive?(cached)
        @material_cache.delete(cache_key)
      end

      mat = if BUILTIN_PRESETS.key?(preset_id)
              resolve_builtin(model, preset_id)
            else
              resolve_library(model, preset_id, grain)
            end

      # Store grain intent and preset ID on the material so apply() and
      # grain-only overrides can read them later without needing these
      # values threaded through every call site.
      if mat
        mat.set_attribute('ml_cabinets', 'grain', grain)
        mat.set_attribute('ml_cabinets', 'preset_id', preset_id.to_s)
      end

      @material_cache[cache_key] = mat
      mat
    end

    # ----------------------------------------------------------------
    # Resolve a full materials hash (from params[:materials]) into
    # a hash of { category => SketchUp::Material }.
    # ----------------------------------------------------------------

    def self.resolve_all(model, materials_hash)
      return {} unless materials_hash.is_a?(Hash)
      result = {}
      materials_hash.each do |cat, entry|
        mat = resolve(model, entry[:id], entry[:grain] || 'vertical')
        result[cat] = mat if mat
      end
      result
    end

    # ----------------------------------------------------------------
    # Apply a material to a ComponentInstance.
    # Sets the instance-level material (fallback for unpainted faces) then,
    # for textured materials, explicitly positions the UV mapping on each
    # face in the definition's geometry so grain direction is respected.
    #
    # Grain direction is stored as an attribute on the material itself
    # (written by +resolve+) so callers don't need to thread grain through.
    #
    # +glass_material+: optional SketchUp::Material for faces whose
    # original library material matched "glass" (case-insensitive).
    # When provided, those faces receive the glass material instead of
    # the primary material so glass inserts survive material category swaps.
    # ----------------------------------------------------------------

    def self.apply(instance, material, glass_material: nil, metal_material: nil)
      return unless instance.is_a?(Sketchup::ComponentInstance) && material
      unless material_alive?(material)
        replacement = nil
        begin
          replacement = instance.model.materials[material.name]
        rescue
          replacement = nil
        end
        material = replacement
      end
      return unless material_alive?(material)
      instance.material = material

      # Always isolate this instance's definition before touching any face data.
      # Without this, instances that are the sole user of a definition at the time
      # apply() is called (make_unique no-ops) would have their face materials
      # mutated in-place, and every subsequent instance loading the same library
      # definition would inherit those painted faces — even if the later instance
      # carries a completely different material override.
      instance.make_unique
      deep_make_unique(instance.definition.entities)

      if material.texture
        grain = material.get_attribute('ml_cabinets', 'grain') || 'vertical'
        # Paint face UV coords — every definition is now unique so writes
        # cannot bleed into other instances or cabinets.
        apply_grain_to_faces(instance.definition.entities, material, grain, glass_material: glass_material, metal_material: metal_material)
      else
        # Solid-colour material: clear any face-level materials that may have
        # been copied from a previously-painted shared definition so that faces
        # correctly inherit this instance's solid colour.
        clear_face_materials(instance.definition.entities, glass_material: glass_material, metal_material: metal_material)
      end
    end

    private

    # ----------------------------------------------------------------
    # Built-in preset ΓåÆ solid-color material
    # ----------------------------------------------------------------

    def self.resolve_builtin(model, preset_id)
      info = BUILTIN_PRESETS[preset_id]
      return nil unless info

      mat_name = "MLC_#{preset_id}"
      mat = model.materials[mat_name]
      return mat if material_alive?(mat)

      mat = model.materials.add(mat_name)
      mat.color = Sketchup::Color.new(*info[:color])
      mat.alpha = info[:alpha] if info[:alpha]

      # Apply a tiny solid-color texture so that face UV coordinates are
      # preserved when switching between textured and solid-color materials.
      # Without this, the solid-color path clears face materials, losing
      # library-authored UVs that cannot be recovered.
      tex_path = solid_color_texture_path(info[:color])
      mat.texture = tex_path if tex_path

      mat
    end

    # ----------------------------------------------------------------
    # Library preset ΓåÆ textured material (PNG from materials library)
    # ----------------------------------------------------------------

    def self.resolve_library(model, preset_id, grain = 'vertical')
      # Look up preset in presets.json to find the folder name
      preset_name = resolve_material_preset_name(preset_id)
      return nil unless preset_name

      png_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'materials',
                           preset_name, "#{preset_name}.png")
      return nil unless File.exist?(png_path)

      mat_name = "MLC_#{preset_name}_#{grain}"
      mat = model.materials[mat_name]
      return mat if material_alive?(mat)

      mat = model.materials.add(mat_name)

      # Load the color from metadata if available
      json_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'materials',
                            preset_name, "#{preset_name}.json")
      if File.exist?(json_path)
        begin
          meta = JSON.parse(File.read(json_path, encoding: 'UTF-8'))
          hex = meta['color']
          if hex && hex =~ /\A#([0-9A-Fa-f]{6})\z/
            r = $1[0..1].to_i(16)
            g = $1[2..3].to_i(16)
            b = $1[4..5].to_i(16)
            mat.color = Sketchup::Color.new(r, g, b)
          end
        rescue => e
          puts "MLCabinets: MaterialHelper metadata read error ΓÇö #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Apply the texture with natural dimensions.
      # Grain direction rotation is handled at the face-UV level in apply(),
      # not by swapping texture tile dimensions here.
      mat.texture = png_path

      mat
    rescue => e
      puts "MLCabinets: MaterialHelper.resolve_library error ΓÇö #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Resolve a preset ID to its folder name.
    # Folder-first: if preset_id is already a valid folder name, use it directly.
    # Falls back to UUID lookup in presets.json for backwards compatibility.
    # ----------------------------------------------------------------

    def self.resolve_material_preset_name(preset_id)
      mats_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'materials')
      return preset_id.to_s if Dir.exist?(File.join(mats_dir, preset_id.to_s))

      presets_file = File.join(mats_dir, 'presets.json')
      return nil unless File.exist?(presets_file)

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      preset = (data['presets'] || []).find { |p| p['id'] == preset_id.to_s }
      preset ? preset['name'] : nil
    rescue => e
      puts "MLCabinets: resolve_material_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Create (or return cached path of) a 4×4 solid-color PNG texture.
    # Stored in Sketchup.temp_dir so it persists for the session but is
    # cleaned up on OS restart.
    # ----------------------------------------------------------------

    def self.solid_color_texture_path(rgb)
      hex = format('%02X%02X%02X', *rgb)
      path = File.join(Sketchup.temp_dir, "mlc_solid_#{hex}.png")
      return path if File.exist?(path)

      begin
        r, g, b = rgb
        pixel = [r, g, b, 255].pack('C4')
        data  = pixel * 16  # 4×4 = 16 pixels
        irep  = Sketchup::ImageRep.new
        irep.set_data(4, 4, 32, 0, data)
        irep.save_file(path)
        path
      rescue => e
        puts "MLCabinets: solid_color_texture_path error — #{e.message}" if MLCabinets::DEBUG
        nil
      end
    end

    # SketchUp entities can remain as stale Ruby objects after deletion.
    # Guard every cache hit and assignment to avoid assigning deleted materials.
    def self.material_alive?(material)
      return false unless material
      return material.valid? if material.respond_to?(:valid?)
      return !material.deleted? if material.respond_to?(:deleted?)
      true
    rescue
      false
    end

    # ----------------------------------------------------------------
    # Recursively clone every ComponentInstance in +entities+ so that
    # no two cabinets share the same sub-component definition.
    # Must be called BEFORE apply_grain_to_faces.
    # ----------------------------------------------------------------

    def self.deep_make_unique(entities)
      # Snapshot to an array first ΓÇö make_unique internally removes/re-adds
      # the instance in the parent entities collection, which corrupts a live
      # Ruby iterator and causes some instances to be skipped or visited twice.
      entities.to_a.each do |ent|
        next unless ent.is_a?(Sketchup::ComponentInstance)
        ent.make_unique
        deep_make_unique(ent.definition.entities)
      end
    rescue => e
      puts "MLCabinets: deep_make_unique error ΓÇö #{e.message}" if MLCabinets::DEBUG
    end

    # ----------------------------------------------------------------
    # Recursively clear face-level materials to nil on every face inside
    # +entities+ (and nested groups/components) so that the instance's
    # solid-colour material is visible.  Called for non-textured materials
    # after deep_make_unique has already isolated the definition.
    # ----------------------------------------------------------------

    def self.clear_face_materials(entities, glass_material: nil, metal_material: nil)
      entities.to_a.each do |ent|
        case ent
        when Sketchup::Face
          if glass_face?(ent)
            ent.material = glass_material if glass_material
          elsif metal_face?(ent)
            ent.material = metal_material if metal_material
          else
            ent.material = nil
          end
        when Sketchup::Group
          clear_face_materials(ent.entities, glass_material: glass_material, metal_material: metal_material)
        when Sketchup::ComponentInstance
          clear_face_materials(ent.definition.entities, glass_material: glass_material, metal_material: metal_material)
        end
      end
    rescue => e
      puts "MLCabinets: clear_face_materials error — #{e.message}" if MLCabinets::DEBUG
    end

    # ----------------------------------------------------------------
    # Traverse +entities+ and position UV mapping on every face.
    # Recurses into nested groups and component definitions.
    # All definitions must be unique before calling this (see deep_make_unique).
    #
    # Faces with library-authored UV mapping (detected on first encounter
    # by their non-MLC_ textured material, then permanently tagged via
    # the +ml_cabinets/library_uv+ attribute) keep their UV coordinates
    # across material swaps — only the material reference changes.  This
    # preserves grain continuity on 45° miters, raised-panel seams, etc.
    #
    # All other faces receive grain-directed UVs so the grain swap tool
    # works correctly on subsequent calls.
    # ----------------------------------------------------------------

    def self.apply_grain_to_faces(entities, material, grain, glass_material: nil, metal_material: nil)
      tw = material.texture.width    # one tile width  in model units (inches)
      th = material.texture.height   # one tile height in model units (inches)
      # Snapshot to array — safe against any live-collection mutation.
      entities.to_a.each do |ent|
        case ent
        when Sketchup::Face
          if glass_face?(ent)
            # Glass insert — apply the glass material if available,
            # otherwise leave the face untouched so the original glass
            # appearance is preserved.
            if glass_material
              if library_uv_face?(ent)
                reapply_with_existing_uvs(ent, glass_material)
              else
                ent.material = glass_material
              end
            end
          elsif metal_face?(ent)
            # Metal insert — apply the handle material if available,
            # otherwise leave the face untouched.
            if metal_material
              if library_uv_face?(ent)
                reapply_with_existing_uvs(ent, metal_material)
              else
                ent.material = metal_material
              end
            end
          elsif library_uv_face?(ent)
            # Face carries library-authored UV mapping — swap material only.
            reapply_with_existing_uvs(ent, material)
          else
            n = ent.normal
            if n.parallel?(X_AXIS) || n.parallel?(Y_AXIS) || n.parallel?(Z_AXIS)
              # Axis-aligned face — apply grain-directed UVs.
              position_face_material(ent, material, grain, tw, th)
            elsif ent.material && ent.material.texture
              # Non-axis-aligned, previously painted by us — preserve UVs.
              reapply_with_existing_uvs(ent, material)
            else
              # Non-axis-aligned, no texture — assign material directly.
              ent.material = material
            end
          end
        when Sketchup::Group
          apply_grain_to_faces(ent.entities, material, grain, glass_material: glass_material, metal_material: metal_material)
        when Sketchup::ComponentInstance
          apply_grain_to_faces(ent.definition.entities, material, grain, glass_material: glass_material, metal_material: metal_material)
        end
      end
    rescue => e
      puts "MLCabinets: apply_grain_to_faces error — #{e.message}" if MLCabinets::DEBUG
    end

    # ----------------------------------------------------------------
    # Detect whether a face has library-authored UV mapping.
    #
    # On first encounter the face still carries its original non-MLC_
    # textured material from the loaded SKP.  We tag it with the
    # +ml_cabinets/library_uv+ attribute so that after make_unique and
    # material swaps (when the face already carries an MLC_ material)
    # we can still recognise it.
    # ----------------------------------------------------------------

    def self.library_uv_face?(face)
      return true if face.get_attribute('ml_cabinets', 'library_uv')

      if face.material && face.material.texture &&
         !face.material.name.to_s.start_with?('MLC_')
        face.set_attribute('ml_cabinets', 'library_uv', true)
        return true
      end

      false
    end

    # ----------------------------------------------------------------
    # Detect whether a face has a glass material (from the library SKP).
    #
    # On first encounter the face still carries its original material
    # whose name contains "glass" (case-insensitive).  We tag it with
    # the +ml_cabinets/glass_face+ attribute so that after make_unique
    # and material swaps we can still recognise it.
    # ----------------------------------------------------------------

    def self.glass_face?(face)
      return true if face.get_attribute('ml_cabinets', 'glass_face')

      if face.material && face.material.name.to_s.downcase.include?('glass')
        face.set_attribute('ml_cabinets', 'glass_face', true)
        return true
      end

      false
    end

    # ----------------------------------------------------------------
    # Detect whether a face has a metal material (from the library SKP).
    #
    # On first encounter the face still carries its original material
    # whose name contains "metal" (case-insensitive).  We tag it with
    # the +ml_cabinets/metal_face+ attribute so that after make_unique
    # and material swaps we can still recognise it.
    # ----------------------------------------------------------------

    def self.metal_face?(face)
      return true if face.get_attribute('ml_cabinets', 'metal_face')

      if face.material && face.material.name.to_s.downcase.include?('metal')
        face.set_attribute('ml_cabinets', 'metal_face', true)
        return true
      end

      false
    end

    # ----------------------------------------------------------------
    # Swap the material on a face while preserving its existing UV
    # coordinates.  Reads the front-face UVQ values from the first 3
    # vertices, converts to UV, and re-applies via position_material
    # so the mapping survives the material change.
    # ----------------------------------------------------------------

    def self.reapply_with_existing_uvs(face, material)
      uvh   = face.get_UVHelper(true, false)
      verts = face.vertices
      return if verts.length < 3

      pts = []
      verts.first(3).each do |v|
        pos = v.position
        uvq = uvh.get_front_UVQ(pos)
        q   = uvq.z
        q   = 1.0 if q.abs < 1e-10   # guard against division by zero
        pts << pos
        pts << Geom::Point3d.new(uvq.x / q, uvq.y / q, 0)
      end
      face.position_material(material, pts, true)
    rescue => e
      puts "MLCabinets: reapply_with_existing_uvs error — #{e.message}" if MLCabinets::DEBUG
    end

    # ----------------------------------------------------------------
    # Paint a single axis-aligned face with UV coordinates that encode
    # the requested grain direction.
    #
    #   Face plane  | vertical grain  | horizontal grain
    #   ------------+-----------------+------------------
    #   XZ (┬▒Y)     | U=+X  V=+Z      | U=+Z  V=+X
    #   XY (┬▒Z)     | U=+X  V=+Y      | U=+Y  V=+X
    #   YZ (┬▒X)     | U=+Y  V=+Z      | U=+Z  V=+Y
    #
    # Non-axis-aligned faces (diagonal cut, complex library shapes) are
    # skipped ΓÇö their existing UV mapping is left intact.
    # ----------------------------------------------------------------

    def self.position_face_material(face, material, grain, tw, th)
      n = face.normal

      if n.parallel?(Y_AXIS)       # Front / back face ΓÇö XZ plane
        if grain == 'vertical'
          u_axis = Z_AXIS;  v_axis = X_AXIS
        else
          u_axis = X_AXIS;  v_axis = Z_AXIS
        end
      elsif n.parallel?(Z_AXIS)    # Top / bottom face ΓÇö XY plane
        if grain == 'vertical'
          u_axis = Y_AXIS;  v_axis = X_AXIS
        else
          u_axis = X_AXIS;  v_axis = Y_AXIS
        end
      elsif n.parallel?(X_AXIS)    # Left / right face ΓÇö YZ plane
        if grain == 'vertical'
          u_axis = Z_AXIS;  v_axis = Y_AXIS
        else
          u_axis = Y_AXIS;  v_axis = Z_AXIS
        end
      else
        return  # Non-axis-aligned ΓÇö skip
      end

      origin = face.vertices.first.position
      u_pt   = origin.offset(u_axis, tw)
      v_pt   = origin.offset(v_axis, th)
      pts    = [origin, Geom::Point3d.new(0, 0),
                u_pt,   Geom::Point3d.new(1, 0),
                v_pt,   Geom::Point3d.new(0, 1)]
      face.position_material(material, pts, true)
    rescue => e
      puts "MLCabinets: position_face_material error ΓÇö #{e.message}" if MLCabinets::DEBUG
    end

  end # module MaterialHelper
end # module MLCabinets
