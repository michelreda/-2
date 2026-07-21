# ML Cabinets - Add Profile to Library
# Validates a 2D profile shape (faces + edges lying on a single plane),
# screenshots it, exports SKP + JSON, and updates the centralized presets index.

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddProfileToLibrary

    @entity = nil
    @profile_name = nil
    @entity_original_transform = nil

    # -----------------------------------------------------------------
    # Public API (called by LibraryHandler)
    # -----------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @entity = entity
      @profile_name = name
    end

    # Full workflow inside a single undo operation.
    def self.process_library_addition
      model = Sketchup.active_model
      model.start_operation('Add Profile to Library', true)

      begin
        # 1. Hide everything except the profile entity
        originally_visible = []
        model.active_entities.each do |ent|
          next unless ent.respond_to?(:visible?)
          if ent.visible? && ent != @entity
            originally_visible << ent
          end
          ent.visible = false if ent != @entity && ent.respond_to?(:visible=)
        end

        # 2. Move to origin
        move_to_origin

        # 3. Screenshot + exports
        preset_folder = profile_preset_folder_path
        ok_png  = take_screenshot(preset_folder)
        ok_skp  = save_to_disk(preset_folder)
        ok_json = export_vertices_json(preset_folder)
        success = ok_png && ok_skp && ok_json

        # 4. Metadata
        save_metadata if success

        # 5. Restore scene
        originally_visible.each { |ent| ent.visible = true if ent.valid? }
        restore_position

        model.commit_operation

        if success
          ::UI.messagebox("Profile '#{@profile_name}' has been successfully added to the library.")
        else
          ::UI.messagebox("Some files could not be created for '#{@profile_name}'. Check the Ruby Console for details.")
        end

        success
      rescue => e
        puts "MLCabinets: AddProfileToLibrary error — #{e.message}" if MLCabinets::DEBUG
        model.abort_operation
        ::UI.messagebox("An error occurred while adding the profile to the library:\n#{e.message}")
        false
      end
    end

    # -----------------------------------------------------------------
    # Validation — a profile must be a component containing exactly
    # one closed face with no stray edges (a clean 2D cross-section).
    # -----------------------------------------------------------------

    def self.is_valid_profile(entity)
      unless entity.is_a?(Sketchup::ComponentInstance)
        ::UI.messagebox("The selected entity must be a component to be added as a profile.")
        return false
      end

      faces = entity.definition.entities.grep(Sketchup::Face)

      if faces.length != 1
        ::UI.messagebox(
          "The selected entity must contain exactly one closed face to be added as a profile.\n\n" \
          "A profile is a 2D cross-section shape (e.g. gola profile) that can be pushed/pulled."
        )
        return false
      end

      face = faces.first
      unless face.valid?
        ::UI.messagebox("The selected face is not valid. Please ensure it is a closed face with no stray edges.")
        return false
      end

      # Check for stray edges not part of the face
      all_edges = entity.definition.entities.grep(Sketchup::Edge)
      face_edges = face.outer_loop.edges + (face.loops - [face.outer_loop]).flat_map(&:edges)
      stray_edges = all_edges.reject { |edge| face_edges.include?(edge) }
      if stray_edges.any?
        ::UI.messagebox(
          "The selected entity contains stray edges not part of the profile face.\n" \
          "Please ensure the profile is clean and has no stray edges."
        )
        return false
      end

      # Store definition name for default naming
      defn_name = entity.definition.name
      @profile_name = defn_name unless defn_name.to_s.strip.empty?

      true
    end

    # -----------------------------------------------------------------
    # Origin repositioning
    # -----------------------------------------------------------------

    def self.move_to_origin
      return unless @entity && @entity.valid?

      @entity_original_transform = @entity.transformation
      origin = @entity.transformation.origin
      vec = Geom::Vector3d.new(-origin.x, -origin.y, -origin.z)
      @entity.transformation = @entity_original_transform * Geom::Transformation.translation(vec)
    end

    def self.restore_position
      return unless @entity && @entity.valid? && @entity_original_transform
      @entity.transformation = @entity_original_transform
    end

    # -----------------------------------------------------------------
    # Screenshot — orthographic top-down view with square zoom framing
    # (matches ML_Doors profile screenshot approach)
    # -----------------------------------------------------------------

    def self.take_screenshot(folder = profile_preset_folder_path)
      begin
        model = Sketchup.active_model
        view  = model.active_view

        # Save current camera
        saved_eye = view.camera.eye
        saved_target = view.camera.target
        saved_up = view.camera.up
        saved_perspective = view.camera.perspective?
        saved_camera = Sketchup::Camera.new(saved_eye, saved_target, saved_up)
        saved_camera.perspective = saved_perspective

        # Save rendering options
        ro = model.rendering_options
        saved_draw_ground       = ro['DrawGround']
        saved_draw_horizon      = ro['DrawHorizon']
        saved_background        = ro['BackgroundColor']
        saved_watermarks        = ro['DisplayWatermarks']
        saved_axes              = ro['DisplaySketchAxes']
        saved_profiles          = ro['EdgeDisplayMode']        
        saved_silhouette_width  = ro['SilhouetteWidth']
        saved_section_cuts      = ro['DisplaySectionCuts']

        # Set clean background for screenshot
        ro['DrawGround']        = false
        ro['DrawHorizon']       = false
        ro['BackgroundColor']   = Sketchup::Color.new(255, 255, 255)
        ro['DisplayWatermarks'] = false
        ro['DisplaySketchAxes'] = false
        ro['EdgeDisplayMode']   = 1
        ro['SilhouetteWidth']   = 3
        ro['DisplaySectionCuts']= false

        view.refresh

        # Orthographic camera looking straight down at the profile
        bounds = @entity.bounds
        center = bounds.center
        eye    = Geom::Point3d.new(center.x, center.y, center.z + 10)
        camera = Sketchup::Camera.new(eye, center, Y_AXIS)
        camera.perspective = false
        view.camera = camera

        # Create a temporary square group for proper zoom framing
        max_dim = [bounds.width, bounds.height].max
        half    = max_dim / 2.0
        square_pts = [
          Geom::Point3d.new(center.x - half, center.y - half, center.z),
          Geom::Point3d.new(center.x + half, center.y - half, center.z),
          Geom::Point3d.new(center.x + half, center.y + half, center.z),
          Geom::Point3d.new(center.x - half, center.y + half, center.z)
        ]
        temp_group = model.active_entities.add_group
        square_pts.each_with_index do |pt, i|
          temp_group.entities.add_line(pt, square_pts[(i + 1) % 4])
        end

        view.zoom(temp_group)
        temp_group.erase! if temp_group.valid?

        # Write image
        screenshot_path = File.join(folder, "#{@profile_name}.png")
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
        ro['DrawGround']        = saved_draw_ground
        ro['DrawHorizon']       = saved_draw_horizon
        ro['BackgroundColor']   = saved_background
        ro['DisplayWatermarks'] = saved_watermarks
        ro['DisplaySketchAxes'] = saved_axes
        ro['EdgeDisplayMode']   = saved_profiles
        ro['DisplaySectionCuts']= saved_section_cuts
        ro['SilhouetteWidth']   = saved_silhouette_width

        if screenshot
          return true
        else
          puts "MLCabinets: screenshot failed for #{@profile_name}" if MLCabinets::DEBUG
          return false
        end
      rescue => e
        puts "MLCabinets: screenshot error — #{e.message}" if MLCabinets::DEBUG

        begin
          if defined?(ro) && ro
            ro['DrawGround']        = saved_draw_ground      if defined?(saved_draw_ground)
            ro['DrawHorizon']       = saved_draw_horizon     if defined?(saved_draw_horizon)
            ro['BackgroundColor']   = saved_background       if defined?(saved_background)
            ro['DisplayWatermarks'] = saved_watermarks       if defined?(saved_watermarks)
            ro['DisplaySketchAxes'] = saved_axes             if defined?(saved_axes)
            ro['EdgeDisplayMode']   = saved_profiles         if defined?(saved_profiles)
            ro['DisplaySectionCuts']= saved_section_cuts     if defined?(saved_section_cuts)
          end
        rescue => restore_error
          puts "MLCabinets: could not restore rendering options — #{restore_error.message}" if MLCabinets::DEBUG
        end

        return false
      end
    end

    # -----------------------------------------------------------------
    # Export SKP
    # -----------------------------------------------------------------

    def self.save_to_disk(folder = profile_preset_folder_path)
      unless @entity
        puts "MLCabinets: No profile entity set to save." if MLCabinets::DEBUG
        return false
      end

      path = File.join(folder, "#{@profile_name}.skp")
      if @entity.is_a?(Sketchup::ComponentInstance)
        @entity.definition.save_as(path)
      else
        # For groups, wrap in a temporary component to save
        model = Sketchup.active_model
        defn = @entity.definition
        defn.save_as(path)
      end
      true
    rescue => e
      puts "MLCabinets: SKP save error — #{e.message}" if MLCabinets::DEBUG
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
      bounds = @entity.bounds
      units  = get_current_units

      # Raw dimensions in inches (SketchUp native) for DC formulas
      width_in  = bounds.width.to_f
      height_in = bounds.height.to_f

      {
        'id'           => SecureRandom.uuid,
        'name'         => @profile_name,
        'type'         => 'profile',
        'category'     => 'cabinet_profile',
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => {
          'width'  => format_dimension(bounds.width,  units),
          'height' => format_dimension(bounds.height, units),
          'depth'  => format_dimension(bounds.depth,  units)
        },
        'dimensions_raw' => {
          'width_in'  => width_in.round(4),
          'height_in' => height_in.round(4),
          'width_cm'  => (width_in * 2.54).round(4),
          'height_cm' => (height_in * 2.54).round(4)
        },
        'units'       => units,
        'description' => "Cabinet profile - #{@profile_name.to_s.gsub('_', ' ')}",
        'thumbnail'   => "#{@profile_name}/#{@profile_name}.png",
        'files'       => {
          'skp'      => "#{@profile_name}/#{@profile_name}.skp",
          'png'      => "#{@profile_name}/#{@profile_name}.png",
          'json'     => "#{@profile_name}/#{@profile_name}.json",
          'vertices' => "#{@profile_name}/#{@profile_name}_vertices.json"
        },
        'geometry_data' => {
          'is_component'  => true,
          'is_2d_profile' => true,
          'entity_count'  => @entity.definition.entities.count,
          'validated'     => true
        }
      }
    end

    def self.save_individual_json(meta)
      path = File.join(profile_preset_folder_path, "#{@profile_name}.json")
      File.write(path, JSON.pretty_generate(meta), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Export face vertices as JSON (for push-pull reconstruction)
    # -----------------------------------------------------------------

    def self.export_vertices_json(folder = profile_preset_folder_path)
      unless @entity
        puts "MLCabinets: No profile entity set to export vertices." if MLCabinets::DEBUG
        return false
      end

      begin
        face = @entity.definition.entities.grep(Sketchup::Face).first
        return false unless face

        vertices = face.outer_loop.vertices.map do |vertex|
          {
            x: (vertex.position.x.to_f * 2.54).round(2),
            y: (vertex.position.y.to_f * 2.54).round(2),
            z: (vertex.position.z.to_f * 2.54).round(2)
          }
        end

        path = File.join(folder, "#{@profile_name}_vertices.json")
        File.write(path, JSON.generate(vertices), encoding: 'UTF-8')
        true
      rescue => e
        puts "MLCabinets: vertices export error — #{e.message}" if MLCabinets::DEBUG
        false
      end
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(profile_folder_path, 'presets.json')

      unless File.exist?(presets_file)
        File.write(presets_file, JSON.pretty_generate({ 'presets' => [] }), encoding: 'UTF-8')
      end

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      data['presets'] ||= []
      data['presets'].reject! { |p| p['name'] == @profile_name }
      data['presets'] << meta.compact
      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

    def self.profile_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles')
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.profile_preset_folder_path
      dir = File.join(profile_folder_path, @profile_name)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    def self.format_dimension(value, units)
      case units
      when 'inches' then "#{value.round(1)} in"
      when 'feet'   then "#{value.round(1)} ft"
      when 'mm'     then "#{(value * 25.4).round(1)} mm"
      when 'cm'     then "#{(value * 2.54).round(1)} cm"
      when 'm'      then "#{(value * 0.0254).round(3)} m"
      else "#{value.round(1)} in"
      end
    end

    def self.get_current_units
      lu = Sketchup.active_model.options['UnitsOptions']['LengthUnit']
      case lu
      when 0 then 'inches'
      when 1 then 'feet'
      when 2 then 'mm'
      when 3 then 'cm'
      when 4 then 'm'
      else 'inches'
      end
    end

  end # class AddProfileToLibrary
end # module MLCabinets
