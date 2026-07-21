# ML Cabinets - Schedule Manager Dialog
# Singleton HtmlDialog that displays the Cabinet Schedule Manager.
# Scans all ML_Cabinets instances in the model and presents them in
# a sortable/filterable table with pricing, export, and client info.

require 'json'

module MLCabinets
  module Dialogs

    class ScheduleManagerDialog

      DIALOG_TITLE = 'Cabinet Schedule Manager'.freeze
      PREFS_KEY    = 'MLCabinets_ScheduleManager'.freeze

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
          # Defer first data push so the dialog fully renders first
          ::UI.start_timer(0.15, false) { refresh_schedule_data }
        end
      end

      def close
        @dialog&.close
        @dialog = nil
      end

      def visible?
        @dialog&.visible? || false
      end

      # -----------------------------------------------------------------------
      private
      # -----------------------------------------------------------------------

      def create_dialog
        @dialog = ::UI::HtmlDialog.new(
          dialog_title:     DIALOG_TITLE,
          preferences_key:  PREFS_KEY,
          style:            ::UI::HtmlDialog::STYLE_DIALOG,
          use_content_size: false,
          width:            1200,
          height:           800,
          min_width:        800,
          min_height:       600,
          resizable:        true,
          scrollable:       true
        )

        html_path = File.join(
          MLCabinets::PLUGIN_DIR, 'dialogs', 'schedule_manager', 'schedule_manager.html'
        )
        @dialog.set_file(html_path)
        setup_callbacks
        @dialog.set_on_closed { @dialog = nil }
      end

      def push_license_status(json)
        return unless @dialog&.visible?
        safe_exec("window.setLicenseStatus(#{json.to_json})")
      rescue => e
        puts "MLCabinets ScheduleManagerDialog#push_license_status: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      end

      def setup_callbacks
        # JS → Ruby: request fresh schedule data
        @dialog.add_action_callback('getScheduleData') { |_| refresh_schedule_data }

        # JS → Ruby: report current unit system
        @dialog.add_action_callback('getUnitSystem') do |_|
          system, label = detect_unit_system
          info = JSON.generate({ system: system, label: label })
          safe_exec("window.scheduleManager.setUnitSystem(#{info})")
          safe_exec("window.setLicenseStatus(#{license_status_json})")
        end

        @dialog.add_action_callback('open_about_dialog') { |_|
          MLCabinets::Dialogs::AboutDialog.show
        }

        # JS → Ruby: select cabinet instances in SketchUp viewport
        @dialog.add_action_callback('selectCabinets') do |_, ids_json|
          begin
            select_cabinets(JSON.parse(ids_json.to_s))
          rescue => e
            log_error('selectCabinets', e)
          end
        end

        # JS → Ruby: persist a per-unit price for one fingerprint group
        @dialog.add_action_callback('updatePrice') do |_, fingerprint, price_str, ids_json|
          begin
            model = Sketchup.active_model
            price = price_str.to_f
            ids   = JSON.parse(ids_json.to_s)

            model.start_operation('Update Cabinet Price', true)
            CabinetScheduleCollector.save_price_override(model, fingerprint.to_s, price)

            ids.each do |pid|
              inst = model.find_entity_by_persistent_id(pid)
              next unless inst.is_a?(Sketchup::ComponentInstance)
              defn = inst.definition
              defn.set_attribute('ml_cabinets', 'price', price)
              update_config_json(defn) { |cfg| cfg['price'] = price }
            end
            model.commit_operation

            refresh_schedule_data
          rescue => e
            Sketchup.active_model.abort_operation rescue nil
            log_error('updatePrice', e)
          end
        end

        # JS → Ruby: persist a display name for one fingerprint group
        @dialog.add_action_callback('updateName') do |_, fingerprint, name, ids_json|
          begin
            model = Sketchup.active_model
            name  = name.to_s.strip
            ids   = JSON.parse(ids_json.to_s)

            model.start_operation('Update Cabinet Name', true)
            CabinetScheduleCollector.save_name_override(model, fingerprint.to_s, name)

            ids.each do |pid|
              inst = model.find_entity_by_persistent_id(pid)
              next unless inst.is_a?(Sketchup::ComponentInstance)
              defn = inst.definition
              defn.set_attribute('ml_cabinets', 'cab_name', name)
              update_config_json(defn) { |cfg| cfg['name'] = name }
            end
            model.commit_operation

            refresh_schedule_data
          rescue => e
            Sketchup.active_model.abort_operation rescue nil
            log_error('updateName', e)
          end
        end

        # JS → Ruby: export schedule as CSV or HTML
        @dialog.add_action_callback('exportSchedule') do |_, format, data_json, columns_json|
          begin
            export_schedule(format.to_s, JSON.parse(data_json), JSON.parse(columns_json))
          rescue => e
            log_error('exportSchedule', e)
          end
        end

        # JS → Ruby: save column/density/filter preferences to model
        @dialog.add_action_callback('savePreferences') do |_, prefs_json|
          begin
            Sketchup.active_model.set_attribute(PREFS_KEY, 'preferences', prefs_json.to_s)
          rescue => e
            log_error('savePreferences', e)
          end
        end

        # JS → Ruby: load saved preferences and push to JS
        @dialog.add_action_callback('getPreferences') do |_|
          begin
            prefs = Sketchup.active_model.get_attribute(PREFS_KEY, 'preferences', 'null')
            safe_exec("window.scheduleManager.loadPreferences(#{prefs})")
          rescue => e
            log_error('getPreferences', e)
          end
        end

        # JS → Ruby: load client info from model attributes
        @dialog.add_action_callback('getClientInfo') do |_|
          begin
            m = Sketchup.active_model
            info = {
              name:    m.get_attribute(PREFS_KEY, 'client_name',    '').to_s,
              mobile:  m.get_attribute(PREFS_KEY, 'client_mobile',  '').to_s,
              email:   m.get_attribute(PREFS_KEY, 'client_email',   '').to_s,
              address: m.get_attribute(PREFS_KEY, 'client_address', '').to_s,
            }
            safe_exec("window.scheduleManager.loadClientInfo(#{JSON.generate(info)})")
          rescue => e
            log_error('getClientInfo', e)
          end
        end

        # JS → Ruby: save client info to model attributes
        @dialog.add_action_callback('saveClientInfo') do |_, info_json|
          begin
            info  = JSON.parse(info_json.to_s)
            m     = Sketchup.active_model
            m.set_attribute(PREFS_KEY, 'client_name',    info['name'].to_s)
            m.set_attribute(PREFS_KEY, 'client_mobile',  info['mobile'].to_s)
            m.set_attribute(PREFS_KEY, 'client_email',   info['email'].to_s)
            m.set_attribute(PREFS_KEY, 'client_address', info['address'].to_s)
            safe_exec("window.scheduleManager.showNotification('Client info saved', 'success')")
          rescue => e
            log_error('saveClientInfo', e)
          end
        end
      end

      # Collect data from the model and push it to the JS ScheduleManager.
      def refresh_schedule_data
        return unless @dialog&.visible?
        unit_system, _label = detect_unit_system
        CabinetThumbnailCapture.capture_missing(Sketchup.active_model)
        rows = CabinetScheduleCollector.collect_all_cabinets(unit_system)
        safe_exec("window.scheduleManager.loadScheduleData(#{JSON.generate(rows)})")
      rescue => e
        log_error('refresh_schedule_data', e)
      end

      def select_cabinets(persistent_ids)
        model     = Sketchup.active_model
        selection = model.selection
        selection.clear
        entities  = persistent_ids.filter_map { |pid| model.find_entity_by_persistent_id(pid) }
        selection.add(entities)
        model.active_view.zoom(entities) unless entities.empty?
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

      def detect_unit_system
        lu = Sketchup.active_model.options['UnitsOptions']['LengthUnit']
        (lu == 0 || lu == 1) ? %w[imperial in] : %w[metric cm]
      end

      # Mutate the config_json stored on a definition; yields the parsed hash.
      def update_config_json(defn)
        json = defn.get_attribute('ml_cabinets', 'config_json')
        return unless json.is_a?(String) && !json.empty?
        cfg = JSON.parse(json)
        yield cfg
        defn.set_attribute('ml_cabinets', 'config_json', JSON.generate(cfg))
      rescue
        nil
      end

      # -----------------------------------------------------------------------
      # Export
      # -----------------------------------------------------------------------

      def export_schedule(format, rows, columns)
        ext = format == 'csv' ? 'csv' : 'html'

        # Use last-saved directory if available, falling back to Documents/home
        saved_dir = Sketchup.active_model.get_attribute(PREFS_KEY, 'last_export_dir', '').to_s
        default   = if saved_dir && Dir.exist?(saved_dir)
                      saved_dir
                    elsif Dir.exist?(File.expand_path('~/Documents'))
                      File.expand_path('~/Documents')
                    else
                      Dir.home
                    end

        path = ::UI.savepanel('Save Cabinet Schedule', default, "cabinet_schedule.#{ext}")
        return unless path

        path += ".#{ext}" unless path.end_with?(".#{ext}")

        # Remember the directory for next time
        Sketchup.active_model.set_attribute(PREFS_KEY, 'last_export_dir', File.dirname(path))

        case format
        when 'csv'  then write_csv(path, rows, columns)
        when 'html' then write_html(path, rows, columns)
        end

        safe_exec("window.scheduleManager.showNotification('Schedule exported successfully', 'success')")
      rescue => e
        safe_exec("window.scheduleManager.showNotification('Export failed', 'error')")
        log_error('export_schedule', e)
      end

      def write_csv(path, rows, columns)
        m           = Sketchup.active_model
        client_name = m.get_attribute(PREFS_KEY, 'client_name', '').to_s

        lines = []
        lines << csv_row(["Cabinet Schedule \u2014 #{m.title}"])
        lines << csv_row(["Generated: #{Time.now.strftime('%Y-%m-%d %H:%M')}"])
        lines << csv_row(["Client: #{client_name}"]) unless client_name.empty?
        lines << csv_row([])
        lines << csv_row(columns.map { |c| c['label'] || c['key'] })
        rows.each do |row|
          lines << csv_row(columns.map do |c|
            key = c['key'].to_s
            (row[key] || row[key.to_sym]).to_s
          end)
        end

        File.write(path, lines.join("\n"), encoding: 'UTF-8')
      end

      # Encodes a single CSV row: wraps fields containing commas/quotes/newlines
      # in double-quotes and escapes internal double-quotes per RFC 4180.
      def csv_row(fields)
        fields.map do |field|
          s = field.to_s
          if s.include?('"') || s.include?(',') || s.include?("\n")
            '"' + s.gsub('"', '""') + '"'
          else
            s
          end
        end.join(',')
      end

      def write_html(path, rows, columns)
        m              = Sketchup.active_model
        client_name    = m.get_attribute(PREFS_KEY, 'client_name',    '').to_s
        client_mobile  = m.get_attribute(PREFS_KEY, 'client_mobile',  '').to_s
        client_email   = m.get_attribute(PREFS_KEY, 'client_email',   '').to_s
        client_address = m.get_attribute(PREFS_KEY, 'client_address', '').to_s
        title_text     = "Cabinet Schedule Manager \u2014 #{m.title.capitalize}"

        # ------------------------------------------------------------------
        # Logo — embed as base64 so the HTML is fully self-contained
        # ------------------------------------------------------------------
        logo_tag = begin
          logo_path = File.join(MLCabinets::PLUGIN_DIR, 'icons', 'logo.png')
          logo_b64  = [[File.binread(logo_path)].pack('m0')].join
          "<img src=\"data:image/png;base64,#{logo_b64}\" alt=\"ML Cabinets\" class=\"logo\">"
        rescue
          ''
        end

        # ------------------------------------------------------------------
        # Table
        # ------------------------------------------------------------------
        header_row = columns.map { |c| "<th>#{c['label'] || c['key']}</th>" }.join
        total_qty  = rows.sum { |r| r['quantity'].to_i }
        total_val  = rows.sum { |r| r['subtotal'].to_f }

        data_rows = rows.map do |row|
          cells = columns.map do |c|
            key = c['key'].to_s
            val = (row[key] || row[key.to_sym]).to_s
            if key == 'thumbnail'
              img = val.empty? ? '' : "<img src=\"#{val}\" width=\"56\" height=\"56\" style=\"object-fit:contain;display:block\">"
              "<td style=\"padding:4px 12px;text-align:center\">#{img}</td>"
            else
              "<td>#{val}</td>"
            end
          end.join
          "<tr>#{cells}</tr>"
        end.join

        col_count = columns.size

        # ------------------------------------------------------------------
        # Client info block (only non-empty fields)
        # ------------------------------------------------------------------
        client_lines = [
          client_name.empty?    ? nil : "<strong>#{client_name}</strong>",
          client_mobile.empty?  ? nil : client_mobile,
          client_email.empty?   ? nil : client_email,
          client_address.empty? ? nil : client_address,
        ].compact
        client_block = client_lines.empty? ? '' :
          "<div class=\"client-block\">#{client_lines.join('<br>')}</div>"

        html = <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>#{title_text}</title>
            <style>
              *{box-sizing:border-box;margin:0;padding:0}
              body{font-family:-apple-system,'Segoe UI',sans-serif;font-size:13px;color:#1c2026;padding:32px}
              .brand{display:flex;align-items:center;gap:14px;padding-bottom:16px;margin-bottom:20px;border-bottom:2px solid #1a6fc4}
              .logo{height:44px;width:auto}
              .brand-name{font-size:22px;font-weight:700;color:#1a6fc4;letter-spacing:-0.3px}
              h1{font-size:16px;font-weight:600;margin-bottom:4px;margin-top:0}
              .meta{color:#5c6370;font-size:12px;margin-bottom:16px}
              .client-block{font-size:13px;line-height:1.7;margin-bottom:20px;color:#1c2026}
              table{width:100%;border-collapse:collapse}
              th{background:#1a6fc4;color:#fff;padding:8px 12px;text-align:left;font-size:12px;font-weight:600;white-space:nowrap}
              td{padding:8px 12px;border-bottom:1px solid #dde1e7;vertical-align:middle}
              tr:nth-child(even) td{background:#f5f6f8}
              .total td{font-weight:700;background:#eceef1;border-top:2px solid #1a6fc4}
              @media print{body{padding:16px}.brand{margin-bottom:12px}}
            </style>
          </head>
          <body>
            <div class="brand">
              #{logo_tag}
              <span class="brand-name">ML Cabinets</span>
            </div>
            <h1>#{title_text}</h1>
            <div class="meta">Generated: #{Time.now.strftime('%Y-%m-%d %H:%M')}</div>
            #{client_block}
            <table>
              <thead><tr>#{header_row}</tr></thead>
              <tbody>
                #{data_rows}
                <tr class="total">
                  <td colspan="#{[col_count - 2, 1].max}" style="text-align:right">TOTAL</td>
                  <td>#{total_qty}</td>
                  <td>$#{total_val.round(2)}</td>
                </tr>
              </tbody>
            </table>
          </body>
          </html>
        HTML

        File.write(path, html, encoding: 'UTF-8')
      end

      # -----------------------------------------------------------------------
      # Helpers
      # -----------------------------------------------------------------------

      def safe_exec(js)
        @dialog&.execute_script(js)
      rescue => e
        log_error('safe_exec', e)
      end

      def log_error(context, err)
        return unless defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
        puts "MLCabinets::ScheduleManagerDialog [#{context}] — #{err.message}"
        puts err.backtrace.first(3).join("\n")
      end

    end
  end
end
