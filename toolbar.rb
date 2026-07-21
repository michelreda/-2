# ML Cabinets - Toolbar
# Creates and manages the ML Cabinets toolbar, Extensions menu, and hot-reload.

module MLCabinets
  module UI
    module Toolbar

      @@toolbar          = nil
      @@toolbar_name    = 'ML Cabinets'
      @@menu            = nil
      @@new_cabinet_cmd = nil
      @@edit_cabinet_cmd = nil
      @@open_close_cmd  = nil
      @@swap_door_cmd   = nil
      @@swap_grain_cmd  = nil
      @@end_panel_cmd   = nil
      @@lib_cmd         = nil
      @@schedule_cmd    = nil
      @@manufacturing_cmd = nil

      # -----------------------------------------------------------------------
      # Public interface
      # -----------------------------------------------------------------------

      def self.hide_toolbar
        @@toolbar.hide if @@toolbar&.respond_to?(:hide) && @@toolbar.visible?
      end

      def self.create_toolbar
        return if @@toolbar&.respond_to?(:visible?) && @@toolbar.visible?

        @@toolbar = ::UI::Toolbar.new(@@toolbar_name)

        # --- Library button ---
        lib_cabinet_cmd = ::UI::Command.new('Library') {
          MLCabinets::Dialogs::CabinetLibraryDialog.show
        }
        lib_cabinet_cmd.tooltip         = 'Library'
        lib_cabinet_cmd.status_bar_text = 'Browse saved presets and place them in the model'
        _set_icon(lib_cabinet_cmd, 'cabinet')
        lib_cabinet_cmd.set_validation_proc {
          MLCabinets::LicenseManager.licensed? ? MF_ENABLED : MF_GRAYED
        }
        @@toolbar.add_item lib_cabinet_cmd

        # --- New Cabinet button ---
        @@new_cabinet_cmd = ::UI::Command.new('New Cabinet') {
          MLCabinets::Dialogs::NewCabinetDialog.show
        }
        @@new_cabinet_cmd.tooltip         = 'New Cabinet'
        @@new_cabinet_cmd.status_bar_text = 'Configure and place a new cabinet in the model'
        _set_icon(@@new_cabinet_cmd, 'cabinet_plus')
        @@new_cabinet_cmd.set_validation_proc {
          MLCabinets::LicenseManager.licensed? ? MF_ENABLED : MF_GRAYED
        }
        @@toolbar.add_item @@new_cabinet_cmd
        
        # Separator
        @@toolbar.add_separator

        # --- Edit Cabinet button ---
        @@edit_cabinet_cmd = ::UI::Command.new('Edit Cabinet') {
          MLCabinets::UI::EditCabinetTool.activate_or_edit
        }
        @@edit_cabinet_cmd.tooltip         = 'Edit Cabinet'
        @@edit_cabinet_cmd.status_bar_text = 'Edit an existing ML cabinet configuration'
        _set_icon(@@edit_cabinet_cmd, 'edit_cabinet')
        @@toolbar.add_item @@edit_cabinet_cmd

        # --- Style Picker button ---
        style_picker_cmd = ::UI::Command.new('Style Picker') {
          Sketchup.active_model.select_tool(MLCabinets::UI::StylePickerTool.new)
        }
        style_picker_cmd.tooltip         = 'Style Picker'
        style_picker_cmd.status_bar_text = 'Pick a cabinet style and apply it to other cabinets'
        _set_icon(style_picker_cmd, 'style_picker')
        @@toolbar.add_item style_picker_cmd

        # Separator
        @@toolbar.add_separator

        # --- Swap Door Opening button ---
        @@swap_door_cmd = ::UI::Command.new('Swap Door Opening') {
          Sketchup.active_model.select_tool(MLCabinets::UI::SwapDoorTool.new)
        }
        @@swap_door_cmd.tooltip         = 'Swap Door Opening'
        @@swap_door_cmd.status_bar_text = 'Click a door to swap its hinge direction (left↔right, top↔bottom)'
        _set_icon(@@swap_door_cmd, 'swap_door')
        @@toolbar.add_item @@swap_door_cmd

        # --- Open / Close button ---
        @@open_close_cmd = ::UI::Command.new('Open / Close') {
          Sketchup.active_model.select_tool(MLCabinets::UI::OpenCloseTool.new)
        }
        @@open_close_cmd.tooltip         = 'Open / Close'
        @@open_close_cmd.status_bar_text = 'Click a door or drawer to animate it open or closed'
        _set_icon(@@open_close_cmd, 'open_close')
        @@toolbar.add_item @@open_close_cmd

        # --- End Panel button ---
        @@end_panel_cmd = ::UI::Command.new('End Panel') {
          Sketchup.active_model.select_tool(MLCabinets::UI::EndPanelTool.new)
        }
        @@end_panel_cmd.tooltip         = 'End Panel'
        @@end_panel_cmd.status_bar_text = 'Click a cabinet side to add a decorative end panel'
        _set_icon(@@end_panel_cmd, 'end_panel')
        @@toolbar.add_item @@end_panel_cmd

        # --- Swap Grain Direction button ---
        @@swap_grain_cmd = ::UI::Command.new('Swap Grain Direction') {
          Sketchup.active_model.select_tool(MLCabinets::UI::SwapGrainTool.new)
        }
        @@swap_grain_cmd.tooltip         = 'Swap Grain Direction'
        @@swap_grain_cmd.status_bar_text = 'Click a door, drawer, or panel to toggle its material grain direction (vertical ↔ horizontal)'
        _set_icon(@@swap_grain_cmd, 'grain_direction')
        @@toolbar.add_item @@swap_grain_cmd

        # Separator
        @@toolbar.add_separator

        # --- Add to Library button ---
        @@lib_cmd = ::UI::Command.new('Add to Library') {
          MLCabinets::AddToLibrary.add_to_library
        }
        @@lib_cmd.tooltip         = 'Add to Library'
        @@lib_cmd.status_bar_text = 'Add the selected object to a preset library'
        _set_icon(@@lib_cmd, 'add_to_library')
        @@toolbar.add_item @@lib_cmd

        # --- Cabinet Schedule button ---
        @@schedule_cmd = ::UI::Command.new('Cabinet Schedule') {
          MLCabinets::Dialogs::ScheduleManagerDialog.show
        }
        @@schedule_cmd.tooltip         = 'Cabinet Schedule Manager'
        @@schedule_cmd.status_bar_text = 'View and export a schedule of all cabinets in the model'
        _set_icon(@@schedule_cmd, 'table')
        @@toolbar.add_item @@schedule_cmd

        # --- Prepare for Manufacturing button ---
        @@manufacturing_cmd = ::UI::Command.new('Prepare for Manufacturing') {
          MLCabinets::UI::ManufacturingPrep.prepare_selected_cabinet
        }
        @@manufacturing_cmd.tooltip         = 'Prepare for Manufacturing'
        @@manufacturing_cmd.status_bar_text = 'Bake selected cabinet parts for manufacturing and cutlists'
        _set_icon(@@manufacturing_cmd, 'manufacturing')
        @@manufacturing_cmd.set_validation_proc {
          MLCabinets::LicenseManager.licensed? ? MF_ENABLED : MF_GRAYED
        }
        @@toolbar.add_item @@manufacturing_cmd
        
        # Separator
        @@toolbar.add_separator

        # --- About button ---
        about_cmd = ::UI::Command.new('About ML Cabinets') {
          MLCabinets::Dialogs::AboutDialog.show
        }
        about_cmd.tooltip         = 'About ML Cabinets'
        about_cmd.status_bar_text = 'View extension info and version.'
        _set_icon(about_cmd, 'about')
        @@toolbar.add_item about_cmd

        @@toolbar.show
      rescue => e
        puts "MLCabinets: Error creating toolbar — #{e.message}"
      end

      def self.create_menu
        return if @@menu

        @@menu = ::UI.menu('Extensions').add_submenu('ML Cabinets')

        # Add the same Command objects used by the toolbar so SketchUp
        # treats them as one action and allows keyboard shortcut assignment
        # via Preferences → Shortcuts.
        @@menu.add_item(@@new_cabinet_cmd)  if @@new_cabinet_cmd
        @@menu.add_item(@@edit_cabinet_cmd) if @@edit_cabinet_cmd
        @@menu.add_item(@@open_close_cmd)  if @@open_close_cmd
        @@menu.add_item(@@swap_door_cmd)   if @@swap_door_cmd
        @@menu.add_item(@@end_panel_cmd)   if @@end_panel_cmd
        @@menu.add_item(@@swap_grain_cmd)  if @@swap_grain_cmd
        @@menu.add_item(@@lib_cmd)         if @@lib_cmd
        @@menu.add_item(@@schedule_cmd)    if @@schedule_cmd
        @@menu.add_item(@@manufacturing_cmd) if @@manufacturing_cmd
        @@menu.add_separator
        @@menu.add_item('About ML Cabinets') {
          MLCabinets::Dialogs::AboutDialog.show
        }
      rescue => e
        puts "MLCabinets: Error creating menu — #{e.message}"
      end

      # -----------------------------------------------------------------------
      # Hot-reload (development only)
      # -----------------------------------------------------------------------

      def self.reload_extension
        plugin_dir = defined?(MLCabinets::PLUGIN_DIR) ? MLCabinets::PLUGIN_DIR : nil
        plugin_dir ||= File.expand_path('../..', __FILE__)

        puts "🔄 Reloading ML Cabinets..."

        # 1. Remove module constants so every file is re-defined cleanly.
        #    Do NOT remove MLCabinets::UI::Toolbar — `self` IS that module.
        if defined?(MLCabinets)
          # Close open dialogs before removing their constants
          if MLCabinets.const_defined?(:Dialogs)
            begin
              MLCabinets::Dialogs::NewCabinetDialog.close if
                MLCabinets::Dialogs.const_defined?(:NewCabinetDialog)
            rescue; end
            begin
              MLCabinets::Dialogs::CabinetLibraryDialog.close if
                MLCabinets::Dialogs.const_defined?(:CabinetLibraryDialog)
            rescue; end
            begin
              MLCabinets::Dialogs::AddToLibraryDialog.close if
                MLCabinets::Dialogs.const_defined?(:AddToLibraryDialog)
            rescue; end
            begin
              MLCabinets::Dialogs::StylePickerDialog.close if
                MLCabinets::Dialogs.const_defined?(:StylePickerDialog)
            rescue; end
            begin
              MLCabinets::Dialogs::ScheduleManagerDialog.close if
                MLCabinets::Dialogs.const_defined?(:ScheduleManagerDialog)
            rescue; end
            begin
              MLCabinets::Dialogs::UserManualDialog.close if
                MLCabinets::Dialogs.const_defined?(:UserManualDialog)
            rescue; end
            begin
              MLCabinets::Dialogs::AboutDialog.close if
                MLCabinets::Dialogs.const_defined?(:AboutDialog)
            rescue; end
            _remove_const(MLCabinets::Dialogs, :AboutDialog)
            _remove_const(MLCabinets::Dialogs, :UserManualDialog)
            _remove_const(MLCabinets::Dialogs, :ScheduleManagerDialog)
            _remove_const(MLCabinets::Dialogs, :StylePickerDialog)
            _remove_const(MLCabinets::Dialogs, :AddToLibraryDialog)
            _remove_const(MLCabinets::Dialogs, :CabinetLibraryDialog)
            _remove_const(MLCabinets::Dialogs, :NewCabinetDialog)
            _remove_const(MLCabinets, :Dialogs)
          end

          # Detach scale observer before reloading
          if MLCabinets::UI.const_defined?(:ScaleObserverManager)
            begin
              MLCabinets::UI::ScaleObserverManager.detach
            rescue; end
            _remove_const(MLCabinets::UI, :ScaleObserverManager)
            _remove_const(MLCabinets::UI, :ScaleObserver)
          end

          _remove_const(MLCabinets, :AddToLibrary)
          _remove_const(MLCabinets, :AddCabinetToLibrary)
          _remove_const(MLCabinets, :AddLegToLibrary)
          _remove_const(MLCabinets, :AddApplianceToLibrary)
          _remove_const(MLCabinets, :AddProfileToLibrary)
          _remove_const(MLCabinets, :AddPanelToLibrary)
          _remove_const(MLCabinets, :AddHandleToLibrary)
          _remove_const(MLCabinets, :AddImageToLibrary)
          _remove_const(MLCabinets, :GrainPickerTool)
          _remove_const(MLCabinets::UI, :LibraryHandler)
          _remove_const(MLCabinets::UI, :ContextMenu)
          _remove_const(MLCabinets::UI, :EditCabinetTool)
          _remove_const(MLCabinets::UI, :StylePickerTool)
          _remove_const(MLCabinets::UI, :OpenCloseTool)
          _remove_const(MLCabinets::UI, :OpenCloseAnimation)
          _remove_const(MLCabinets::UI, :SwapDoorTool)
          _remove_const(MLCabinets::UI, :EndPanelTool)
          _remove_const(MLCabinets::UI, :LayerManager)
          _remove_const(MLCabinets::UI, :SwapGrainTool)
          _remove_const(MLCabinets::UI, :ManufacturingPrep)

          _remove_const(MLCabinets, :MaterialHelper)
          _remove_const(MLCabinets, :CabinetScheduleCollector)
          _remove_const(MLCabinets, :CabinetThumbnailCapture)
          _remove_const(MLCabinets, :CabinetDC)
          _remove_const(MLCabinets, :CornerCabinetDC)
          _remove_const(MLCabinets, :GroupDC)
          _remove_const(MLCabinets, :ItemDC)
          _remove_const(MLCabinets, :ShelfDC)
          _remove_const(MLCabinets, :DrawerDC)
          _remove_const(MLCabinets, :BlankDC)
          _remove_const(MLCabinets, :HANDLE_BOTTOM_THRESHOLD_IN)
          _remove_const(MLCabinets, :ProfileDC)
          _remove_const(MLCabinets, :ApplianceDC)
          _remove_const(MLCabinets, :PanelDC)

          _remove_const(MLCabinets, :DrawerFaceDC)
          _remove_const(MLCabinets, :DoorLeafDC)
          _remove_const(MLCabinets, :HandleDC)
          _remove_const(MLCabinets, :DEBUG)
          _remove_const(MLCabinets, :EXTENSION_NAME)
          _remove_const(MLCabinets, :VERSION)
          _remove_const(MLCabinets, :AUTHOR)
          _remove_const(MLCabinets, :COPYRIGHT)
          _remove_const(MLCabinets, :DESCRIPTION)
          _remove_const(MLCabinets, :IS_TRIAL_VERSION)
          _remove_const(MLCabinets, :TRIAL_DAYS)
          _remove_const(MLCabinets, :GUMROAD_FULL_PRODUCT_ID)
          _remove_const(MLCabinets, :GUMROAD_EDUCATION_PRODUCT_ID)
          _remove_const(MLCabinets, :GUMROAD_PRODUCT_ID)
          _remove_const(MLCabinets, :GUMROAD_TRIAL_PRODUCT_URL)
          _remove_const(MLCabinets, :GUMROAD_EDUCATION_PRODUCT_URL)
          _remove_const(MLCabinets, :GUMROAD_FULL_PRODUCT_URL)
          _remove_const(MLCabinets, :GUMROAD_PRODUCT_URL)
          _remove_const(MLCabinets, :PLUGIN_DIR)
        end

        # 2. Reload each non-toolbar file explicitly via `load` (bypasses the
        #    require cache). toolbar.rb is intentionally excluded — reloading it
        #    mid-execution would redefine reload_extension while it is running.
        #    Add new source files here as the plugin grows (matches ML_Doors pattern).
        load File.join(plugin_dir, 'material_helper.rb')
        load File.join(plugin_dir, 'blank_dc.rb')
        load File.join(plugin_dir, 'drawer_dc.rb')
        load File.join(plugin_dir, 'drawer_face_dc.rb')
        load File.join(plugin_dir, 'door_leaf_dc.rb')
        load File.join(plugin_dir, 'handle_dc.rb')
        load File.join(plugin_dir, 'shelf_dc.rb')
        load File.join(plugin_dir, 'profile_dc.rb')
        load File.join(plugin_dir, 'appliance_dc.rb')
        load File.join(plugin_dir, 'panel_dc.rb')
        load File.join(plugin_dir, 'item_dc.rb')
        load File.join(plugin_dir, 'group_dc.rb')
        load File.join(plugin_dir, 'cabinet_dc.rb')
        load File.join(plugin_dir, 'corner_cabinet_dc.rb')
        load File.join(plugin_dir, 'ui', 'scale_observer.rb')
        load File.join(plugin_dir, 'ui', 'placement_tool.rb')
        load File.join(plugin_dir, 'ui', 'library_handler.rb')
        load File.join(plugin_dir, 'ui', 'add_cabinet_to_library.rb')
        load File.join(plugin_dir, 'ui', 'add_leg_to_library.rb')
        load File.join(plugin_dir, 'ui', 'add_appliance_to_library.rb')
        load File.join(plugin_dir, 'ui', 'add_profile_to_library.rb')
        load File.join(plugin_dir, 'ui', 'add_panel_to_library.rb')
        load File.join(plugin_dir, 'ui', 'add_handle_to_library.rb')
        load File.join(plugin_dir, 'ui', 'add_image_to_library.rb')
        load File.join(plugin_dir, 'ui', 'grain_picker_tool.rb')
        load File.join(plugin_dir, 'ui', 'open_close_tool.rb')
        load File.join(plugin_dir, 'ui', 'swap_door_tool.rb')
        load File.join(plugin_dir, 'ui', 'manufacturing_prep.rb')
        load File.join(plugin_dir, 'ui', 'apply_preset_tool.rb')
        load File.join(plugin_dir, 'ui', 'edit_cabinet_tool.rb')
        load File.join(plugin_dir, 'ui', 'style_picker_tool.rb')
        load File.join(plugin_dir, 'ui', 'end_panel_tool.rb')
        load File.join(plugin_dir, 'ui', 'add_to_library.rb')
        load File.join(plugin_dir, 'ui', 'context_menu.rb')
        load File.join(plugin_dir, 'ui', 'layer_manager.rb')
        load File.join(plugin_dir, 'ui', 'swap_grain_tool.rb')
        load File.join(plugin_dir, 'dialogs', 'new_cabinet_dialog.rb')
        load File.join(plugin_dir, 'dialogs', 'style_picker_dialog.rb')
        load File.join(plugin_dir, 'dialogs', 'cabinet_library_dialog.rb')
        load File.join(plugin_dir, 'dialogs', 'add_to_library_dialog.rb')
        load File.join(plugin_dir, 'cabinet_schedule_collector.rb')
        load File.join(plugin_dir, 'ui', 'cabinet_thumbnail_capture.rb')
        load File.join(plugin_dir, 'dialogs', 'schedule_manager_dialog.rb')
        load File.join(plugin_dir, 'dialogs', 'user_manual_dialog.rb')
        load File.join(plugin_dir, 'dialogs', 'about_dialog.rb')
        load File.join(plugin_dir, 'license_manager.rb')

        # 3. Reload loader.rb last: restores scalar constants and calls
        #    initialize_extension, which no-ops via the @@extension_initialized
        #    guard so the existing toolbar and menu are never recreated.
        load File.join(plugin_dir, 'loader.rb')

        # Re-attach the scale observer (initialize_extension no-ops on reload)
        MLCabinets::UI::ScaleObserverManager.attach

        puts "✅ ML Cabinets reloaded"
      rescue => e
        puts "❌ Reload failed: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end

      # -----------------------------------------------------------------------
      private
      # -----------------------------------------------------------------------

      # Builds the about message from current constants (always up-to-date after reload).
      def self._about_msg
        "#{MLCabinets::EXTENSION_NAME} v#{MLCabinets::VERSION}\n" \
        "#{MLCabinets::COPYRIGHT}\n\n" \
        "Ruby #{RUBY_VERSION} | SketchUp #{Sketchup.version} \n\n" \
        "This is a professional cabinet placement tool for SketchUp, developed by ML Extensions."
      end

      # Sets small + large icon only if the file exists (graceful no-icon fallback).
      def self._set_icon(cmd, name)
        path = File.join(MLCabinets::PLUGIN_DIR, 'icons', "#{name}.png")
        if File.exist?(path)
          cmd.small_icon = path
          cmd.large_icon = path
        end
      end

      # Safe remove_const helper.
      def self._remove_const(mod, sym)
        mod.send(:remove_const, sym) if mod.const_defined?(sym)
      rescue NameError
        # already gone — ignore
      end

    end # module Toolbar
  end # module UI
end # module MLCabinets
