# ML Cabinets - Add Leg to Library
# Validates a leg component, screenshots it, exports SKP+DAE+JSON,
# and updates the centralized presets index.

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddLegToLibrary

    @leg = nil
    @leg_name = nil
    @leg_original_transform = nil

    # -----------------------------------------------------------------
    # Public API (called by LibraryHandler)
    # -----------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @leg = entity
      @leg_name = name
    end

    # Full workflow inside a single undo operation.
    def self.process_library_addition
      model = Sketchup.active_model
      model.start_operation('Add Leg to Library', true)

      begin
        # 1. Hide everything except the leg
        originally_visible = []
        model.active_entities.each do |ent|
          next unless ent.respond_to?(:visible?)
          if ent.visible? && ent != @leg
            originally_visible << ent
          end
          ent.visible = false if ent != @leg && ent.respond_to?(:visible=)
        end

        # 2. Move to origin
        move_to_origin

        # 3. Screenshot + exports
        preset_folder = leg_preset_folder_path
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
          ::UI.messagebox("Leg '#{@leg_name}' has been successfully added to the library.")
        else
          ::UI.messagebox("Some files could not be created for '#{@leg_name}'. Check the Ruby Console for details.")
        end

        success
      rescue => e
        puts "MLCabinets: AddLegToLibrary error — #{e.message}" if MLCabinets::DEBUG
        model.abort_operation
        ::UI.messagebox("An error occurred while adding the leg to the library:\n#{e.message}")
        false
      end
    end

    # -----------------------------------------------------------------
    # Validation
    # -----------------------------------------------------------------

    def self.is_valid_leg(entity)
      unless entity.is_a?(Sketchup::ComponentInstance)
        ::UI.messagebox("The selected entity must be a component instance to be added as a leg.")
        return false
      end

      entities = entity.definition.entities
      has_geometry = entities.any? { |e|
        e.is_a?(Sketchup::Face) ||
        e.is_a?(Sketchup::Edge) ||
        e.is_a?(Sketchup::ComponentInstance) ||
        e.is_a?(Sketchup::Group)
      }
      unless has_geometry
        ::UI.messagebox("The selected component must contain geometry to be added as a leg.")
        return false
      end

      bounds = entity.bounds
      w = bounds.width
      h = bounds.height
      d = bounds.depth

      min_dim = 0.1
      if w < min_dim && h < min_dim && d < min_dim
        ::UI.messagebox("The selected component is too small to be considered a valid leg.")
        return false
      end

      # Store definition name for default naming
      defn_name = entity.definition.name
      @leg_name = defn_name unless defn_name.to_s.strip.empty?

      true
    end

    # -----------------------------------------------------------------
    # Origin repositioning
    # -----------------------------------------------------------------

    def self.move_to_origin
      return unless @leg && @leg.valid?

      @leg_original_transform = @leg.transformation
      origin = @leg.transformation.origin
      vec = Geom::Vector3d.new(-origin.x, -origin.y, -origin.z)
      @leg.transformation = @leg_original_transform * Geom::Transformation.translation(vec)
    end

    def self.restore_position
      return unless @leg && @leg.valid? && @leg_original_transform
      @leg.transformation = @leg_original_transform
    end

    # -----------------------------------------------------------------
    # Screenshot (isometric, 256×256, transparent background)
    # -----------------------------------------------------------------

    def self.take_screenshot(folder = leg_preset_folder_path)
      begin
        model = Sketchup.active_model
        view  = model.active_view

        # Save the current camera position
        saved_eye = view.camera.eye
        saved_target = view.camera.target
        saved_up = view.camera.up
        saved_perspective = view.camera.perspective?
        saved_camera = Sketchup::Camera.new(saved_eye, saved_target, saved_up)
        saved_camera.perspective = saved_perspective

        # Save current background and rendering options
        rendering_options = model.rendering_options
        saved_draw_ground       = rendering_options['DrawGround']
        saved_draw_horizon      = rendering_options['DrawHorizon']
        saved_draw_hidden       = rendering_options['DrawHidden']
        saved_background        = rendering_options['BackgroundColor']
        saved_watermarks        = rendering_options['DisplayWatermarks']
        saved_axes              = rendering_options['DisplaySketchAxes']
        saved_profiles          = rendering_options['EdgeDisplayMode']
        saved_section_cuts      = rendering_options['DisplaySectionCuts']
        saved_render_mode       = rendering_options['RenderMode']
        saved_silhouette_width  = rendering_options['SilhouetteWidth']
        saved_ambient_occlusion = rendering_options['AmbientOcclusion']

        # Set up optimal view settings for screenshot
        rendering_options['DrawGround']        = false
        rendering_options['DrawHorizon']       = false
        rendering_options['BackgroundColor']   = Sketchup::Color.new(255, 255, 255, 0)
        rendering_options['DisplayWatermarks'] = false
        rendering_options['DisplaySketchAxes'] = false
        rendering_options['RenderMode']        = 2     # Shaded with Textures
        rendering_options['EdgeDisplayMode']   = 1     # Show profiles
        rendering_options['SilhouetteWidth']   = 2     # Default silhouette width
        rendering_options['DisplaySectionCuts']= false
        rendering_options['AmbientOcclusion']  = false

        # Get the bounds and calculate camera position
        bounds  = @leg.bounds
        center  = bounds.center
        max_dim = [bounds.width, bounds.height, bounds.depth].max
        distance = max_dim * 6  # Distance multiplier for good framing

        # Position camera at an isometric angle
        eye = Geom::Point3d.new(
          center.x + distance,
          center.y - distance,
          center.z + distance * 0.5
        )

        camera = Sketchup::Camera.new(eye, center, Z_AXIS)
        camera.perspective = true
        camera.fov = 10  # Narrow FOV reduces perspective distortion
        view.camera = camera

        # Write image
        screenshot_path = File.join(folder, "#{@leg_name}.png")
        options = {
          :antialias   => true,
          :transparent => true,
          :compression => 0.9,
          :width       => 128,
          :height      => 128,
          :filename    => screenshot_path
        }
        screenshot = view.write_image(options)

        # Restore the original camera position
        if saved_camera
          view.camera = saved_camera
        else
          puts "MLCabinets: saved camera was not valid, unable to restore." if MLCabinets::DEBUG
        end

        # Restore original rendering options
        rendering_options['DrawGround']         = saved_draw_ground
        rendering_options['DrawHorizon']        = saved_draw_horizon
        rendering_options['DrawHidden']         = saved_draw_hidden
        rendering_options['BackgroundColor']    = saved_background
        rendering_options['DisplayWatermarks']  = saved_watermarks
        rendering_options['DisplaySketchAxes']  = saved_axes
        rendering_options['EdgeDisplayMode']    = saved_profiles
        rendering_options['DisplaySectionCuts'] = saved_section_cuts
        rendering_options['RenderMode']         = saved_render_mode
        rendering_options['SilhouetteWidth']    = saved_silhouette_width
        rendering_options['AmbientOcclusion']   = saved_ambient_occlusion
        if screenshot
          return true
        else
          puts "MLCabinets: screenshot failed for #{@leg_name}" if MLCabinets::DEBUG
          return false
        end
      rescue => e
        puts "MLCabinets: screenshot error — #{e.message}" if MLCabinets::DEBUG

        # Restore rendering options even on error
        begin
          if defined?(rendering_options) && rendering_options
            rendering_options['DrawGround']        = saved_draw_ground      if defined?(saved_draw_ground)
            rendering_options['DrawHorizon']       = saved_draw_horizon     if defined?(saved_draw_horizon)
            rendering_options['DrawHidden']        = saved_draw_hidden      if defined?(saved_draw_hidden)
            rendering_options['BackgroundColor']   = saved_background       if defined?(saved_background)
            rendering_options['DisplayWatermarks'] = saved_watermarks       if defined?(saved_watermarks)
            rendering_options['DisplaySketchAxes'] = saved_axes             if defined?(saved_axes)
            rendering_options['EdgeDisplayMode']   = saved_profiles         if defined?(saved_profiles)
            rendering_options['DisplaySectionCuts']= saved_section_cuts     if defined?(saved_section_cuts)
            rendering_options['RenderMode']        = saved_render_mode      if defined?(saved_render_mode)
            rendering_options['SilhouetteWidth']   = saved_silhouette_width if defined?(saved_silhouette_width)
            rendering_options['AmbientOcclusion']  = saved_ambient_occlusion if defined?(saved_ambient_occlusion)
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

    def self.save_to_disk(folder = leg_folder_path)
      unless @leg
        puts "MLCabinets: No leg set to save." if MLCabinets::DEBUG
        return false
      end

      path = File.join(folder, "#{@leg_name}.skp")
      @leg.definition.save_as(path)
      true
    rescue => e
      puts "MLCabinets: SKP save error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Export DAE (Collada)
    # -----------------------------------------------------------------

    def self.export_to_dae(folder = leg_folder_path)
      unless @leg
        puts "MLCabinets: No leg set to export." if MLCabinets::DEBUG
        return false
      end

      model = Sketchup.active_model
      model.selection.clear
      model.selection.add(@leg)

      path = File.join(folder, "#{@leg_name}.dae")
      ok = model.export(path, false)

      model.selection.clear

      puts "MLCabinets: DAE export failed for #{@leg_name}" if !ok && MLCabinets::DEBUG
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
      bounds = @leg.bounds
      units  = get_current_units

      {
        'id'           => SecureRandom.uuid,
        'name'         => @leg_name,
        'type'         => 'leg',
        'category'     => 'cabinet_leg',
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => {
          'width'  => format_dimension(bounds.width,  units),
          'height' => format_dimension(bounds.height, units),
          'depth'  => format_dimension(bounds.depth,  units)
        },
        'units'       => units,
        'description' => "Custom cabinet leg - #{@leg_name.to_s.gsub('_', ' ')}",
        'thumbnail'   => "#{@leg_name}/#{@leg_name}.png",
        'files'       => {
          'skp'  => "#{@leg_name}/#{@leg_name}.skp",
          'dae'  => "#{@leg_name}/#{@leg_name}.dae",
          'png'  => "#{@leg_name}/#{@leg_name}.png",
          'json' => "#{@leg_name}/#{@leg_name}.json"
        },
        'geometry_data' => {
          'is_component'  => true,
          'entity_count'  => @leg.definition.entities.count,
          'validated'     => true
        }
      }
    end

    def self.save_individual_json(meta)
      path = File.join(leg_preset_folder_path, "#{@leg_name}.json")
      File.write(path, JSON.pretty_generate(meta), encoding: 'UTF-8')
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(leg_folder_path, 'presets.json')

      unless File.exist?(presets_file)
        File.write(presets_file, JSON.pretty_generate({ 'presets' => [] }), encoding: 'UTF-8')
      end

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      data['presets'] ||= []
      data['presets'].reject! { |p| p['name'] == @leg_name }
      data['presets'] << meta.compact
      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

    def self.leg_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'legs')
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Per-preset subfolder: libraries/legs/{name}/
    def self.leg_preset_folder_path
      dir = File.join(leg_folder_path, @leg_name)
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

  end # class AddLegToLibrary
end # module MLCabinets
