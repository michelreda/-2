# ML Cabinets - Add to Library
# Entry point: validates selection and opens the HtmlDialog.
# File-existence helpers are kept here for use by AddToLibraryDialog.

require 'sketchup.rb'
require_relative 'library_handler'
require_relative 'add_cabinet_to_library'
require_relative 'add_leg_to_library'
require_relative 'add_profile_to_library'
require_relative 'add_panel_to_library'
require_relative 'add_handle_to_library'
require_relative 'add_image_to_library'

module MLCabinets
  class AddToLibrary

    # Main entry point — called from toolbar button and context menu.
    def self.add_to_library
      selection = Sketchup.active_model.selection
      entity    = selection.first

      unless entity
        ::UI.messagebox('Please select an object to add to the library.')
        return
      end

      if MLCabinets::UI::LibraryHandler.get_available_types.empty?
        ::UI.messagebox('No library handlers are available yet.')
        return
      end

      MLCabinets::Dialogs::AddToLibraryDialog.show(entity)
    end

    # ------------------------------------------------------------------
    # Check whether files already exist in the unified handles/ folder.
    # Called by AddToLibraryDialog for Handle overwrite detection.
    # ------------------------------------------------------------------

    def self.handle_files_exist(name)
      folder = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'handles', name)
      return false unless Dir.exist?(folder)

      %w[.png .skp .dae .json].any? { |ext| File.exist?(File.join(folder, "#{name}#{ext}")) }
    end

    # ------------------------------------------------------------------
    # Check whether files already exist in the unified panels/ folder.
    # Called by AddToLibraryDialog for Panel overwrite detection.
    # ------------------------------------------------------------------

    def self.panel_files_exist(name, _sub_types = nil)
      folder = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', name)
      return false unless Dir.exist?(folder)

      %w[.png .skp .dae .json].any? { |ext| File.exist?(File.join(folder, "#{name}#{ext}")) }
    end

    # ------------------------------------------------------------------
    # Check whether files already exist in the unified materials/ folder.
    # Called by AddToLibraryDialog for Material overwrite detection.
    # ------------------------------------------------------------------

    def self.image_files_exist(name)
      folder = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'materials', name)
      return false unless Dir.exist?(folder)

      File.exist?(File.join(folder, "#{name}.png"))
    end

    # ------------------------------------------------------------------
    # Check whether files already exist for a given name + single type.
    # Called by AddToLibraryDialog for non-Panel overwrite detection.
    # ------------------------------------------------------------------

    def self.files_exist_for_type(name, type)
      config = MLCabinets::UI::LibraryHandler::LIBRARY_TYPES[type]
      return false unless config && config[:folder]

      folder = File.join(MLCabinets::PLUGIN_DIR, 'libraries', config[:folder], name)
      return false unless Dir.exist?(folder)

      %w[.png .skp .dae .json].any? { |ext| File.exist?(File.join(folder, "#{name}#{ext}")) }
    end

  end # class AddToLibrary
end # module MLCabinets

