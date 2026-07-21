# ML Cabinets - Add Appliance to Library
# Validates an appliance component, screenshots it, exports SKP+DAE+JSON,
# and updates the centralized presets index under libraries/appliances/.

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddApplianceToLibrary

    @appliance = nil
    @appliance_name = nil
    @appliance_original_transform = nil
    @fixed_size    = false
    @free_standing = false

    # Labels used by the add-to-library dialog to render the two checkboxes
    ALL_APPLIANCE_TYPES = ['Fixed Size', 'Free Standing'].freeze

    # -----------------------------------------------------------------
    # Public API (called by LibraryHandler)
    # -----------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @appliance = entity
      @appliance_name = name
    end

    def self.set_appliance_flags(fixed_size:, free_standing:)
      @fixed_size    = fixed_size    == true
      @free_standing = free_standing == true
    end

    # Full workflow inside a single undo operation.
    def self.process_library_addition
      model = Sketchup.active_model
      model.start_operation('Add Appliance to Library', true)

      begin
        # 1. Hide everything except the appliance
        originally_visible = []
        model.active_entities.each do |ent|
          next unless ent.respond_to?(:visible?)
          if ent.visible? && ent != @appliance
            originally_visible << ent
          end
          ent.visible = false if ent != @appliance && ent.respond_to?(:visible=)
        end

        # 2. Move to origin
        move_to_origin

        # 3. Screenshot + exports
        preset_folder = appliance_preset_folder_path
        ok_png = take_screenshot(preset_folder)
        ok_skp = save_to_disk(preset_folder)
        ok_dae = export_to_dae(preset_folder)
        success = ok_png && ok_skp && ok_dae

        # 4. Metadata
        save_metadata if success

        # 5. Restore scene
        originally_visible.each { |ent| ent.visible = true if ent.valid? }
        restore_position

        model.commit_operation

        if success
          ::UI.messagebox("Appliance '#{@appliance_name}' has been successfully added to the library.")
        else
          ::UI.messagebox("Some files could not be created for '#{@appliance_name}'. Check the Ruby Console for details.")
        end

        success
      rescue => e
        puts "MLCabinets: AddApplianceToLibrary error — #{e.message}" if MLCabinets::DEBUG
        model.abort_operation
        ::UI.messagebox("An error occurred while adding the appliance to the library:\n#{e.message}")
        false
      end
    end

    # -----------------------------------------------------------------
    # Validation
    # -----------------------------------------------------------------

    # Thresholds (SketchUp native = inches):
    # ALL three dimensions must be >= MIN_DIM_IN to rule out flat panels,
    # thin legs, and tiny hardware.
    # At least TWO dimensions must be >= SUBSTANTIAL_DIM_IN to confirm the
    # object is large in multiple directions (typical of real kitchen appliances).
    # The max/min ratio must stay below MAX_ELONGATION_RATIO to exclude
    # highly elongated objects such as extrusion profiles or rods.
    MIN_DIM_IN           = 3.0.freeze  # ≈ 7.6 cm  — excludes panels, handles, thin legs
    SUBSTANTIAL_DIM_IN   = 9.0.freeze  # ≈ 22.9 cm — confirms appliance-scale volume
    MAX_ELONGATION_RATIO = 12.0.freeze # ratio max_dim / min_dim upper bound

    def self.is_valid_appliance(entity)
      unless entity.is_a?(Sketchup::ComponentInstance)
        ::UI.messagebox("The selected entity must be a component instance to be added as an appliance.")
        return false
      end

      inner = entity.definition.entities
      has_geometry = inner.any? { |e|
        e.is_a?(Sketchup::Face)              ||
        e.is_a?(Sketchup::Edge)              ||
        e.is_a?(Sketchup::ComponentInstance) ||
        e.is_a?(Sketchup::Group)
      }
      unless has_geometry
        ::UI.messagebox("The selected component must contain geometry to be added as an appliance.")
        return false
      end

      bounds = entity.bounds
      dims   = [bounds.width, bounds.height, bounds.depth].sort  # [smallest, mid, largest]

      # --- Rule 1: must be volumetric — no dimension too thin ---
      if dims[0] < MIN_DIM_IN
        thin_cm = (dims[0] * 2.54).round(1)
        ::UI.messagebox(
          "The selected component is too flat or thin to be an appliance.\n\n" \
          "Thinnest dimension: #{thin_cm} cm\n" \
          "Minimum required:   #{(MIN_DIM_IN * 2.54).round(1)} cm\n\n" \
          "Appliances must have substantial depth in all three directions.\n" \
          "Panels, legs, and handles should be added under their own types."
        )
        return false
      end

      # --- Rule 2: must be large in at least two directions ---
      large_dims = dims.count { |d| d >= SUBSTANTIAL_DIM_IN }
      if large_dims < 2
        small_cm = dims.map { |v| "#{(v * 2.54).round(1)} cm" }.join(' × ')
        ::UI.messagebox(
          "The selected component is too small to be an appliance.\n\n" \
          "Bounding box: #{small_cm}\n" \
          "At least two dimensions must be ≥ #{(SUBSTANTIAL_DIM_IN * 2.54).round(1)} cm.\n\n" \
          "Typical appliances: ovens, fridges, dishwashers, range hoods, microwaves."
        )
        return false
      end

      # --- Rule 3: not overly elongated (excludes extrusion profiles, rods) ---
      elongation = dims[2] / dims[0].to_f
      if elongation >= MAX_ELONGATION_RATIO
        ::UI.messagebox(
          "The selected component appears too elongated to be an appliance " \
          "(max/min ratio #{elongation.round(1)} ≥ #{MAX_ELONGATION_RATIO.to_i}).\n\n" \
          "If this is a profile or extrusion, add it under the Profile type instead."
        )
        return false
      end

      # Cache the definition name for the default name suggestion
      defn_name = entity.definition.name
      @appliance_name = defn_name unless defn_name.to_s.strip.empty?

      true
    rescue => e
      puts "MLCabinets: AddApplianceToLibrary.is_valid_appliance error — #{e.message}" if MLCabinets::DEBUG
      ::UI.messagebox("An error occurred while validating the appliance:\n#{e.message}")
      false
    end

    # -----------------------------------------------------------------
    # Origin repositioning
    # -----------------------------------------------------------------

    def self.move_to_origin
      return unless @appliance && @appliance.valid?

      @appliance_original_transform = @appliance.transformation
      origin = @appliance.transformation.origin
      vec = Geom::Vector3d.new(-origin.x, -origin.y, -origin.z)
      @appliance.transformation = @appliance_original_transform * Geom::Transformation.translation(vec)
    end

    def self.restore_position
      return unless @appliance && @appliance.valid? && @appliance_original_transform
      @appliance.transformation = @appliance_original_transform
    end

    # -----------------------------------------------------------------
    # Screenshot (isometric, 128×128, transparent background)
    # -----------------------------------------------------------------

    def self.take_screenshot(folder = appliance_preset_folder_path)
      begin
        model = Sketchup.active_model
        view  = model.active_view

        # Save current camera
        saved_eye         = view.camera.eye
        saved_target      = view.camera.target
        saved_up          = view.camera.up
        saved_perspective = view.camera.perspective?
        saved_camera      = Sketchup::Camera.new(saved_eye, saved_target, saved_up)
        saved_camera.perspective = saved_perspective

        # Save rendering options
        ro = model.rendering_options
        saved_draw_ground        = ro['DrawGround']
        saved_draw_horizon       = ro['DrawHorizon']
        saved_draw_hidden        = ro['DrawHidden']
        saved_background         = ro['BackgroundColor']
        saved_watermarks         = ro['DisplayWatermarks']
        saved_axes               = ro['DisplaySketchAxes']
        saved_profiles           = ro['EdgeDisplayMode']
        saved_section_cuts       = ro['DisplaySectionCuts']
        saved_render_mode        = ro['RenderMode']
        saved_silhouette_width   = ro['SilhouetteWidth']
        saved_ambient_occlusion  = ro['AmbientOcclusion']

        # Set screenshot rendering options
        ro['DrawGround']         = false
        ro['DrawHorizon']        = false
        ro['BackgroundColor']    = Sketchup::Color.new(255, 255, 255, 0)
        ro['DisplayWatermarks']  = false
        ro['DisplaySketchAxes']  = false
        ro['RenderMode']         = 2     # Shaded with Textures
        ro['EdgeDisplayMode']    = 1     # Show profiles
        ro['SilhouetteWidth']    = 2
        ro['DisplaySectionCuts'] = false
        ro['AmbientOcclusion']   = false

        # Isometric camera framing
        bounds   = @appliance.bounds
        center   = bounds.center
        max_dim  = [bounds.width, bounds.height, bounds.depth].max
        distance = max_dim * 6

        eye = Geom::Point3d.new(
          center.x - distance * Math.cos(Math::PI / 6) * Math.cos(Math::PI / 6),
          center.y + distance,
          center.z + distance * 0.5
        )

        camera = Sketchup::Camera.new(eye, center, Z_AXIS)
        camera.perspective = true
        camera.fov = 10
        view.camera = camera

        # Write image
        screenshot_path = File.join(folder, "#{@appliance_name}.png")
        options = {
          :antialias   => true,
          :transparent => true,
          :compression => 0.9,
          :width       => 128,
          :height      => 128,
          :filename    => screenshot_path
        }
        screenshot = view.write_image(options)

        # Restore camera
        view.camera = saved_camera if saved_camera

        # Restore rendering options
        ro['DrawGround']         = saved_draw_ground
        ro['DrawHorizon']        = saved_draw_horizon
        ro['DrawHidden']         = saved_draw_hidden
        ro['BackgroundColor']    = saved_background
        ro['DisplayWatermarks']  = saved_watermarks
        ro['DisplaySketchAxes']  = saved_axes
        ro['EdgeDisplayMode']    = saved_profiles
        ro['DisplaySectionCuts'] = saved_section_cuts
        ro['RenderMode']         = saved_render_mode
        ro['SilhouetteWidth']    = saved_silhouette_width
        ro['AmbientOcclusion']   = saved_ambient_occlusion

        if screenshot
          return true
        else
          puts "MLCabinets: screenshot failed for #{@appliance_name}" if MLCabinets::DEBUG
          return false
        end
      rescue => e
        puts "MLCabinets: screenshot error — #{e.message}" if MLCabinets::DEBUG

        # Best-effort restore
        begin
          if defined?(ro) && ro
            ro['DrawGround']         = saved_draw_ground        if defined?(saved_draw_ground)
            ro['DrawHorizon']        = saved_draw_horizon       if defined?(saved_draw_horizon)
            ro['DrawHidden']         = saved_draw_hidden        if defined?(saved_draw_hidden)
            ro['BackgroundColor']    = saved_background         if defined?(saved_background)
            ro['DisplayWatermarks']  = saved_watermarks         if defined?(saved_watermarks)
            ro['DisplaySketchAxes']  = saved_axes               if defined?(saved_axes)
            ro['EdgeDisplayMode']    = saved_profiles           if defined?(saved_profiles)
            ro['DisplaySectionCuts'] = saved_section_cuts       if defined?(saved_section_cuts)
            ro['RenderMode']         = saved_render_mode        if defined?(saved_render_mode)
            ro['SilhouetteWidth']    = saved_silhouette_width   if defined?(saved_silhouette_width)
            ro['AmbientOcclusion']   = saved_ambient_occlusion  if defined?(saved_ambient_occlusion)
          end
        rescue => restore_err
          puts "MLCabinets: could not restore rendering options — #{restore_err.message}" if MLCabinets::DEBUG
        end

        return false
      end
    end

    # -----------------------------------------------------------------
    # Export SKP
    # -----------------------------------------------------------------

    def self.save_to_disk(folder = appliance_folder_path)
      unless @appliance
        puts "MLCabinets: No appliance set to save." if MLCabinets::DEBUG
        return false
      end

      path = File.join(folder, "#{@appliance_name}.skp")
      @appliance.definition.save_as(path)
      true
    rescue => e
      puts "MLCabinets: SKP save error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Export DAE (Collada)
    # -----------------------------------------------------------------

    def self.export_to_dae(folder = appliance_folder_path)
      unless @appliance
        puts "MLCabinets: No appliance set to export." if MLCabinets::DEBUG
        return false
      end

      model = Sketchup.active_model
      model.selection.clear
      model.selection.add(@appliance)

      path = File.join(folder, "#{@appliance_name}.dae")
      ok = model.export(path, false)

      model.selection.clear

      puts "MLCabinets: DAE export failed for #{@appliance_name}" if !ok && MLCabinets::DEBUG
      ok
    rescue => e
      puts "MLCabinets: DAE export error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Metadata
    # -----------------------------------------------------------------

    def self.save_metadata
      meta = generate_metadata
      save_individual_json(meta)
      save_to_presets_index(meta)
    rescue => e
      puts "MLCabinets: metadata save error — #{e.message}" if MLCabinets::DEBUG
    end

    def self.generate_metadata
      bounds = @appliance.bounds

      {
        'id'           => SecureRandom.uuid,
        'name'         => @appliance_name,
        'type'         => 'appliance',
        'category'     => 'appliance',
        'fixed_size'   => @fixed_size,
        'free_standing'=> @free_standing,
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => {
          'width'  => bounds.width.round(4),
          'height' => bounds.depth.round(4),
          'depth'  => bounds.height.round(4)
        },
        'description'  => "Custom appliance - #{@appliance_name.to_s.gsub('_', ' ')}",
        'thumbnail'    => "#{@appliance_name}/#{@appliance_name}.png",
        'files'        => {
          'skp'  => "#{@appliance_name}/#{@appliance_name}.skp",
          'dae'  => "#{@appliance_name}/#{@appliance_name}.dae",
          'png'  => "#{@appliance_name}/#{@appliance_name}.png",
          'json' => "#{@appliance_name}/#{@appliance_name}.json"
        },
        'geometry_data' => {
          'is_component' => true,
          'entity_count' => @appliance.definition.entities.count,
          'validated'    => true
        }
      }
    end

    def self.save_individual_json(meta)
      path = File.join(appliance_preset_folder_path, "#{@appliance_name}.json")
      File.write(path, JSON.pretty_generate(meta), encoding: 'UTF-8')
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(appliance_folder_path, 'presets.json')

      unless File.exist?(presets_file)
        File.write(presets_file, JSON.pretty_generate({ 'presets' => [] }), encoding: 'UTF-8')
      end

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      data['presets'] ||= []
      data['presets'].reject! { |p| p['name'] == @appliance_name }
      data['presets'] << meta.compact
      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

    def self.appliance_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances')
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Per-preset subfolder: libraries/appliances/{name}/
    def self.appliance_preset_folder_path
      dir = File.join(appliance_folder_path, @appliance_name)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

  end # class AddApplianceToLibrary
end # module MLCabinets
