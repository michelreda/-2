# ML Cabinets - User Manual Dialog
# Opens a read-only HTML documentation viewer.

module MLCabinets
  module Dialogs
    class UserManualDialog

      @@instance = nil

      # ---------------------------------------------------------------------
      # Singleton interface
      # ---------------------------------------------------------------------

      def self.show
        @@instance ||= new
        @@instance.show
      end

      def self.close
        @@instance&.close
        @@instance = nil
      end

      # ---------------------------------------------------------------------
      # Instance
      # ---------------------------------------------------------------------

      def initialize
        @dialog = nil
      end

      def show
        if @dialog&.visible?
          @dialog.bring_to_front
          return
        end
        create_dialog
        @dialog.show
      end

      def close
        @dialog&.close
        @dialog = nil
      end

      private

      def create_dialog
        html_path = File.join(PLUGIN_DIR, 'dialogs', 'user_manual', 'user_manual.html')

        @dialog = ::UI::HtmlDialog.new(
          dialog_title:    'ML Cabinets — User Manual',
          preferences_key: 'MLCabinets_UserManual',
          scrollable:      false,
          resizable:       true,
          width:           1060,
          height:          720,
          min_width:       600,
          min_height:      400,
          style:           ::UI::HtmlDialog::STYLE_DIALOG
        )

        @dialog.set_file(html_path)
        @dialog.center

        @dialog.set_on_closed { @@instance = nil }
      end

    end
  end
end
