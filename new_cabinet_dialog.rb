# ML Cabinets - New Cabinet Dialog
# Opens the New Cabinet HTML dialog and forwards the submitted config to Ruby.

module MLCabinets
  module Dialogs

    # Blocks any selection change while the edit dialog is open.
    class EditSelectionLock < Sketchup::SelectionObserver
      def initialize(locked_entities)
        @locked  = locked_entities
        @guarded = false
      end

      def onSelectionBulkChange(selection)
        return if @guarded
        @guarded = true
        selection.clear
        selection.add(@locked) unless @locked.empty?
        @guarded = false
      end

      def onSelectionCleared(selection)
        return if @guarded
        @guarded = true
        selection.add(@locked) unless @locked.empty?
        @guarded = false
      end
    end

    class NewCabinetDialog

      @@instance = nil

      # -----------------------------------------------------------------------
      # Singleton interface
      # -----------------------------------------------------------------------

      def self.show
        unless MLCabinets::LicenseManager.licensed?
          show_license_expired_message
          return
        end
        @@instance ||= new
        @@instance.show
      end

      def self.show_edit(entity)
        @@instance ||= new
        @@instance.show_edit(entity)
      end

      def self.show_bulk_edit(entities)
        @@instance ||= new
        @@instance.show_bulk_edit(entities)
      end

      def self.close
        @@instance&.close
        @@instance = nil
      end

      def self.instance
        @@instance
      end

      def self.show_license_expired_message
        state = MLCabinets::LicenseManager.state
        msg = if state == :trial_expired
          "Your 14-day trial has expired.\n\nActivate a license to continue creating cabinets."
        else
          "Your license is no longer active.\n\nPlease activate a valid license to continue."
        end
        UI.messagebox(msg, MB_OK)
        MLCabinets::Dialogs::AboutDialog.show
      end

      # -----------------------------------------------------------------------
      # Instance
      # -----------------------------------------------------------------------

      def initialize
        @dialog = nil
        @edit_entity = nil     # non-nil when in single edit mode
        @bulk_entities = nil   # non-nil when in bulk edit mode
        @selection_observer = nil
        @locked_selection = nil
      end

      def show
        @edit_entity = nil
        @bulk_entities = nil
        if @dialog&.visible?
          @dialog.bring_to_front
        else
          create_dialog
          @dialog.show
        end
      end

      def show_edit(entity)
        @edit_entity = entity
        @bulk_entities = nil
        # Always close and reopen to ensure a clean edit-mode state
        if @dialog&.visible?
          @dialog.set_on_closed {}   # neutralize async callback
          @dialog.close
          @dialog = nil
        end
        _unlock_selection            # clean up any previous lock
        _lock_selection
        create_dialog('Edit Cabinet', edit_mode: true)
        @dialog.show
      end

      def show_bulk_edit(entities)
        @edit_entity = nil
        @bulk_entities = entities
        if @dialog&.visible?
          @dialog.set_on_closed {}   # neutralize async callback
          @dialog.close
          @dialog = nil
        end
        _unlock_selection            # clean up any previous lock
        _lock_selection
        create_dialog("Edit #{entities.size} Cabinets", edit_mode: true)
        @dialog.show
      end

      def close
        @edit_entity = nil
        @bulk_entities = nil
        _unlock_selection
        @dialog&.close
        @dialog = nil
      end

      def visible?
        @dialog&.visible? || false
      end

      # -----------------------------------------------------------------------
      private
      # -----------------------------------------------------------------------

      # Freeze the current SketchUp selection while the edit dialog is open.
      def _lock_selection
        sel = Sketchup.active_model.selection
        @locked_selection   = sel.to_a
        @selection_observer = EditSelectionLock.new(@locked_selection)
        sel.add_observer(@selection_observer)
      end

      def _unlock_selection
        return unless @selection_observer
        Sketchup.active_model.selection.remove_observer(@selection_observer)
        @selection_observer = nil
        @locked_selection   = nil
      end

      def create_dialog(title = 'New Cabinet', edit_mode: false)
        w, h, min_w, min_h, max_w, max_h = edit_mode ? [530, 750, 530, 620, 640, 950] : [820, 640, 960, 620, 1280, 768]
        @dialog = ::UI::HtmlDialog.new(
          dialog_title:     title,
          preferences_key:  'MLCabinets_NewCabinet',
          style:            ::UI::HtmlDialog::STYLE_DIALOG,
          use_content_size: true,
          width:            w,
          height:           h,
          min_width:        min_w,
          min_height:       min_h,
          max_width:        max_w,
          max_height:       max_h
        )
        html_path = File.join(MLCabinets::PLUGIN_DIR, 'dialogs', 'new_cabinet', 'new_cabinet.html')
        @dialog.set_file(html_path)
        setup_callbacks
        @dialog.set_on_closed { _unlock_selection }
      end

      def push_license_status(json)
        return unless @dialog&.visible?
        @dialog.execute_script("window.setLicenseStatus(#{json.to_json})")
      rescue => e
        puts "MLCabinets NewCabinetDialog#push_license_status: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      end

      def setup_callbacks
        # JS calls sketchup.close_dialog() when the user hits Cancel
        @dialog.add_action_callback('close_dialog') { |_| close }

        # JS fires sketchup.dialog_ready() on DOMContentLoaded; Ruby replies
        # with the active model's unit system so the dialog shows the right
        # labels and default values.
        @dialog.add_action_callback('dialog_ready') do |_|
          unit = detect_units
          # Inject library presets BEFORE setUnits — restoreFormState (called
          # from setUnits) needs the preset arrays populated to restore
          # saved selector state.
          inject_leg_presets
          inject_appliance_presets
          inject_profile_presets
          inject_panel_presets
          inject_panel_face_presets
          inject_handle_presets
          inject_material_presets

          # In edit / bulk-edit mode, set the flag BEFORE setUnits so that
          # the session-state wrapper skips restoreFormState().
          if @edit_entity
            @dialog.execute_script('_editMode = true')
          elsif @bulk_entities
            @dialog.execute_script('_editMode = true')
            @dialog.execute_script('_bulkMode = true')
          end

          @dialog.execute_script("window.setUnits('#{unit}')")

          # If in edit mode, send the stored config to JS to populate the form
          if @edit_entity
            config = CabinetDC.extract_config(@edit_entity)
            if config
              # Use to_json to produce a safely-escaped JS string literal
              js_str = JSON.generate(config).to_json  # double-quoted JS string
              @dialog.execute_script("window.loadEditConfig(#{js_str})")
            else
              puts 'MLCabinets: No stored config found on cabinet — edit mode unavailable' if MLCabinets::DEBUG
              @edit_entity = nil
            end

          # If in bulk edit mode, merge configs from all cabinets and send
          elsif @bulk_entities
            configs = @bulk_entities.filter_map { |e| CabinetDC.extract_config(e) }
            if configs.size >= 2
              result = CabinetDC.merge_configs(configs)
              merged_js = JSON.generate(result[:merged]).to_json
              mixed_js  = JSON.generate(result[:mixed]).to_json
              @dialog.execute_script("window.loadBulkEditConfig(#{merged_js}, #{mixed_js})")
            else
              puts 'MLCabinets: Not enough valid configs for bulk edit' if MLCabinets::DEBUG
              @bulk_entities = nil
            end
          end

          @dialog.execute_script("window.setLicenseStatus(#{license_status_json})")
        end

        @dialog.add_action_callback('open_about_dialog') { |_|
          MLCabinets::Dialogs::AboutDialog.show
        }

        # JS calls sketchup.delete_preset(jsonString) to remove a user preset
        @dialog.add_action_callback('delete_preset') do |_, params_json|
          begin
            params = JSON.parse(params_json, symbolize_names: true)
            delete_user_preset(params[:type], params[:name])
          rescue => e
            puts "MLCabinets: delete_preset error — #{e.message}" if MLCabinets::DEBUG
          end
        end

        # JS calls sketchup.create_cabinet(jsonString) when the user hits Create
        @dialog.add_action_callback('create_cabinet') do |_, params_json|
          begin
            config = JSON.parse(params_json, symbolize_names: true)
            puts "[MLCabinets] New cabinet config received: #{config.inspect}" if MLCabinets::DEBUG

            result = MLCabinets::CabinetDC.build_definition(config)
            if result
              close
              tool = MLCabinets::UI::PlacementTool.new(result)
              Sketchup.active_model.select_tool(tool)
            else
              puts "MLCabinets: build_definition returned nil" if MLCabinets::DEBUG
            end
          rescue => e
            puts "MLCabinets: create_cabinet error — #{e.message}"
          end
        end

        # JS calls sketchup.apply_cabinet(jsonString) when the user hits Apply (edit mode)
        @dialog.add_action_callback('apply_cabinet') do |_, params_json|
          begin
            config = JSON.parse(params_json, symbolize_names: true)
            puts "[MLCabinets] Edit cabinet config received: #{config.inspect}" if MLCabinets::DEBUG

            entity = @edit_entity
            unless entity&.valid?
              puts 'MLCabinets: Edit target entity is no longer valid' if MLCabinets::DEBUG
              close
              next
            end

            result = MLCabinets::CabinetDC.update_cabinet(entity, config)
            unless result
              puts 'MLCabinets: update_cabinet returned nil' if MLCabinets::DEBUG
            end
          rescue => e
            puts "MLCabinets: apply_cabinet error — #{e.message}"
            e.backtrace.first(3).each { |line| puts "    #{line}" }
          end
        end

        # JS calls sketchup.apply_bulk_cabinet(jsonString) when the user
        # hits Apply in bulk-edit mode. The payload contains only the fields
        # the user actually changed. We merge each changed field into each
        # cabinet's original config and update them all.
        # Each update_cabinet call uses start_operation(…, true) (transparent),
        # so all updates merge into a single Undo step.
        @dialog.add_action_callback('apply_bulk_cabinet') do |_, params_json|
          begin
            partial = JSON.parse(params_json, symbolize_names: true)
            puts "[MLCabinets] Bulk edit partial config: #{partial.inspect}" if MLCabinets::DEBUG

            entities = @bulk_entities || []
            valid = entities.select(&:valid?)
            if valid.empty?
              puts 'MLCabinets: No valid bulk-edit targets remain' if MLCabinets::DEBUG
              close
              next
            end

            failed = 0
            valid.each do |entity|
              original = CabinetDC.extract_config(entity)
              unless original
                failed += 1
                next
              end

              merged = CabinetDC.deep_merge_partial(original, partial)
              result = CabinetDC.update_cabinet(entity, merged)
              failed += 1 unless result
            end

            puts "[MLCabinets] Bulk edit complete: #{valid.size - failed}/#{valid.size} updated" if MLCabinets::DEBUG
          rescue => e
            puts "MLCabinets: apply_bulk_cabinet error — #{e.message}"
            e.backtrace.first(4).each { |line| puts "    #{line}" }
          end
        end
      end

      def license_status_json
        info = MLCabinets::LicenseManager.license_info
        JSON.generate(
          state:                info[:state].to_s,
          days_left:            info[:days_left],
          expiry_date:          info[:expiry_date],
          type:                 info[:type],
          connectivity_warning: MLCabinets::LicenseManager.connectivity_warning?
        )
      end

      def detect_units
        # LengthUnit: 0 = Inches, 1 = Feet  →  'in'
        #             2 = mm, 3 = cm, 4 = m  →  'cm'
        lu = Sketchup.active_model.options['UnitsOptions']['LengthUnit']
        (lu == 0 || lu == 1) ? 'in' : 'cm'
      end

      # Deletes a user-created preset from disk and updates presets.json.
      def delete_user_preset(type, name)
        return unless type && name

        type_folder = case type.to_s
                      when 'leg'         then 'legs'
                      when 'appliance'   then 'appliances'
                      when 'profile'     then 'profiles'
                      when 'handle'      then 'handles'
                      when 'material'    then 'materials'
                      when 'panel',
                           'drawer_face' then 'panels'  # 'drawer_face' kept for legacy presets
                      else return
                      end

        base_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', type_folder)
        preset_dir = File.join(base_dir, name.to_s)

        # Remove the preset subfolder and all its files
        if Dir.exist?(preset_dir)
          FileUtils.rm_rf(preset_dir)
          puts "MLCabinets: Deleted preset folder #{preset_dir}" if MLCabinets::DEBUG
        end

        # Update presets.json index
        presets_file = File.join(base_dir, 'presets.json')
        if File.exist?(presets_file)
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          data['presets'] ||= []
          data['presets'].reject! { |p| p['name'] == name.to_s }
          File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
        end
      rescue => e
        puts "MLCabinets: delete_user_preset error — #{e.message}" if MLCabinets::DEBUG
      end

      # Reads user-created appliance presets from libraries/appliances/presets.json
      # and injects them into the dialog so the JS APPLIANCE_PRESETS array is populated.
      def inject_appliance_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          js_presets = data['presets'].map do |p|
            thumb = p['thumbnail']
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', thumb)
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end
            {
              id:        p['name'],
              label:     (p['name'] || '').gsub('_', ' '),
              source:    p['user_created'] ? 'user' : 'builtin',
              thumbnail: thumb
            }
          end

          json_str = JSON.generate({ 'presets' => js_presets }).gsub("'", "\\\\'")
          @dialog.execute_script("window.initAppliancePresets('#{json_str}')")
        rescue => e
          puts "MLCabinets: inject_appliance_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Reads user-created leg presets from libraries/legs/presets.json and
      # injects them into the dialog so the JS LEG_PRESETS array is extended.
      def inject_leg_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'legs', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          # Build a JS-friendly array of preset objects matching LEG_PRESETS shape
          js_presets = data['presets'].map do |p|
            thumb = p['thumbnail']
            # Resolve thumbnail to an absolute file:// URL so <img> can display it
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'legs', thumb)
              # thumb is now "{name}/{name}.png" — resolve relative to legs/
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end
            {
              id:        p['name'],
              label:     (p['name'] || '').gsub('_', ' '),
              source:    p['user_created'] ? 'user' : 'builtin',
              thumbnail: thumb
            }
          end

          json_str = JSON.generate(js_presets).gsub("'", "\\\\'")
          @dialog.execute_script("window.initLegPresets('#{json_str}')")
        rescue => e
          puts "MLCabinets: inject_leg_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Reads panel presets from libraries/panels/presets.json and injects them
      # into the dialog. Each preset's `sub_types` array controls which tab receives it:
      #   'Door Panel'   → window.initDoorPanelPresets   (Doors tab)
      #   'Drawer Front' → window.initDrawerFrontPresets (Drawers tab)
      # A preset tagged for both sub-types is injected into both.
      def inject_panel_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          door_js    = []
          drawer_js  = []

          data['presets'].each do |p|
            thumb = p['thumbnail']
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', thumb)
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end

            entry = {
              id:        p['name'],
              label:     (p['name'] || '').gsub('_', ' '),
              source:    p['user_created'] ? 'user' : 'builtin',
              thumbnail: thumb
            }

            sub_types = Array(p['sub_types'] || p['sub_type'])
            door_js   << entry if sub_types.include?('Door Panel')
            drawer_js << entry if sub_types.include?('Drawer Front')
          end

          unless door_js.empty?
            json_str = JSON.generate(door_js).gsub("'", "\\\\'")
            @dialog.execute_script("window.initDoorPanelPresets('#{json_str}')")
          end

          unless drawer_js.empty?
            json_str = JSON.generate(drawer_js).gsub("'", "\\\\'")
            @dialog.execute_script("window.initDrawerFrontPresets('#{json_str}')")
          end
        rescue => e
          puts "MLCabinets: inject_panel_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Reads panel presets filtered to 'Decorative Panel' and 'End Panel' sub-types
      # and injects them into the Panels tab via window.initPanelFacePresets.
      def inject_panel_face_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          panel_face_types = ['End Panel', 'Decorative Panel']
          entries = data['presets'].select do |p|
            sub_types = Array(p['sub_types'] || p['sub_type'])
            sub_types.any? { |st| panel_face_types.include?(st.to_s) }
          end
          return if entries.empty?

          js_presets = entries.map do |p|
            thumb = p['thumbnail']
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', thumb)
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end
            {
              id:        p['name'],
              label:     (p['name'] || '').gsub('_', ' '),
              source:    p['user_created'] ? 'user' : 'builtin',
              thumbnail: thumb
            }
          end

          json_str = JSON.generate(js_presets).gsub("'", "\\\\'")
          @dialog.execute_script("window.initPanelFacePresets('#{json_str}')")
        rescue => e
          puts "MLCabinets: inject_panel_face_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Reads user-created handle presets from libraries/handles/presets.json and
      # injects them into the dialog. Each preset's `handle_types` array controls
      # which selector receives it:
      #   'Door Handle'   → window.initHandlePresets    (Doors tab)
      #   'Drawer Handle' → window.initDrawerHandlePresets (Drawers tab)
      # A preset tagged for both handle types is injected into both.
      def inject_handle_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'handles', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          door_js   = []
          drawer_js = []

          data['presets'].each do |p|
            thumb = p['thumbnail']
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'handles', thumb)
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end

            entry = {
              id:        p['name'],
              label:     (p['name'] || '').gsub('_', ' '),
              source:    p['user_created'] ? 'user' : 'builtin',
              thumbnail: thumb
            }

            handle_types = Array(p['handle_types'] || p['handle_type'])
            door_js   << entry if handle_types.include?('Door Handle')
            drawer_js << entry if handle_types.include?('Drawer Handle')
          end

          unless door_js.empty?
            json_str = JSON.generate({ 'presets' => door_js }).gsub("'", "\\\\'")
            @dialog.execute_script("window.initHandlePresets('#{json_str}')")
          end

          unless drawer_js.empty?
            json_str = JSON.generate({ 'presets' => drawer_js }).gsub("'", "\\\\'")
            @dialog.execute_script("window.initDrawerHandlePresets('#{json_str}')")
          end
        rescue => e
          puts "MLCabinets: inject_handle_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Reads user-created profile presets from libraries/profiles/presets.json
      # and injects them into the dialog so the JS PROFILE_PRESETS array is extended.
      def inject_profile_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          js_presets = data['presets'].map do |p|
            thumb = p['thumbnail']
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles', thumb)
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end
            raw = p['dimensions_raw'] || {}
            {
              id:        p['name'],
              label:     (p['name'] || '').gsub('_', ' '),
              source:    p['user_created'] ? 'user' : 'builtin',
              thumbnail: thumb,
              width_cm:  raw['width_cm'] || 0,
              width_in:  raw['width_in'] || 0,
              height_cm: raw['height_cm'] || 0,
              height_in: raw['height_in'] || 0
            }
          end

          json_str = JSON.generate(js_presets).gsub("'", "\\\\'")
          @dialog.execute_script("window.initProfilePresets('#{json_str}')")
        rescue => e
          puts "MLCabinets: inject_profile_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Reads user-created material presets from libraries/materials/presets.json
      # and injects them into the dialog so the JS MATERIAL_PRESETS array is extended.
      def inject_material_presets
        presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'materials', 'presets.json')
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          return unless data['presets'].is_a?(Array) && !data['presets'].empty?

          js_presets = data['presets'].map do |p|
            thumb = p['thumbnail']
            if thumb && !thumb.start_with?('file://', 'http://', 'https://')
              abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'materials', thumb)
              thumb = "file:///#{abs.gsub('\\', '/')}" if File.exist?(abs)
            end
            {
              id:        p['name'],
              label:       (p['name'] || '').gsub('_', ' '),
              source:      p['source'] || p['category'] || 'builtin',
              category:    p['category'] || p['source'],
              thumbnail:   thumb,
              color:       p['color'],
              grain:       p['grain'],
              user_created: !!p['user_created']
            }
          end

          json_str = JSON.generate(js_presets).gsub("'", "\\\\'")
          @dialog.execute_script("window.initMaterialPresets('#{json_str}')")
        rescue => e
          puts "MLCabinets: inject_material_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

    end # class NewCabinetDialog
  end # module Dialogs
end # module MLCabinets
