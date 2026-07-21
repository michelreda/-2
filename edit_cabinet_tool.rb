# ML Cabinets — Edit Cabinet Tool
#
# Interactive pick tool: hover over ML cabinet instances to highlight them,
# click to open the Edit Cabinet dialog. When a single cabinet is already
# selected, opens the dialog directly without activating the pick tool.
# When multiple cabinets are selected, opens the bulk-edit dialog (future).

module MLCabinets
  module UI
    class EditCabinetTool

      DA = 'dynamic_attributes'.freeze unless defined?(DA)

      # -------------------------------------------------------------------
      # Public entry point — called from toolbar/menu
      # -------------------------------------------------------------------

      def self.activate_or_edit
        model = Sketchup.active_model
        sel   = model.selection

        # Collect ML cabinet instances from the current selection
        cabinets = sel.select { |e| MLCabinets::CabinetDC.cabinet_instance?(e) }

        if cabinets.size == 1
          # Single cabinet selected → open edit dialog directly
          MLCabinets::Dialogs::NewCabinetDialog.show_edit(cabinets.first)
        elsif cabinets.size > 1
          # Multiple cabinets selected → open bulk edit dialog
          MLCabinets::Dialogs::NewCabinetDialog.show_bulk_edit(cabinets)
        else
          # Nothing selected → activate pick tool
          model.select_tool(EditCabinetTool.new)
        end
      end

      # -------------------------------------------------------------------
      # Tool lifecycle
      # -------------------------------------------------------------------

      def initialize
        @hover_entity = nil
        @hover_bounds = nil
      end

      def activate
        Sketchup.status_text = 'Click an ML cabinet to edit it. Press Esc to cancel.'
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        @hover_entity = nil
        @hover_bounds = nil
        view.invalidate
      end

      def resume(view)
        Sketchup.status_text = 'Click an ML cabinet to edit it. Press Esc to cancel.'
        view.invalidate
      end

      def onSetCursor
        @cursor_id ||= ::UI.create_cursor(
          File.join(MLCabinets::PLUGIN_DIR, 'icons', 'edit_cabinet_cursor.png'), 6, 27
        )
        ::UI.set_cursor(@cursor_id)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@hover_bounds) if @hover_bounds
        bb
      end

      # -------------------------------------------------------------------
      # Mouse move — highlight hovered cabinet
      # -------------------------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked

        # Walk up the instance path to find a cabinet root
        cabinet = _find_cabinet(entity, ph)

        if cabinet != @hover_entity
          @hover_entity = cabinet
          @hover_bounds = cabinet ? _world_bounds(cabinet) : nil
          view.invalidate
        end
      end

      # -------------------------------------------------------------------
      # Click — open edit dialog for the hovered cabinet
      # -------------------------------------------------------------------

      def onLButtonDown(_flags, _x, _y, _view)
        return unless @hover_entity

        entity = @hover_entity
        @hover_entity = nil
        @hover_bounds = nil

        # Deactivate the tool before opening the dialog
        Sketchup.active_model.select_tool(nil)

        MLCabinets::Dialogs::NewCabinetDialog.show_edit(entity)
      end

      # -------------------------------------------------------------------
      # Escape — cancel tool
      # -------------------------------------------------------------------

      def onKeyDown(key, _repeat, _flags, _view)
        if key == VK_ESCAPE
          Sketchup.active_model.select_tool(nil)
        end
      end

      # -------------------------------------------------------------------
      # Draw — wireframe highlight on hover
      # -------------------------------------------------------------------

      def draw(view)
        return unless @hover_bounds && @hover_bounds.size >= 8

        pts = @hover_bounds
        view.line_stipple = ''
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(26, 111, 196, 180)

        # Bottom face
        view.draw_polyline(pts[0], pts[1], pts[2], pts[3], pts[0])
        # Top face
        view.draw_polyline(pts[4], pts[5], pts[6], pts[7], pts[4])
        # Verticals
        4.times { |i| view.draw_line(pts[i], pts[i + 4]) }
      end

      private



      # Walk the pick path to find the outermost ML cabinet instance.
      def _find_cabinet(entity, pick_helper)
        return nil unless entity

        # Check if picked entity itself is a cabinet
        if entity.is_a?(Sketchup::ComponentInstance) && MLCabinets::CabinetDC.cabinet_instance?(entity)
          return entity
        end

        # Walk the pick path upward
        path = pick_helper.path_at(0)
        return nil unless path

        path.reverse_each do |e|
          if e.is_a?(Sketchup::ComponentInstance) && MLCabinets::CabinetDC.cabinet_instance?(e)
            return e
          end
        end
        nil
      end

      # Compute 8 world-space bounding box corner points for wireframe drawing.
      def _world_bounds(instance)
        bb = instance.bounds
        min = bb.min
        max = bb.max
        [
          Geom::Point3d.new(min.x, min.y, min.z),
          Geom::Point3d.new(max.x, min.y, min.z),
          Geom::Point3d.new(max.x, max.y, min.z),
          Geom::Point3d.new(min.x, max.y, min.z),
          Geom::Point3d.new(min.x, min.y, max.z),
          Geom::Point3d.new(max.x, min.y, max.z),
          Geom::Point3d.new(max.x, max.y, max.z),
          Geom::Point3d.new(min.x, max.y, max.z),
        ]
      end

    end # class EditCabinetTool
  end # module UI
end # module MLCabinets
