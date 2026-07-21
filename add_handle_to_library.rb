# ML Cabinets - Add Handle to Library
# Validates a 3D handle component and saves it to the unified
# libraries/handles/ folder. The preset's JSON entry carries a
# `handle_types` array so the dialog knows which selector(s) to surface
# it in ('Door Handle' → door handle picker, 'Drawer Handle' → drawer
# handle picker, or both).

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddHandleToLibrary

    @entity                    = nil
    @handle_name               = nil
    @entity_original_transform = nil
    @handle_types              = []

    # Unified library folder under libraries/
    HANDLE_LIBRARY_FOLDER = 'handles'.freeze

    # All handle-type labels in display order
    ALL_HANDLE_TYPES = ['Door Handle', 'Drawer Handle'].freeze

    # -----------------------------------------------------------------
    # Public API (called by AddToLibraryDialog)
    # -----------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @entity      = entity
      @handle_name = name
    end

    def self.set_handle_types(handle_types)
      @handle_types = handle_types
    end

    # Full workflow inside a single undo operation.
    def self.process_library_addition
      return false if @handle_types.nil? || @handle_types.empty?

      model = Sketchup.active_model
      model.start_operation('Add Handle to Library', true)

      begin
        # 1. Hide everything except the handle entity
        originally_visible = []
        model.active_entities.each do |ent|
          next unless ent.respond_to?(:visible?)
          originally_visible << ent if ent.visible? && ent != @entity
          ent.visible = false if ent != @entity && ent.respond_to?(:visible=)
        end

        # 2. Move to origin for a clean screenshot
        move_to_origin

        # 3. Export to the unified handles/ folder
        folder = handle_preset_folder_path

        ok_png = take_screenshot(folder)
        ok_skp = save_to_disk(folder)
        ok_dae = export_to_dae(folder)
        success = ok_png && ok_skp && ok_dae

        # 4. Write single metadata entry carrying the full handle_types array
        save_metadata(folder) if success

        # 5. Restore scene
        originally_visible.each { |ent| ent.visible = true if ent.valid? }
        restore_position

        model.commit_operation

        if success
          label_list = @handle_types.join(', ')
          ::UI.messagebox("Handle '#{@handle_name}' has been successfully added to the library.\nUsage: #{label_list}")
        else
          ::UI.messagebox("Some files could not be created for '#{@handle_name}'. Check the Ruby Console for details.")
        end

        success
      rescue => e
        puts "MLCabinets: AddHandleToLibrary error — #{e.message}" if MLCabinets::DEBUG
        model.abort_operation
        ::UI.messagebox("An error occurred while adding the handle to the library:\n#{e.message}")
        false
      end
    end

    # -----------------------------------------------------------------
    # Validation — must be a component or group with geometry.
    # Handles are 3D, so no flatness restriction is applied.
    # -----------------------------------------------------------------

    def self.is_valid_handle(entity)
      unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        ::UI.messagebox("The selected entity must be a component or group to be added as a handle.")
        return false
      end

      inner = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : entity.entities
      has_geometry = inner.any? { |e|
        e.is_a?(Sketchup::Face)              ||
        e.is_a?(Sketchup::Edge)              ||
        e.is_a?(Sketchup::ComponentInstance) ||
        e.is_a?(Sketchup::Group)
      }
      unless has_geometry
        ::UI.messagebox("The selected entity must contain geometry to be added as a handle.")
        return false
      end

      bounds = entity.bounds
      dims = [bounds.width, bounds.height, bounds.depth].sort  # [min, mid, max]

      if dims[2] < 0.1
        ::UI.messagebox("The selected entity is too small to be a valid handle.")
        return false
      end

      # Reject appliance-sized objects: if two or more dimensions are >= 9 inches
      # (~22.9 cm) the object is too large to be a door or drawer handle.
      large_dims = dims.count { |d| d >= 9.0 }
      if large_dims >= 2
        ::UI.messagebox(
          "The selected entity is too large to be a handle.\n\n" \
          "If this is an appliance (oven, fridge, etc.), add it as an Appliance instead."
        )
        return false
      end

      true
    rescue => e
      puts "MLCabinets: AddHandleToLibrary.is_valid_handle error — #{e.message}" if MLCabinets::DEBUG
      ::UI.messagebox("An error occurred while validating the handle:\n#{e.message}")
      false
    end

    # -----------------------------------------------------------------
    # Origin repositioning
    # -----------------------------------------------------------------

    def self.move_to_origin
      return unless @entity && @entity.valid?

      @entity_original_transform = @entity.transformation
      bounds = @entity.bounds
      center = bounds.center
      vec    = Geom::Vector3d.new(-center.x, -center.y, -center.z)
      @entity.transformation = @entity_original_transform * Geom::Transformation.translation(vec)
    end

    def self.restore_position
      return unless @entity && @entity.valid? && @entity_original_transform
      @entity.transformation = @entity_original_transform
    end

    # -----------------------------------------------------------------
    # Screenshot (isometric, 128×128, transparent background)
    # An isometric view is used because handles are 3D objects.
    # -----------------------------------------------------------------

    def self.take_screenshot(folder = handle_preset_folder_path)
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

        # Apply clean screenshot settings (Hidden Line)
        ro['DrawGround']         = false
        ro['DrawHorizon']        = false
        ro['BackgroundColor']    = Sketchup::Color.new(255, 255, 255, 0)
        ro['DisplayWatermarks']  = false
        ro['DisplaySketchAxes']  = false
        ro['RenderMode']         = 2    # Shaded with Textures
        ro['EdgeDisplayMode']    = 1    # Show profiles
        ro['SilhouetteWidth']    = 2
        ro['DisplaySectionCuts'] = false
        ro['AmbientOcclusion']   = false

        # Position camera at an isometric angle for a 3D hardware feel
        bounds   = @entity.bounds
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
        camera.fov = 10   # Narrow FOV reduces perspective distortion
        view.camera = camera

        # Write 128×128 image
        screenshot_path = File.join(folder, "#{@handle_name}.png")
        options = {
          antialias:   true,
          transparent: true,
          compression: 0.9,
          width:       128,
          height:      128,
          filename:    screenshot_path
        }
        result = view.write_image(options)

        # Restore camera
        view.camera = saved_camera

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

        result
      rescue => e
        puts "MLCabinets: AddHandleToLibrary screenshot error — #{e.message}" if MLCabinets::DEBUG
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
        rescue => re
          puts "MLCabinets: AddHandleToLibrary could not restore rendering options — #{re.message}" if MLCabinets::DEBUG
        end
        false
      end
    end

    # -----------------------------------------------------------------
    # Export SKP
    # -----------------------------------------------------------------

    def self.save_to_disk(folder = handle_preset_folder_path)
      unless @entity
        puts "MLCabinets: AddHandleToLibrary — no entity set to save." if MLCabinets::DEBUG
        return false
      end

      path = File.join(folder, "#{@handle_name}.skp")
      @entity.definition.save_as(path)
      true
    rescue => e
      puts "MLCabinets: AddHandleToLibrary SKP save error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Export DAE (Collada)
    # -----------------------------------------------------------------

    def self.export_to_dae(folder = handle_preset_folder_path)
      unless @entity
        puts "MLCabinets: AddHandleToLibrary — no entity set to export." if MLCabinets::DEBUG
        return false
      end

      model = Sketchup.active_model
      model.selection.clear
      model.selection.add(@entity)

      path = File.join(folder, "#{@handle_name}.dae")
      ok   = model.export(path, false)

      model.selection.clear

      puts "MLCabinets: AddHandleToLibrary DAE export failed for #{@handle_name}" if !ok && MLCabinets::DEBUG
      ok
    rescue => e
      puts "MLCabinets: AddHandleToLibrary DAE export error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Metadata
    # -----------------------------------------------------------------

    def self.save_metadata(folder = handle_preset_folder_path)
      meta = generate_metadata
      save_individual_json(meta, folder)
      save_to_presets_index(meta)
    rescue => e
      puts "MLCabinets: AddHandleToLibrary metadata save error — #{e.message}" if MLCabinets::DEBUG
    end

    def self.generate_metadata
      bounds = @entity.bounds
      units  = get_current_units

      {
        'id'           => SecureRandom.uuid,
        'name'         => @handle_name,
        'type'         => 'handle',
        'category'     => 'handle',
        # Array of handle-type labels — dialog uses this to route the preset
        # to the correct picker ('Door Handle' → door handle tab,
        # 'Drawer Handle' → drawer handle tab).
        'handle_types' => @handle_types,
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => {
          'width'  => format_dimension(bounds.width,  units),
          'height' => format_dimension(bounds.height, units),
          'depth'  => format_dimension(bounds.depth,  units)
        },
        'units'        => units,
        'description'  => "Handle - #{@handle_name.to_s.gsub('_', ' ')}",
        'thumbnail'    => "#{@handle_name}/#{@handle_name}.png",
        'files'        => {
          'skp'  => "#{@handle_name}/#{@handle_name}.skp",
          'dae'  => "#{@handle_name}/#{@handle_name}.dae",
          'png'  => "#{@handle_name}/#{@handle_name}.png",
          'json' => "#{@handle_name}/#{@handle_name}.json"
        },
        'geometry_data' => {
          'is_component' => @entity.is_a?(Sketchup::ComponentInstance),
          'entity_count' => (@entity.is_a?(Sketchup::ComponentInstance) ?
                              @entity.definition.entities.count : @entity.entities.count),
          'validated'    => true
        }
      }
    end

    def self.save_individual_json(meta, folder)
      path = File.join(folder, "#{@handle_name}.json")
      File.write(path, JSON.pretty_generate(meta), encoding: 'UTF-8')
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(handle_folder_path, 'presets.json')

      unless File.exist?(presets_file)
        File.write(presets_file, JSON.pretty_generate({ 'presets' => [] }), encoding: 'UTF-8')
      end

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      data['presets'] ||= []
      data['presets'].reject! { |p| p['name'] == @handle_name }
      data['presets'] << meta.compact
      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Paths
    # -----------------------------------------------------------------

    # Top-level folder: libraries/handles/
    def self.handle_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', HANDLE_LIBRARY_FOLDER)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Per-preset subfolder: libraries/handles/{handle_name}/
    def self.handle_preset_folder_path
      dir = File.join(handle_folder_path, @handle_name)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

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

  end # class AddHandleToLibrary
end # module MLCabinets
