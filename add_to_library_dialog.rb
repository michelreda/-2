# ML Cabinets - Add to Library Dialog
# HtmlDialog form replacing the native UI.inputbox Add to Library flow.
# Handles name input, type selection, panel sub-types, overwrite warnings,
# and inline validation — all within a single styled dialog.

require 'sketchup.rb'
require 'json'

module MLCabinets
  module Dialogs
    class AddToLibraryDialog

      @@instance = nil

      # -----------------------------------------------------------------------
      # Singleton interface
      # -----------------------------------------------------------------------

      def self.show(entity)
        @@instance ||= new
        @@instance.open(entity)
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
        @entity = nil
      end

      def open(entity)
        @entity = entity
        if @dialog&.visible?
          @dialog.bring_to_front
          send_initial_data
        else
          @dialog = nil
          create_dialog
          @dialog.center if @dialog.respond_to?(:center)
          @dialog.show
          @dialog.bring_to_front
        end
      rescue => e
        message = "Unable to open the Add to Library dialog:\n#{e.message}"
        puts "MLCabinets: AddToLibraryDialog.open — #{e.message}"
        puts e.backtrace.first(5).join("\n") if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
        ::UI.messagebox(message)
      end

      def close
        @dialog&.close
        @dialog = nil
        @entity = nil
      end

      def visible?
        @dialog&.visible? || false
      end

      # -----------------------------------------------------------------------
      private
      # -----------------------------------------------------------------------

      def create_dialog
        @dialog = ::UI::HtmlDialog.new(
          dialog_title:     'Add to Library',
          preferences_key:  'MLCabinets_AddToLibrary',
          style:            ::UI::HtmlDialog::STYLE_DIALOG,
          use_content_size: true,
          width:            400,
          height:           500,
          min_width:        380,
          min_height:       400
        )
        html_path = File.join(
          MLCabinets::PLUGIN_DIR, 'dialogs', 'add_to_library', 'add_to_library.html'
        )
        @dialog.set_file(html_path)
        setup_callbacks
        @dialog.set_on_closed do
          @dialog = nil
          @entity = nil
        end
      end

      def setup_callbacks
        @dialog.add_action_callback('dialog_ready') { |_| send_initial_data }
        @dialog.add_action_callback('cancel_dialog') { |_| close }
        @dialog.add_action_callback('confirm_add') { |_, json| handle_confirm(json) }
        @dialog.add_action_callback('start_grain_pick') do |_|
          tool = MLCabinets::GrainPickerTool.new(@dialog)
          Sketchup.active_model.tools.push_tool(tool)
        end
      end

      # -----------------------------------------------------------------------
      # Build and send initial form data to the JS layer
      # -----------------------------------------------------------------------

      def send_initial_data
        return unless @entity

        detected_type = MLCabinets::UI::LibraryHandler.detect_entity_type(@entity)
        detected_type ||= MLCabinets::UI::LibraryHandler.get_available_types.first

        default_name = MLCabinets::UI::LibraryHandler.get_default_name(@entity, detected_type)
        default_name = default_name.strip.gsub(/\s+/, '_')

        types = MLCabinets::UI::LibraryHandler.get_available_types.map do |t|
          { name: t, description: MLCabinets::UI::LibraryHandler.get_type_description(t) }
        end

        panel_sub_types  = defined?(MLCabinets::AddPanelToLibrary::ALL_SUB_TYPES) ?
          MLCabinets::AddPanelToLibrary::ALL_SUB_TYPES : []
        handle_sub_types = defined?(MLCabinets::AddHandleToLibrary::ALL_HANDLE_TYPES) ?
          MLCabinets::AddHandleToLibrary::ALL_HANDLE_TYPES : []
        material_categories = defined?(MLCabinets::AddImageToLibrary::ALL_CATEGORIES) ?
          MLCabinets::AddImageToLibrary::ALL_CATEGORIES : []
        appliance_types = defined?(MLCabinets::AddApplianceToLibrary::ALL_APPLIANCE_TYPES) ?
          MLCabinets::AddApplianceToLibrary::ALL_APPLIANCE_TYPES : []

        sub_types_by_type         = {
          'Panel'     => panel_sub_types,
          'Handle'    => handle_sub_types,
          'Material'  => material_categories,
          'Appliance' => appliance_types
        }
        default_sub_types_by_type = {
          'Panel'     => panel_sub_types.dup,
          'Handle'    => handle_sub_types.dup,
          'Material'  => [],
          'Appliance' => []
        }

        entity_label = ''
        if @entity.is_a?(Sketchup::Image)
          # Sketchup::Image has no name/definition — use the file name
          path = @entity.path.to_s
          entity_label = path.empty? ? 'Image' : File.basename(path, File.extname(path))
        elsif @entity.respond_to?(:name) && !@entity.name.to_s.strip.empty?
          entity_label = @entity.name
        elsif @entity.respond_to?(:definition)
          entity_label = @entity.definition.name.to_s
        end

        data = {
          default_name:              default_name,
          detected_type:             detected_type,
          types:                     types,
          # Legacy keys kept for backwards compatibility
          sub_types:                 panel_sub_types,
          default_sub_types:         panel_sub_types.dup,
          # Per-type dictionaries consumed by the updated JS layer
          sub_types_by_type:         sub_types_by_type,
          default_sub_types_by_type: default_sub_types_by_type,
          entity_label:              entity_label
        }

        @dialog.execute_script("window.initDialog(#{data.to_json})")
      rescue => e
        puts "MLCabinets: AddToLibraryDialog.send_initial_data — #{e.message}" if MLCabinets::DEBUG
      end

      # -----------------------------------------------------------------------
      # Handle confirm_add callback from JS
      # -----------------------------------------------------------------------

      def handle_confirm(params_json)
        params             = JSON.parse(params_json, symbolize_names: true)
        name               = params[:name].to_s.strip
        selected_type      = params[:type].to_s
        selected_sub_types = Array(params[:sub_types]).map(&:to_s)
        overwrite_confirmed = params[:overwrite_confirmed] == true
        material_grain     = params[:grain].to_s

        # --- Name validation ---
        err = name_error(name)
        if err
          send_error('name', err)
          return
        end

        clean_name = name.gsub(/\s+/, '_')
                        .gsub(/[^a-zA-Z0-9_\-]/, '_')
                        .gsub(/_+/, '_')
                        .gsub(/^_+|_+$/, '')

        if clean_name.empty?
          send_error('name', 'Name becomes empty after cleaning. Try a different name.')
          return
        end

        # --- Entity validation (silent — captures any messagebox text) ---
        valid, error_msg = MLCabinets::UI::LibraryHandler.validate_entity_with_message(
          @entity, selected_type
        )
        unless valid
          send_error('type', error_msg.to_s.split("\n").first ||
            "The selected object is not valid for the #{selected_type} library.")
          return
        end

        # --- Panel path ---
        if selected_type == 'Panel'
          if selected_sub_types.empty?
            send_error('subtypes', 'Please select at least one sub-type.')
            return
          end

          unless overwrite_confirmed
            if MLCabinets::AddToLibrary.panel_files_exist(clean_name)
              send_overwrite("'#{clean_name}' already exists. Click 'Save Anyway' to overwrite.")
              return
            end
          end

          MLCabinets::AddPanelToLibrary.set_entity_and_name(@entity, clean_name)
          MLCabinets::AddPanelToLibrary.set_sub_types(selected_sub_types)
          success = MLCabinets::AddPanelToLibrary.process_library_addition

        # --- Material / Image path ---
        elsif selected_type == 'Material'
          if selected_sub_types.empty?
            send_error('subtypes', 'Please select a material category.')
            return
          end

          unless overwrite_confirmed
            if MLCabinets::AddToLibrary.image_files_exist(clean_name)
              send_overwrite("'#{clean_name}' already exists. Click 'Save Anyway' to overwrite.")
              return
            end
          end

          MLCabinets::AddImageToLibrary.set_entity_and_name(@entity, clean_name)
          MLCabinets::AddImageToLibrary.set_sub_types(selected_sub_types)
          MLCabinets::AddImageToLibrary.set_grain(material_grain)
          success = MLCabinets::AddImageToLibrary.process_library_addition

        # --- Handle path ---
        elsif selected_type == 'Handle'
          if selected_sub_types.empty?
            send_error('subtypes', 'Please select at least one handle type.')
            return
          end

          unless overwrite_confirmed
            if MLCabinets::AddToLibrary.handle_files_exist(clean_name)
              send_overwrite("'#{clean_name}' already exists. Click 'Save Anyway' to overwrite.")
              return
            end
          end

          MLCabinets::AddHandleToLibrary.set_entity_and_name(@entity, clean_name)
          MLCabinets::AddHandleToLibrary.set_handle_types(selected_sub_types)
          success = MLCabinets::AddHandleToLibrary.process_library_addition

        # --- Appliance path ---
        elsif selected_type == 'Appliance'
          unless overwrite_confirmed
            if MLCabinets::AddToLibrary.files_exist_for_type(clean_name, selected_type)
              send_overwrite("'#{clean_name}' already exists. Click 'Save Anyway' to overwrite.")
              return
            end
          end

          MLCabinets::AddApplianceToLibrary.set_entity_and_name(@entity, clean_name)
          MLCabinets::AddApplianceToLibrary.set_appliance_flags(
            fixed_size:    selected_sub_types.include?('Fixed Size'),
            free_standing: selected_sub_types.include?('Free Standing')
          )
          success = MLCabinets::AddApplianceToLibrary.process_library_addition

        # --- All other types ---
        else
          unless overwrite_confirmed
            if MLCabinets::AddToLibrary.files_exist_for_type(clean_name, selected_type)
              send_overwrite(
                "#{selected_type} '#{clean_name}' already exists. " \
                "Click 'Save Anyway' to overwrite."
              )
              return
            end
          end

          success = MLCabinets::UI::LibraryHandler.process_entity(
            @entity, selected_type, clean_name
          )
        end

        if success
          MLCabinets::Dialogs::CabinetLibraryDialog.refresh
          close
        else
          send_error('general', "Failed to save '#{clean_name}'. Please try again.")
        end

      rescue => e
        puts "MLCabinets: AddToLibraryDialog.handle_confirm — #{e.message}" if MLCabinets::DEBUG
        send_error('general', "Unexpected error: #{e.message}")
      end

      # -----------------------------------------------------------------------
      # Name validation — mirrors LibraryHandler.validate_name but returns
      # the error string instead of popping a messagebox.
      # -----------------------------------------------------------------------

      def name_error(name)
        return 'Name cannot be empty.' if name.nil? || name.strip.empty?

        clean = name.strip
        return 'Name is too long (max 50 characters).' if clean.length > 50
        return 'Name cannot start with a number.' if clean =~ /^\d/

        if clean =~ /[^a-zA-Z0-9_\- ]/
          bad = clean.scan(/[^a-zA-Z0-9_\- ]/).uniq.join(', ')
          return "Invalid characters: #{bad}. Use letters, numbers, underscores, hyphens, or spaces."
        end

        if clean =~ /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i
          return "'#{clean}' is a reserved system name. Please choose a different name."
        end

        nil
      end

      # -----------------------------------------------------------------------
      # Bridge helpers — use to_json for safe escaping of all messages
      # -----------------------------------------------------------------------

      def send_error(field, message)
        @dialog.execute_script(
          "window.showFieldError(#{field.to_json}, #{message.to_json})"
        )
      end

      def send_overwrite(message)
        @dialog.execute_script("window.showOverwriteWarning(#{message.to_json})")
      end

    end
  end
end
