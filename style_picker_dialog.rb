# ML Cabinets — Style Picker Filter Dialog
#
# Compact HtmlDialog that lets the user choose which property groups
# to copy from a picked cabinet before applying to targets.

module MLCabinets
  module Dialogs
    class StylePickerDialog

      @@instance = nil

      # Show the filter dialog.
      #   source_config — the picked cabinet's config hash (for display context)
      #   last_filter   — previously used filter (Hash or nil) to restore state
      #   &block        — called with the filter Hash on confirm, or nil on cancel
      def self.show(source_config, last_filter = nil, &block)
        @@instance ||= new
        @@instance.open(source_config, last_filter, &block)
      end

      def self.close
        @@instance&.close
        @@instance = nil
      end

      def initialize
        @dialog = nil
        @callback = nil
      end

      def open(source_config, last_filter, &block)
        @callback = block

        if @dialog&.visible?
          @dialog.close
          @dialog = nil
        end

        @dialog = ::UI::HtmlDialog.new(
          dialog_title:     'Style Picker — Choose Properties',
          preferences_key:  'MLCabinets_StylePicker',
          style:            ::UI::HtmlDialog::STYLE_DIALOG,
          use_content_size: true,
          width:            380,
          height:           520,
          min_width:        320,
          min_height:       400
        )
        html_path = File.join(MLCabinets::PLUGIN_DIR, 'dialogs', 'style_picker', 'style_picker.html')
        @dialog.set_file(html_path)
        _setup_callbacks(source_config, last_filter)

        @dialog.set_on_closed { _on_closed }
        @dialog.show
      end

      def close
        @dialog&.close
        @dialog = nil
      end

      private

      def _setup_callbacks(source_config, last_filter)
        @dialog.add_action_callback('dialog_ready') do |_|
          # Send source config summary + last filter to JS
          payload = {
            source_type: source_config[:type] || source_config['type'] || '',
            source_name: source_config[:name] || source_config['name'] || ''
          }
          @dialog.execute_script("window.initFilter(#{JSON.generate(payload).to_json})")

          if last_filter
            @dialog.execute_script("window.restoreFilter(#{JSON.generate(last_filter).to_json})")
          end
        end

        @dialog.add_action_callback('cancel_filter') do |_|
          close
          @callback&.call(nil)
          @callback = nil
        end

        @dialog.add_action_callback('confirm_filter') do |_, json_str|
          begin
            filter = JSON.parse(json_str, symbolize_names: false)
            close
            @callback&.call(filter)
            @callback = nil
          rescue => e
            puts "MLCabinets StylePickerDialog: confirm_filter error — #{e.message}" if MLCabinets::DEBUG
          end
        end
      end

      def _on_closed
        # If dialog closed without confirm (X button), treat as cancel
        if @callback
          @callback.call(nil)
          @callback = nil
        end
      end

    end # class StylePickerDialog
  end # module Dialogs
end # module MLCabinets
