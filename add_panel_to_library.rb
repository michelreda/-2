# ML Cabinets - Add Panel to Library
# Validates a flat panel component/group and saves it to the unified
# libraries/panels/ folder. The preset's JSON entry carries a `sub_types`
# array so the dialog knows which tab(s) to surface it in.

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddPanelToLibrary

    @entity = nil
    @panel_name = nil
    @entity_original_transform = nil
    @sub_types = []

    # Unified library folder under libraries/
    PANEL_LIBRARY_FOLDER = 'panels'.freeze

    # All sub-type labels in display order
    ALL_SUB_TYPES = ['Door Panel', 'Drawer Front', 'Decorative Panel', 'End Panel'].freeze

    # -----------------------------------------------------------------
    # Public API (called by add_to_library.rb)
    # -----------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @entity     = entity
      @panel_name = name
    end

    def self.set_sub_types(sub_types)
      @sub_types = sub_types
    end

    # Full workflow inside a single undo operation.
    def self.process_library_addition
      return false if @sub_types.nil? || @sub_types.empty?

      model = Sketchup.active_model
      model.start_operation('Add Panel to Library', true)

      begin
        # 1. Hide everything except the panel entity
        originally_visible = []
        model.active_entities.each do |ent|
          next unless ent.respond_to?(:visible?)
          if ent.visible? && ent != @entity
            originally_visible << ent
          end
          ent.visible = false if ent != @entity && ent.respond_to?(:visible=)
        end

        # 2. Move to origin for a clean screenshot
        move_to_origin

        # 3. Export to the unified panels/ folder
        folder = panel_preset_folder_path

        ok_png = take_screenshot(folder)
        ok_skp = save_to_disk(folder)
        ok_dae = export_to_dae(folder)
        success = ok_png && ok_skp && ok_dae

        # 4. Write single metadata entry carrying the full sub_types array
        save_metadata(folder) if success

        # 5. Restore scene
        originally_visible.each { |ent| ent.visible = true if ent.valid? }
        restore_position

        model.commit_operation

        if success
          label_list = @sub_types.join(', ')
          ::UI.messagebox("Panel '#{@panel_name}' has been successfully added to the library.\nUsage: #{label_list}")
        else
          ::UI.messagebox("Some files could not be created for '#{@panel_name}'. Check the Ruby Console for details.")
        end

        success
      rescue => e
        puts "MLCabinets: AddPanelToLibrary error — #{e.message}" if MLCabinets::DEBUG
        model.abort_operation
        ::UI.messagebox("An error occurred while adding the panel to the library:\n#{e.message}")
        false
      end
    end

    # -----------------------------------------------------------------
    # Validation — a panel must be a flat 3D component or group.
    # Orientation-agnostic: the thinnest dimension must be < half of
    # both other dimensions.
    # -----------------------------------------------------------------

    def self.is_valid_panel(entity)
      unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        ::UI.messagebox("The selected entity must be a component or group to be added as a panel.")
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
        ::UI.messagebox("The selected entity must contain geometry to be added as a panel.")
        return false
      end

      bounds = entity.bounds
      dims   = [bounds.width, bounds.depth, bounds.height].sort  # [thin, mid, large]

      if dims[2] < 0.1
        ::UI.messagebox("The selected entity is too small to be a valid panel.")
        return false
      end

      # Flat-panel check: thinnest dimension < half of both other dimensions
      unless dims[0] < dims[1] / 2.0 && dims[0] < dims[2] / 2.0
        ::UI.messagebox(
          "The selected entity does not appear to be a flat panel.\n" \
          "The thinnest dimension must be less than half of both other dimensions.\n\n" \
          "Dimensions (sorted):\n" \
          "Thin:  #{(dims[0] * 2.54).round(1)} cm\n" \
          "Mid:   #{(dims[1] * 2.54).round(1)} cm\n" \
          "Large: #{(dims[2] * 2.54).round(1)} cm"
        )
        return false
      end

      true
    rescue => e
      puts "MLCabinets: AddPanelToLibrary.is_valid_panel error — #{e.message}" if MLCabinets::DEBUG
      ::UI.messagebox("An error occurred while validating the panel:\n#{e.message}")
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
    # Screenshot (face-on front view, 256×256, transparent background)
    # -----------------------------------------------------------------

    def self.take_screenshot(folder = panel_preset_folder_path)
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
        saved_draw_ground       = ro['DrawGround']
        saved_draw_horizon      = ro['DrawHorizon']
        saved_draw_hidden       = ro['DrawHidden']
        saved_background        = ro['BackgroundColor']
        saved_watermarks        = ro['DisplayWatermarks']
        saved_axes              = ro['DisplaySketchAxes']
        saved_profiles          = ro['EdgeDisplayMode']
        saved_section_cuts      = ro['DisplaySectionCuts']
        saved_render_mode       = ro['RenderMode']
        saved_silhouette_width  = ro['SilhouetteWidth']
        saved_ambient_occlusion = ro['AmbientOcclusion']

        # Apply clean screenshot settings (Shaded with Textures)
        ro['DrawGround']         = false
        ro['DrawHorizon']        = false
        ro['BackgroundColor']    = Sketchup::Color.new(255, 255, 255, 0)
        ro['DisplayWatermarks']  = false
        ro['DisplaySketchAxes']  = false
        ro['RenderMode']         = 2     # Shaded with Textures
        ro['EdgeDisplayMode']    = 1     # Show profiles
        ro['SilhouetteWidth']    = 1
        ro['DisplaySectionCuts'] = false
        ro['AmbientOcclusion']   = false

        # Position camera face-on (looking along -Y axis)
        bounds   = @entity.bounds
        center   = bounds.center
        max_dim  = [bounds.width, bounds.depth, bounds.height].max
        distance = max_dim * 2

        eye    = Geom::Point3d.new(center.x, center.y + distance, center.z)
        target = center
        camera = Sketchup::Camera.new(eye, target, Z_AXIS)
        camera.perspective = false
        view.camera = camera

        # Zoom to fit the entity with slight padding
        view.zoom(@entity)
        view.zoom(0.9)

        # Write 256×256 image
        screenshot_path = File.join(folder, "#{@panel_name}.png")
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

        puts "MLCabinets: screenshot failed for #{@panel_name}" if !result && MLCabinets::DEBUG
        result
      rescue => e
        puts "MLCabinets: AddPanelToLibrary screenshot error — #{e.message}" if MLCabinets::DEBUG
        # Best-effort restore on error
        begin
          if defined?(ro) && ro
            ro['DrawGround']         = saved_draw_ground       if defined?(saved_draw_ground)
            ro['DrawHorizon']        = saved_draw_horizon      if defined?(saved_draw_horizon)
            ro['DrawHidden']         = saved_draw_hidden       if defined?(saved_draw_hidden)
            ro['BackgroundColor']    = saved_background        if defined?(saved_background)
            ro['DisplayWatermarks']  = saved_watermarks        if defined?(saved_watermarks)
            ro['DisplaySketchAxes']  = saved_axes              if defined?(saved_axes)
            ro['EdgeDisplayMode']    = saved_profiles          if defined?(saved_profiles)
            ro['DisplaySectionCuts'] = saved_section_cuts      if defined?(saved_section_cuts)
            ro['RenderMode']         = saved_render_mode       if defined?(saved_render_mode)
            ro['SilhouetteWidth']    = saved_silhouette_width  if defined?(saved_silhouette_width)
            ro['AmbientOcclusion']   = saved_ambient_occlusion if defined?(saved_ambient_occlusion)
          end
        rescue => re
          puts "MLCabinets: could not restore rendering options — #{re.message}" if MLCabinets::DEBUG
        end
        false
      end
    end

    # -----------------------------------------------------------------
    # Export SKP
    # -----------------------------------------------------------------

    def self.save_to_disk(folder = panel_preset_folder_path)
      unless @entity
        puts "MLCabinets: AddPanelToLibrary — no entity set to save." if MLCabinets::DEBUG
        return false
      end

      path = File.join(folder, "#{@panel_name}.skp")

      if @entity.is_a?(Sketchup::ComponentInstance)
        @entity.definition.save_as(path)
      else
        temp = @entity.to_component
        temp.definition.save_as(path)
      end

      true
    rescue => e
      puts "MLCabinets: AddPanelToLibrary SKP save error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Export DAE (Collada)
    # -----------------------------------------------------------------

    def self.export_to_dae(folder = panel_preset_folder_path)
      unless @entity
        puts "MLCabinets: AddPanelToLibrary — no entity set to export." if MLCabinets::DEBUG
        return false
      end

      model = Sketchup.active_model
      model.selection.clear
      model.selection.add(@entity)

      path = File.join(folder, "#{@panel_name}.dae")
      ok   = model.export(path, false)

      model.selection.clear

      puts "MLCabinets: AddPanelToLibrary DAE export failed for #{@panel_name}" if !ok && MLCabinets::DEBUG
      ok
    rescue => e
      puts "MLCabinets: AddPanelToLibrary DAE export error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # -----------------------------------------------------------------
    # Metadata
    # -----------------------------------------------------------------

    def self.save_metadata(folder = panel_preset_folder_path)
      meta = generate_metadata
      save_individual_json(meta, folder)
      save_to_presets_index(meta)
    rescue => e
      puts "MLCabinets: AddPanelToLibrary metadata save error — #{e.message}" if MLCabinets::DEBUG
    end

    def self.generate_metadata
      bounds    = @entity.bounds
      units     = get_current_units
      dims_list = [bounds.width, bounds.depth, bounds.height].sort

      {
        'id'           => SecureRandom.uuid,
        'name'         => @panel_name,
        'type'         => 'panel',
        'category'     => 'panel',
        # Array of sub-type labels — dialog uses this to route the preset
        # to the correct tab (Door Panel → Doors tab, Drawer Front → Drawers tab, etc.)
        'sub_types'    => @sub_types,
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => {
          'width'     => format_dimension(bounds.width,  units),
          'height'    => format_dimension(bounds.height, units),
          'thickness' => format_dimension(dims_list[0],  units)
        },
        'units'        => units,
        'description'  => "Panel - #{@panel_name.to_s.gsub('_', ' ')}",
        'thumbnail'    => "#{@panel_name}/#{@panel_name}.png",
        'files'        => {
          'skp'  => "#{@panel_name}/#{@panel_name}.skp",
          'dae'  => "#{@panel_name}/#{@panel_name}.dae",
          'png'  => "#{@panel_name}/#{@panel_name}.png",
          'json' => "#{@panel_name}/#{@panel_name}.json"
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
      path = File.join(folder, "#{@panel_name}.json")
      File.write(path, JSON.pretty_generate(meta), encoding: 'UTF-8')
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(panel_folder_path, 'presets.json')

      unless File.exist?(presets_file)
        File.write(presets_file, JSON.pretty_generate({ 'presets' => [] }), encoding: 'UTF-8')
      end

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      data['presets'] ||= []
      data['presets'].reject! { |p| p['name'] == @panel_name }
      data['presets'] << meta.compact
      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Paths
    # -----------------------------------------------------------------

    # Top-level folder: libraries/panels/
    def self.panel_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', PANEL_LIBRARY_FOLDER)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Per-preset subfolder: libraries/panels/{panel_name}/
    def self.panel_preset_folder_path
      dir = File.join(panel_folder_path, @panel_name)
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

  end # class AddPanelToLibrary
end # module MLCabinets
