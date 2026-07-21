# ML Cabinets — Grain Picker Tool
#
# A lightweight two-click SketchUp tool activated from the Add to Library
# dialog.  The user draws a line anywhere in the scene; the tool compares the
# horizontal (X) extent against the vertical (Y) extent of that line and
# reports 'horizontal' or 'vertical' back to the dialog via execute_script.
#
# Lifecycle:
#   1. AddToLibraryDialog registers the 'start_grain_pick' callback.
#   2. JS calls sketchup.start_grain_pick() when the user clicks the button.
#   3. Ruby calls Sketchup.active_model.tools.push_tool(GrainPickerTool.new(dialog))
#   4. User clicks two points; tool detects grain and calls window.setGrainResult(grain).
#   5. ESC or second click pops the tool automatically.

module MLCabinets
  class GrainPickerTool

    CURSOR_PENCIL = 632 unless defined?(CURSOR_PENCIL)  # built-in SketchUp pencil cursor

    # Colour constants for the live preview line
    LINE_COLOR_DEFAULT  = Sketchup::Color.new(255, 140, 0)   # orange while picking first pt
    LINE_COLOR_ACTIVE   = Sketchup::Color.new(30,  144, 255) # blue while dragging to second pt

    def initialize(dialog)
      @dialog    = dialog
      @start_pt  = nil
      @current_pt = nil
      @ip        = nil     # Sketchup::InputPoint
      @done      = false
    end

    # -------------------------------------------------------------------------
    # Tool lifecycle
    # -------------------------------------------------------------------------

    def activate
      @ip = Sketchup::InputPoint.new
      Sketchup.status_text =
        'Grain direction: click the START point of the grain line'
      update_cursor
    end

    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      view.invalidate
      update_cursor
    end

    def suspend(_view); end

    # -------------------------------------------------------------------------
    # Mouse events
    # -------------------------------------------------------------------------

    def onMouseMove(_flags, x, y, view)
      @ip.pick(view, x, y)
      @current_pt = @ip.position
      view.invalidate
      view.tooltip = @ip.tooltip
    end

    def onLButtonDown(_flags, x, y, view)
      @ip.pick(view, x, y)
      pt = @ip.position.clone

      if @start_pt.nil?
        # First click — record start point
        @start_pt = pt
        Sketchup.status_text =
          'Grain direction: click the END point of the grain line'
      else
        # Second click — compute and report
        finish(pt, view)
      end
    end

    # -------------------------------------------------------------------------
    # Keyboard
    # -------------------------------------------------------------------------

    def onKeyDown(key, _repeat, _flags, _view)
      # VK_ESCAPE = 27
      if key == 27
        cancel
        return true
      end
      false
    end

    # -------------------------------------------------------------------------
    # Drawing
    # -------------------------------------------------------------------------

    def draw(view)
      return unless @start_pt && @current_pt

      dx = (@current_pt.x - @start_pt.x).abs
      dy = (@current_pt.y - @start_pt.y).abs
      color = dx >= dy ? LINE_COLOR_DEFAULT : LINE_COLOR_ACTIVE

      view.set_color_from_line(@start_pt, @current_pt)
      view.line_width = 2
      view.line_stipple = ''
      view.drawing_color = color
      view.draw_line(@start_pt, @current_pt)

      # Draw a small cross at the start point
      view.draw_points([@start_pt], 8, 2, color)
    end

    # -------------------------------------------------------------------------
    private
    # -------------------------------------------------------------------------

    def finish(end_pt, view)
      @done = true

      dx = (end_pt.x - @start_pt.x).abs
      dy = (end_pt.y - @start_pt.y).abs
      grain = dx >= dy ? 'horizontal' : 'vertical'

      begin
        @dialog.execute_script("window.setGrainResult(#{grain.to_json})")
      rescue => e
        puts "MLCabinets: GrainPickerTool.finish — #{e.message}" if MLCabinets::DEBUG
      end

      Sketchup.active_model.tools.pop_tool
      view.invalidate
    end

    def cancel
      begin
        @dialog.execute_script("window.cancelGrainPick()")
      rescue => e
        puts "MLCabinets: GrainPickerTool.cancel — #{e.message}" if MLCabinets::DEBUG
      end
      Sketchup.active_model.tools.pop_tool
    end

    def update_cursor
      ::UI.set_cursor(CURSOR_PENCIL)
    end

  end # class GrainPickerTool
end # module MLCabinets
