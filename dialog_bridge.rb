module SKBCam
  module DialogBridge
    def self.show
      @dialog ||= build_dialog
      @dialog.show
    end

    def self.build_dialog
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Smart Kitchen Builder & CAM',
        preferences_key: 'skb_cam_system',
        scrollable: true,
        resizable: true,
        width: 480,
        height: 720
      )
      dlg.set_file(File.join(SKBCam::DIR, 'ui', 'dialog.html'))

      dlg.add_action_callback('build_cabinet') do |_ctx, json|
        opts = parse(json)
        opts_sym = symbolize(opts)
        begin
          SKBCam::CabinetGenerator.build(opts_sym)
          dlg.execute_script("mhResult(#{ {ok: true}.to_json })")
        rescue => e
          dlg.execute_script("mhResult(#{ {ok: false, error: e.message}.to_json })")
        end
      end

      dlg.add_action_callback('run_radar') do |_ctx, _json|
        issues = SKBCam::Radar.run_as_json
        dlg.execute_script("mhRadarResult(#{issues.to_json})")
      end

      dlg.add_action_callback('get_settings') do |_ctx, _json|
        dlg.execute_script("mhSettingsResult(#{SKBCam::Settings.all.to_json})")
      end

      dlg.add_action_callback('save_settings') do |_ctx, json|
        SKBCam::Settings.set(parse(json))
        dlg.execute_script("mhSettingsResult(#{SKBCam::Settings.all.to_json})")
      end

      dlg.add_action_callback('get_cutlist') do |_ctx, _json|
        dlg.execute_script("mhCutlistResult(#{SKBCam::BomEngine.aggregate.to_json})")
      end

      dlg.add_action_callback('get_price') do |_ctx, _json|
        dlg.execute_script("mhPriceResult(#{SKBCam::BomEngine.estimate_price.to_json})")
      end

      dlg.add_action_callback('export_csv') do |_ctx, _json|
        path = UI.savepanel('حفظ Cut List', '', 'cutlist.csv')
        if path
          SKBCam::BomEngine.export_csv(path)
          dlg.execute_script("mhResult(#{ {ok: true, path: path}.to_json })")
        end
      end

      dlg
    end

    def self.parse(json)
      require 'json'
      JSON.parse(json)
    rescue
      {}
    end

    def self.symbolize(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end
end
