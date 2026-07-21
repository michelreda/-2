# ML Cabinets - About Dialog

module MLCabinets
  module Dialogs
    class AboutDialog

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

      # -----------------------------------------------------------------------
      # Instance
      # -----------------------------------------------------------------------

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
        html_path = File.join(PLUGIN_DIR, 'dialogs', 'about', 'about.html')

        @dialog = ::UI::HtmlDialog.new(
          dialog_title:    'About ML Cabinets',
          preferences_key: 'MLCabinets_About',
          scrollable:      true,
          resizable:       false,
          width:           420,
          height:          640,
          style:           ::UI::HtmlDialog::STYLE_DIALOG
        )

        @dialog.set_file(html_path)
        @dialog.center

        setup_callbacks
        @dialog.set_on_closed { @@instance = nil }
      end

      def setup_callbacks
        # JS signals ready — push metadata
        @dialog.add_action_callback('about_ready') do |_ctx|
          data = {
            version:   "v#{MLCabinets::VERSION}",
            author:    MLCabinets::AUTHOR,
            copyright: MLCabinets::COPYRIGHT,
            sketchup:  Sketchup.version,
            ruby:      RUBY_VERSION
          }.to_json
          @dialog.execute_script("window.initAbout(#{data.to_json})")
          @dialog.execute_script("window.initLicense(#{license_info_json})")
        end

        # Activate license key entered in the About dialog
        @dialog.add_action_callback('activate_license') do |_ctx, key|
          result = MLCabinets::LicenseManager.activate(key.to_s.strip)
          ok     = result.is_a?(Hash) && result[:success] == true
          info   = MLCabinets::LicenseManager.license_info
          payload = JSON.generate(
            success: ok,
            message: ok ? 'License activated successfully.' : (MLCabinets::LicenseManager.last_error.to_s.then { |m| m.empty? ? 'Activation failed.' : m }),
            license: {
              state:       info[:state].to_s,
              days_left:   info[:days_left],
              expiry_date: info[:expiry_date],
              masked_key:  info[:masked_key],
              type:        info[:type]
            }
          )
          @dialog.execute_script("window.onActivationResult(#{payload.to_json})")
          broadcast_license_status if ok
        end

        # Deactivate the current machine
        @dialog.add_action_callback('deactivate_license') do |_ctx|
          begin
            MLCabinets::LicenseManager.deactivate
            info    = MLCabinets::LicenseManager.license_info
            payload = JSON.generate(
              success: true,
              message: 'License deactivated for this machine.',
              license: {
                state:       info[:state].to_s,
                days_left:   info[:days_left],
                expiry_date: info[:expiry_date],
                masked_key:  info[:masked_key],
                type:        info[:type]
              }
            )
            broadcast_license_status
          rescue => e
            payload = JSON.generate(success: false, message: "Deactivation failed: #{e.message}")
          end
          @dialog.execute_script("window.onDeactivationResult(#{payload.to_json})")
        end

        # Open purchase URL in default browser
        @dialog.add_action_callback('open_purchase_url') do |_ctx|
          ::UI.openURL(MLCabinets::GUMROAD_PRODUCT_URL)
        end

        # Open user manual
        @dialog.add_action_callback('open_user_manual') do |_ctx|
          MLCabinets::Dialogs::UserManualDialog.show
          @dialog.close
          @@instance = nil
        end

        # Close button
        @dialog.add_action_callback('close_about') do |_ctx|
          @dialog.close
          @@instance = nil
        end
      end

      def license_info_json
        info = MLCabinets::LicenseManager.license_info

        # Compute days remaining for education licenses
        edu_days = nil
        if info[:type] == 'education' && info[:expiry_date]
          begin
            exp = Time.parse(info[:expiry_date])
            edu_days = [(exp.to_i - Time.now.to_i) / 86_400, 0].max
          rescue
            edu_days = nil
          end
        end

        JSON.generate(
          state:         info[:state].to_s,
          days_left:     info[:days_left],
          expiry_date:   info[:expiry_date],
          masked_key:    info[:masked_key],
          type:          info[:type],
          edu_days_left: edu_days
        )
      end

      # Push updated license status to all other open dialogs so their
      # banners update immediately without requiring a dialog restart.
      def broadcast_license_status
        json = license_status_json
        [
          MLCabinets::Dialogs::NewCabinetDialog,
          MLCabinets::Dialogs::CabinetLibraryDialog,
          MLCabinets::Dialogs::ScheduleManagerDialog
        ].each do |klass|
          next unless klass.respond_to?(:instance)
          inst = klass.instance
          next unless inst&.respond_to?(:push_license_status)
          inst.push_license_status(json)
        end
      rescue => e
        puts "MLCabinets AboutDialog#broadcast_license_status: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      end

      def license_status_json
        info = MLCabinets::LicenseManager.license_info
        JSON.generate(
          state:       info[:state].to_s,
          days_left:   info[:days_left],
          expiry_date: info[:expiry_date],
          type:        info[:type]
        )
      end

    end
  end
end
