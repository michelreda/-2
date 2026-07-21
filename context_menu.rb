# ML Cabinets - Context Menu
# Adds "ML Cabinets" submenu to the right-click context menu.

module MLCabinets
  module UI
    class ContextMenu

      @@context_menu_name = 'ML Cabinets'

      def self.create_context_menu
        ::UI.add_context_menu_handler do |context_menu|
          submenu = context_menu.add_submenu(@@context_menu_name)
          submenu.add_item('Add to Library') do
            MLCabinets::AddToLibrary.add_to_library
          end
          submenu.add_item('Edit Cabinet') do
            MLCabinets::UI::EditCabinetTool.activate_or_edit
          end
          submenu.add_item('Style Picker') do
            Sketchup.active_model.select_tool(MLCabinets::UI::StylePickerTool.new)
          end
          submenu.add_item('Open / Close') do
            Sketchup.active_model.select_tool(MLCabinets::UI::OpenCloseTool.new)
          end
          submenu.add_item('Prepare for Manufacturing') do
            MLCabinets::UI::ManufacturingPrep.prepare_selected_cabinet
          end
        end
      rescue => e
        puts "MLCabinets: Error creating context menu — #{e.message}" if MLCabinets::DEBUG
      end

    end # class ContextMenu
  end # module UI
end # module MLCabinets
