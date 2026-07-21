# skb_cam_system.rb
# Smart Kitchen Builder & CAM System
# Top-level loader required by SketchUp's Extension Manager.

require 'sketchup.rb'
require 'extensions.rb'

module SKBCam
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new(
      'Smart Kitchen Builder & CAM',
      File.join(File.dirname(__FILE__), 'skb_cam_system', 'main.rb')
    )
    ext.description = 'مصمم مطابخ ذكي: رسم كباين، مقاسات جاهزة، رادار كشف الأخطاء، Cut List وتصدير CNC.'
    ext.version     = '1.0.0'
    ext.creator     = 'MH Kitchen'
    ext.copyright   = '2026'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
