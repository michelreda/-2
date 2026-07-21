# ML Cabinets Extension - Registration
# This file lives at the Plugins root and registers the extension with SketchUp.

require 'sketchup.rb'
require 'extensions.rb'

module MLCabinets
  def self.registration_version
    candidates = [
      File.join(__dir__, 'VERSION'),
      File.join(__dir__, 'ML_Cabinets', 'VERSION')
    ]
    path = candidates.find { |candidate| File.exist?(candidate) }
    path ? File.read(path).strip : '0.0.0'
  rescue
    '0.0.0'
  end

  EXTENSION = SketchupExtension.new('ML Cabinets', 'ML_Cabinets/loader.rb')
  EXTENSION.version     = registration_version
  EXTENSION.description = 'Professional cabinet placement tool for SketchUp'
  EXTENSION.creator     = 'ML Extensions'
  EXTENSION.copyright   = '© 2026 ML Extensions'
  Sketchup.register_extension(EXTENSION, true)
end
