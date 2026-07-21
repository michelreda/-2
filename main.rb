# main.rb — entry point loaded by the extension manager

module SKBCam
  DIR = File.dirname(__FILE__)
end

require File.join(SKBCam::DIR, 'core', 'settings.rb')
require File.join(SKBCam::DIR, 'core', 'cabinet_generator.rb')
require File.join(SKBCam::DIR, 'core', 'radar.rb')
require File.join(SKBCam::DIR, 'core', 'bom_engine.rb')
require File.join(SKBCam::DIR, 'core', 'dialog_bridge.rb')

module SKBCam
  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins').add_submenu('Smart Kitchen Builder')
    menu.add_item('فتح لوحة التحكم') { SKBCam::DialogBridge.show }

    toolbar = UI::Toolbar.new('Smart Kitchen Builder')
    cmd = UI::Command.new('Kitchen Builder') { SKBCam::DialogBridge.show }
    cmd.tooltip = 'Smart Kitchen Builder & CAM'
    cmd.status_bar_text = 'فتح لوحة تصميم وتصنيع المطابخ'
    cmd.small_icon = cmd.large_icon = File.join(SKBCam::DIR, 'ui', 'icon.png')
    toolbar.add_item(cmd)
    toolbar.show

    file_loaded(__FILE__)
  end
end
