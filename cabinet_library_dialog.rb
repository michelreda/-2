# ML Cabinets - Cabinet Library Dialog
# Opens a grid of saved cabinet presets.  Clicking a preset reads its stored
# config JSON, builds the cabinet definition, and activates PlacementTool.

require 'sketchup.rb'
require 'json'

module MLCabinets
  module Dialogs
    class CabinetLibraryDialog

      @@instance = nil

      # -----------------------------------------------------------------------
      # Singleton interface
      # -----------------------------------------------------------------------

      def self.show
        @@instance ||= new
        @@instance.show
      end

      def self.close
        @@instance&.close
        @@instance = nil
      end

      def self.instance
        @@instance
      end

      # -----------------------------------------------------------------------
      # Instance
      # -----------------------------------------------------------------------

      def initialize
        @dialog = nil
      end

      def show
        if @dialog&.visible?
          @dialog.bring_to_front
        else
          create_dialog
          @dialog.show
        end
      end

      def close
        @dialog&.close
        @dialog = nil
      end

      def visible?
        @dialog&.visible? || false
      end

      # Re-inject all preset data into the open dialog.
      def refresh
        return unless @dialog&.visible?
        inject_cabinet_presets
        inject_door_panel_presets
        inject_door_handle_presets
        inject_drawer_front_presets
        inject_drawer_handle_presets
        inject_panels_presets
        inject_leg_presets
        inject_material_presets
        inject_appliance_presets
      end

      # Class-level convenience
      def self.refresh
        @@instance&.refresh
      end

      # -----------------------------------------------------------------------
      private
      # -----------------------------------------------------------------------

      def create_dialog
        @dialog = ::UI::HtmlDialog.new(
          dialog_title:     'Library',
          preferences_key:  'MLCabinets_CabinetLibrary',
          style:            ::UI::HtmlDialog::STYLE_DIALOG,
          use_content_size: true,
          width:            374,
          height:           560,
          min_width:        360,
          min_height:       560
        )
        html_path = File.join(
          MLCabinets::PLUGIN_DIR, 'dialogs', 'cabinet_library', 'cabinet_library.html'
        )
        @dialog.set_file(html_path)
        setup_callbacks
      end

      def push_license_status(json)
        return unless @dialog&.visible?
        @dialog.execute_script("window.setLicenseStatus(#{json.to_json})")
      rescue => e
        puts "MLCabinets CabinetLibraryDialog#push_license_status: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      end

      def setup_callbacks
        @dialog.add_action_callback('dialog_ready') do |_|
          inject_cabinet_presets
          inject_door_panel_presets
          inject_door_handle_presets
          inject_drawer_front_presets
          inject_drawer_handle_presets
          inject_panels_presets
          inject_leg_presets
          inject_material_presets
          inject_appliance_presets
          @dialog.execute_script("window.setLicenseStatus(#{license_status_json})")
        end
        @dialog.add_action_callback('close_dialog') { |_| close }
        @dialog.add_action_callback('open_about_dialog') { |_|
          MLCabinets::Dialogs::AboutDialog.show
        }

        # Place a cabinet from its preset
        @dialog.add_action_callback('place_cabinet') do |_, json|
          unless MLCabinets::LicenseManager.licensed?
            MLCabinets::Dialogs::NewCabinetDialog.show_license_expired_message
            next
          end
          begin
            data = JSON.parse(json, symbolize_names: true)
            place_preset(data[:id])
          rescue => e
            puts "MLCabinets: place_cabinet error — #{e.message}" if MLCabinets::DEBUG
          end
        end

        # Delete a user-created cabinet preset
        @dialog.add_action_callback('delete_cabinet_preset') do |_, json|
          begin
            data = JSON.parse(json, symbolize_names: true)
            delete_preset(data[:id], data[:name])
            inject_cabinet_presets  # refresh the grid
          rescue => e
            puts "MLCabinets: delete_cabinet_preset error — #{e.message}" if MLCabinets::DEBUG
          end
        end

        # Generic delete_preset — fired by preset-modal.js for ALL preset types.
        # Dispatches to the correct library folder based on the 'type' field.
        @dialog.add_action_callback('delete_preset') do |_, json|
          begin
            data = JSON.parse(json, symbolize_names: true)
            id   = data[:id].to_s
            name = data[:name].to_s
            case data[:type].to_s
            when 'cabinet'
              delete_preset(id, name)
              inject_cabinet_presets
            when 'door_panel'
              _delete_asset_preset('panels', id, name)
              inject_door_panel_presets
            when 'drawer_front'
              _delete_asset_preset('panels', id, name)
              inject_drawer_front_presets
            when 'door_handle'
              _delete_asset_preset('handles', id, name)
              inject_door_handle_presets
            when 'drawer_handle'
              _delete_asset_preset('handles', id, name)
              inject_drawer_handle_presets
            when 'panel'
              _delete_asset_preset('panels', id, name)
              inject_panels_presets
            when 'leg'
              _delete_asset_preset('legs', id, name)
              inject_leg_presets
            when 'material'
              _delete_asset_preset('materials', id, name)
              inject_material_presets
            when 'appliance'
              _delete_asset_preset('appliances', id, name)
              inject_appliance_presets
            end
          rescue => e
            puts "MLCabinets: delete_preset error — #{e.message}" if MLCabinets::DEBUG
          end
        end

        # Open the New Cabinet dialog from the library header
        @dialog.add_action_callback('open_new_cabinet') do |_|
          MLCabinets::Dialogs::NewCabinetDialog.show
        end

        @dialog.add_action_callback('apply_material') do |_, json|
          begin
            data = JSON.parse(json, symbolize_names: true)
            preset_id = data[:id].to_s
            target    = data[:target].to_s
            grain     = data[:grain].to_s
            next if preset_id.empty? || target.empty?
            tool = MLCabinets::UI::ApplyPresetTool.new(
              preset_id,
              :material,
              material_target: target,
              material_grain: grain
            )
            Sketchup.active_model.select_tool(tool)
          rescue => e
            puts "MLCabinets: apply_material error — #{e.message}" if MLCabinets::DEBUG
          end
        end

        @dialog.add_action_callback('cancel_active_preset_tool') do |_|
          Sketchup.active_model.select_tool(nil)
        rescue => e
          puts "MLCabinets: cancel_active_preset_tool error — #{e.message}" if MLCabinets::DEBUG
        end

        # Apply-preset tool — activated when the user clicks a preset card
        # in the Doors / Drawers / Panels tabs of the Library dialog.
        [
          ['apply_door_panel',    :door_panel],
          ['apply_door_handle',   :door_handle],
          ['apply_drawer_front',  :drawer_front],
          ['apply_drawer_handle', :drawer_handle],
          ['apply_panel',         :panel],
          ['apply_leg',           :leg],
          ['apply_appliance',     :appliance],
        ].each do |cb_name, kind|
          @dialog.add_action_callback(cb_name) do |_, json|
            begin
              data = JSON.parse(json, symbolize_names: true)
              preset_id = data[:id].to_s
              next if preset_id.empty?
              tool = MLCabinets::UI::ApplyPresetTool.new(preset_id, kind)
              Sketchup.active_model.select_tool(tool)
            rescue => e
              puts "MLCabinets: #{cb_name} error — #{e.message}" if MLCabinets::DEBUG
            end
          end
        end
      end

      # -----------------------------------------------------------------------
      # Inject presets → JS
      # -----------------------------------------------------------------------

      def license_status_json
        info = MLCabinets::LicenseManager.license_info
        JSON.generate(
          state:       info[:state].to_s,
          days_left:   info[:days_left],
          expiry_date: info[:expiry_date],
          type:        info[:type]
        )
      end

      def detect_units
        # LengthUnit: 0 = Inches, 1 = Feet  →  'in';  2/3/4 = mm/cm/m  →  'cm'
        lu = Sketchup.active_model.options['UnitsOptions']['LengthUnit']
        (lu == 0 || lu == 1) ? 'in' : 'cm'
      end

      def inject_cabinet_presets
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'cabinets', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          current_unit = detect_units
          data    = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          entries = (data['presets'] || []).select do |p|
            (p['unit'] || 'cm') == current_unit
          end

          js_presets = entries.map do |p|
            thumb = resolve_thumbnail('cabinets', p['thumbnail'])
            {
              id:           p['id'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              cabinet_type: cabinet_filter_type(p),
              user_created: !!p['user_created'],
              dimensions:   p['dimensions'] || '',
              description:  p['description'] || '',
              thumbnail:    thumb
            }
          end

          @dialog.execute_script("window.initCabinetPresets(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: inject_cabinet_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      def cabinet_filter_type(preset)
        known_types = %w[base wall tall high filler base-corner wall-corner]
        cabinet_type = preset['cabinet_type'].to_s
        return cabinet_type if known_types.include?(cabinet_type)

        legacy_type = preset['type'].to_s
        known_types.include?(legacy_type) ? legacy_type : 'base'
      end

      def inject_panels_presets
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'panels', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          data    = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          panel_types = ['End Panel', 'Decorative Panel']
          entries = (data['presets'] || []).select do |p|
            (p['sub_types'] || []).any? { |st| panel_types.include?(st.to_s) }
          end

          js_presets = entries.map do |p|
            thumb = resolve_thumbnail('panels', p['thumbnail'])
            {
              id:           p['name'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              user_created: !!p['user_created'],
              description:  p['description'] || '',
              thumbnail:    thumb
            }
          end

          @dialog.execute_script("window.initPanels(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: inject_panels_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      def inject_leg_presets
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'legs', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          entries = data['presets'] || []

          js_presets = entries.map do |p|
            {
              id:           p['name'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              source:       p['user_created'] ? 'user' : 'builtin',
              user_created: !!p['user_created'],
              description:  p['description'] || '',
              thumbnail:    resolve_thumbnail('legs', p['thumbnail'])
            }
          end

          @dialog.execute_script("window.initLegs(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: inject_leg_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      def inject_material_presets
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'materials', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          entries = data['presets'] || []

          js_presets = entries.map do |p|
            {
              id:           p['name'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              source:       p['source'] || p['category'] || 'builtin',
              category:     p['category'] || p['source'],
              user_created: !!p['user_created'],
              description:  p['description'] || '',
              thumbnail:    resolve_thumbnail('materials', p['thumbnail']),
              color:        p['color'],
              grain:        (p['grain'] || 'vertical').to_s
            }
          end

          @dialog.execute_script("window.initMaterials(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: inject_material_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      def inject_appliance_presets
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          entries = data['presets'] || []

          js_presets = entries.map do |p|
            {
              id:           p['name'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              source:       p['user_created'] ? 'user' : 'builtin',
              user_created: !!p['user_created'],
              description:  p['description'] || '',
              thumbnail:    resolve_thumbnail('appliances', p['thumbnail'])
            }
          end

          @dialog.execute_script("window.initAppliances(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: inject_appliance_presets error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      def inject_door_panel_presets
        _inject_panel_presets('Door Panel', 'window.initDoorPanels')
      end

      def inject_drawer_front_presets
        _inject_panel_presets('Drawer Front', 'window.initDrawerFronts')
      end

      def inject_door_handle_presets
        _inject_handle_presets('Door Handle', 'window.initDoorHandles')
      end

      def inject_drawer_handle_presets
        _inject_handle_presets('Drawer Handle', 'window.initDrawerHandles')
      end

      # Internal: load libraries/panels/presets.json filtered by sub_type
      def _inject_panel_presets(sub_type, js_fn)
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'panels', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          data    = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          entries = (data['presets'] || []).select do |p|
            (p['sub_types'] || []).include?(sub_type)
          end

          js_presets = entries.map do |p|
            thumb = resolve_thumbnail('panels', p['thumbnail'])
            {
              id:           p['name'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              user_created: !!p['user_created'],
              description:  p['description'] || '',
              thumbnail:    thumb
            }
          end

          @dialog.execute_script("#{js_fn}(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: #{js_fn} error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # Internal: load libraries/handles/presets.json filtered by handle_type
      def _inject_handle_presets(handle_type, js_fn)
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'handles', 'presets.json'
        )
        return unless File.exist?(presets_file)

        begin
          data    = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          entries = (data['presets'] || []).select do |p|
            (p['handle_types'] || []).include?(handle_type)
          end

          js_presets = entries.map do |p|
            thumb = resolve_thumbnail('handles', p['thumbnail'])
            {
              id:           p['name'],
              name:         p['name'],
              label:        (p['name'] || '').gsub('_', ' '),
              user_created: !!p['user_created'],
              description:  p['description'] || '',
              thumbnail:    thumb
            }
          end

          @dialog.execute_script("#{js_fn}(#{JSON.generate(js_presets)})")
        rescue => e
          puts "MLCabinets: #{js_fn} error — #{e.message}" if MLCabinets::DEBUG
        end
      end

      # -----------------------------------------------------------------------
      # Place a cabinet from a preset config
      # -----------------------------------------------------------------------

      def place_preset(preset_id)
        presets_file = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'cabinets', 'presets.json'
        )
        return unless File.exist?(presets_file)

        data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
        entry = (data['presets'] || []).find { |p| p['id'] == preset_id }
        unless entry
          puts "MLCabinets: Preset #{preset_id} not found" if MLCabinets::DEBUG
          return
        end

        config_path = File.join(
          MLCabinets::PLUGIN_DIR, 'libraries', 'cabinets',
          entry['files']['json']
        )
        unless File.exist?(config_path)
          puts "MLCabinets: Config file not found — #{config_path}" if MLCabinets::DEBUG
          return
        end

        config = JSON.parse(
          File.read(config_path, encoding: 'UTF-8'),
          symbolize_names: true
        )

        result = MLCabinets::CabinetDC.build_definition(config)
        if result
          tool = MLCabinets::UI::PlacementTool.new(result)
          Sketchup.active_model.select_tool(tool)
        else
          puts "MLCabinets: build_definition returned nil for preset #{preset_id}" if MLCabinets::DEBUG
        end
      rescue => e
        puts "MLCabinets: place_preset error — #{e.message}" if MLCabinets::DEBUG
        puts e.backtrace.first(3).join("\n") if MLCabinets::DEBUG
      end

      # -----------------------------------------------------------------------
      # Delete a user preset
      # -----------------------------------------------------------------------

      def delete_preset(preset_id, name)
        base_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'cabinets')
        preset_dir = File.join(base_dir, name.to_s)

        if Dir.exist?(preset_dir)
          FileUtils.rm_rf(preset_dir)
          puts "MLCabinets: Deleted cabinet preset folder #{preset_dir}" if MLCabinets::DEBUG
        end

        presets_file = File.join(base_dir, 'presets.json')
        if File.exist?(presets_file)
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          data['presets'] ||= []
          data['presets'].reject! { |p| p['id'] == preset_id }
          File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
        end
      rescue => e
        puts "MLCabinets: delete_preset error — #{e.message}" if MLCabinets::DEBUG
      end

      # -----------------------------------------------------------------------
      # Helpers
      # -----------------------------------------------------------------------

      # Delete a user preset from any asset library folder (panels, handles, etc.)
      def _delete_asset_preset(library_folder, preset_id, name)
        base_dir    = File.join(MLCabinets::PLUGIN_DIR, 'libraries', library_folder)
        preset_dir  = File.join(base_dir, name.to_s)

        FileUtils.rm_rf(preset_dir) if Dir.exist?(preset_dir)

        presets_file = File.join(base_dir, 'presets.json')
        if File.exist?(presets_file)
          data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
          data['presets'] ||= []
          data['presets'].reject! { |p| p['id'] == preset_id || p['name'] == name.to_s }
          File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
        end
      rescue => e
        puts "MLCabinets: _delete_asset_preset error — #{e.message}" if MLCabinets::DEBUG
      end

      def resolve_thumbnail(library, thumb)
        return nil unless thumb
        return thumb if thumb.start_with?('file://', 'http://', 'https://')
        abs = File.join(MLCabinets::PLUGIN_DIR, 'libraries', library, thumb)
        return nil unless File.exist?(abs)
        # Cache-bust so overwritten thumbnails are not served stale by Chromium
        "file:///#{abs.gsub('\\', '/')}?t=#{File.mtime(abs).to_i}"
      end

    end # class CabinetLibraryDialog
  end # module Dialogs
end # module MLCabinets
