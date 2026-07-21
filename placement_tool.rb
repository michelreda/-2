# ML Cabinets - Cabinet Placement Tool
# Shows a wireframe bounding-box preview under the cursor and places the
# cabinet instance on click.  Supports corner cycling, vertical anchor
# toggle, and 90° rotation — matching the ML_Kitchens reference tool
# but wired into the MLCabinets architecture.

module MLCabinets
  module UI
    class PlacementTool

      # Session state (persists across placements, resets on SketchUp restart)
      @@last_corner_index   = 1     # back-right
      @@last_vertical_top   = false # bottom anchor
      @@last_rotation_deg   = 0

      # ---------------------------------------------------------------
      # Initialization
      # ---------------------------------------------------------------

      # +build_result+ is the hash returned by CabinetDC.build_definition:
      #   { defn:, params:, parent_name: }
      def initialize(build_result)
        @defn        = build_result[:defn]
        @params      = build_result[:params]
        @parent_name = build_result[:parent_name]

        @model          = Sketchup.active_model
        @cursor_pos     = Geom::Point3d.new(0, 0, 0)
        @input_point    = nil

        # Compute a simple bounding box from the known dimensions (cm → inches)
        w = @params[:w_cm].cm
        h = @params[:h_cm].cm
        d = @params[:d_cm].cm

        # Height-from-floor offset (wall/tall cabinets)
        @hff = (@params[:hff_cm] || 0.0).cm

        # Corner cabinet type — drives preview shape.
        # Only activate corner shapes when this is actually a corner cabinet;
        # corner_type defaults to 'l-shaped' for all cabinet types in params.
        is_corner = (@params[:cab_type] || '').end_with?('-corner')
        @corner_type = is_corner ? (@params[:corner_type] || 'l-shaped') : nil

        if @corner_type == 'l-shaped'
          # L-shape footprint: (w+d) × (w+d) bounding square; one quadrant is notched
          total_xy = w + d
          @bb_min = Geom::Point3d.new(0, 0, @hff)
          @bb_max = Geom::Point3d.new(total_xy, total_xy, @hff + h)
          @l_wing_depth = d   # depth of each wing, used to draw the notch
        elsif @corner_type == 'blind'
          # Blind corner: rectangular — total width = w + d + blind margin (no thickness)
          # Margin: 3 in (7.62 cm) when unit is inches, 8 cm otherwise.
          unit      = (@params[:unit] || 'cm').to_s
          margin_cm = unit == 'in' ? MLCabinets::CornerCabinetDC::BLIND_MARGIN_IN_CM : MLCabinets::CornerCabinetDC::BLIND_MARGIN_CM
          total_w   = w + d + margin_cm.cm
          @bb_min = Geom::Point3d.new(0, 0, @hff)
          @bb_max = Geom::Point3d.new(total_w, d, @hff + h)
        else
          # Standard rectangular bounding box
          @bb_min = Geom::Point3d.new(0, 0, @hff)
          @bb_max = Geom::Point3d.new(w, d, @hff + h)
        end

        # Restore last-used settings
        @corner_index   = @@last_corner_index
        @is_top         = @@last_vertical_top
        @rotation_deg   = @@last_rotation_deg
      end

      # ---------------------------------------------------------------
      # SketchUp Tool callbacks
      # ---------------------------------------------------------------

      def activate
        if @defn.nil?
          ::UI.messagebox('Invalid cabinet definition.')
          @model.select_tool(nil)
          return
        end

        Sketchup.status_text =
          'Arrows: change corner/anchor | [ ]: rotate 90° | Esc: cancel | Click: place'
      end

      def deactivate(view)
        view.invalidate if view
      end

      def resume(_view)
        Sketchup.status_text =
          'Arrows: change corner/anchor | [ ]: rotate 90° | Esc: cancel | Click: place'
      end

      def suspend(_view); end

      # ------- Mouse --------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        @input_point = view.inputpoint(x, y)
        @cursor_pos  = @input_point.position
        view.invalidate
        false
      end

      def onLButtonDown(_flags, _x, _y, _view)
        place_cabinet
        true
      end

      # ------- Keyboard -----------------------------------------------

      CORNER_CYCLE = [1, 0, 2, 3].freeze unless defined?(CORNER_CYCLE)
      KEY_LEFT_ARROW  = [37, 63234].freeze unless defined?(KEY_LEFT_ARROW)
      KEY_RIGHT_ARROW = [39, 63235].freeze unless defined?(KEY_RIGHT_ARROW)
      KEY_UP_ARROW    = [38, 63232].freeze unless defined?(KEY_UP_ARROW)
      KEY_DOWN_ARROW  = [40, 63233].freeze unless defined?(KEY_DOWN_ARROW)
      KEY_ROTATE_CW   = [221, 93].freeze unless defined?(KEY_ROTATE_CW)
      KEY_ROTATE_CCW  = [219, 91].freeze unless defined?(KEY_ROTATE_CCW)

      def onKeyDown(key, _repeat, _flags, view)
        handled = false

        case key
        when *KEY_LEFT_ARROW  # Left arrow - previous corner
          idx = CORNER_CYCLE.index(@corner_index) || 0
          @corner_index = CORNER_CYCLE[(idx - 1) % 4]
          view.invalidate
          handled = true
        when *KEY_RIGHT_ARROW # Right arrow - next corner
          idx = CORNER_CYCLE.index(@corner_index) || 0
          @corner_index = CORNER_CYCLE[(idx + 1) % 4]
          view.invalidate
          handled = true
        when *KEY_UP_ARROW    # Up arrow - top anchor
          @is_top = true
          view.invalidate
          handled = true
        when *KEY_DOWN_ARROW  # Down arrow - bottom anchor
          @is_top = false
          view.invalidate
          handled = true
        when *KEY_ROTATE_CW   # ] - rotate CW 90 deg
          @rotation_deg = (@rotation_deg + 90) % 360
          view.invalidate
          handled = true
        when *KEY_ROTATE_CCW  # [ - rotate CCW 90 deg
          @rotation_deg = (@rotation_deg - 90) % 360
          view.invalidate
          handled = true
        when 27  # Escape — cancel
          @model.select_tool(nil)
          handled = true
        end

        handled
      end

      # ------- Draw ---------------------------------------------------

      def draw(view)
        if @corner_type == 'l-shaped'
          draw_l_shape_prism(view)
        else
          draw_box_prism(view)
        end
      end

      def draw_box_prism(view)
        corners = compute_box_corners
        return if corners.empty?

        # Back + side edges (blue wireframe)
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(100, 150, 255, 255)

        # Bottom face — back edge (0-1), sides (1-2, 3-0)
        view.draw_line(corners[0], corners[1])
        view.draw_line(corners[1], corners[2])
        view.draw_line(corners[3], corners[0])

        # Top face — back edge (4-5), sides (5-6, 7-4)
        view.draw_line(corners[4], corners[5])
        view.draw_line(corners[5], corners[6])
        view.draw_line(corners[7], corners[4])

        # Vertical edges
        4.times { |i| view.draw_line(corners[i], corners[i + 4]) }

        # Front edges (green, thicker)
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(50, 200, 50, 255)
        view.draw_line(corners[2], corners[3])  # bottom front
        view.draw_line(corners[6], corners[7])  # top front

        # Directional arrow showing front
        draw_front_arrow(view, corners)

        # Floor footprint + vertical leaders (when cabinet is elevated)
        draw_floor_footprint(view, corners) if @hff > 0

        # Anchor marker (orange cross)
        draw_anchor_marker(view)

        # Inference tooltip
        @input_point.draw(view) if @input_point
      end

      # ---------------------------------------------------------------
      private
      # ---------------------------------------------------------------

      # Return the anchor point in local (definition) coordinates.
      # Anchor stays at floor level (z=0) so clicking on the floor places correctly.
      def anchor_point
        x = (@corner_index == 0 || @corner_index == 2) ? @bb_min.x : @bb_max.x
        y = (@corner_index == 0 || @corner_index == 1) ? @bb_min.y : @bb_max.y
        z = @is_top ? @bb_max.z : 0.0
        Geom::Point3d.new(x, y, z)
      end

      # Build the world-space transformation: rotate around anchor, then
      # translate so the anchor lands on the cursor.
      def placement_transform
        ap = anchor_point
        rad = @rotation_deg * Math::PI / 180.0

        rotation    = Geom::Transformation.rotation(ap, Geom::Vector3d.new(0, 0, 1), rad)
        rotated_ap  = ap.transform(rotation)
        translation = Geom::Transformation.translation(@cursor_pos - rotated_ap)

        translation * rotation
      end

      # 8 bounding-box corners transformed to world space.
      def compute_box_corners
        min = @bb_min
        max = @bb_max
        local = [
          Geom::Point3d.new(min.x, min.y, min.z),
          Geom::Point3d.new(max.x, min.y, min.z),
          Geom::Point3d.new(max.x, max.y, min.z),
          Geom::Point3d.new(min.x, max.y, min.z),
          Geom::Point3d.new(min.x, min.y, max.z),
          Geom::Point3d.new(max.x, min.y, max.z),
          Geom::Point3d.new(max.x, max.y, max.z),
          Geom::Point3d.new(min.x, max.y, max.z),
        ]
        t = placement_transform
        local.map { |pt| t * pt }
      end

      # L-shaped prism preview — 6-vertex footprint, two open front faces (green)
      # and four outer walls (blue).
      #
      # Footprint polygon (CW from back-left, looking down):
      #   B0(0,0)  B1(tx,0)  B2(tx,d)  B3(d,d)  B4(d,ty)  B5(0,ty)
      # The notch (missing quadrant) is at X:[d,tx], Y:[d,ty].
      # Open faces: B2→B3 (main wing opening) and B3→B4 (side wing opening).
      def draw_l_shape_prism(view)
        d  = @l_wing_depth
        tx = @bb_max.x   # w + d
        ty = @bb_max.y   # w + d
        z0 = @bb_min.z   # hff
        z1 = @bb_max.z   # hff + h

        local_bot = [
          Geom::Point3d.new(0,  0,  z0),  # B0 — back-left (inner room corner)
          Geom::Point3d.new(tx, 0,  z0),  # B1 — back-right
          Geom::Point3d.new(tx, d,  z0),  # B2 — notch outer-right corner
          Geom::Point3d.new(d,  d,  z0),  # B3 — inner L junction
          Geom::Point3d.new(d,  ty, z0),  # B4 — notch outer-top corner
          Geom::Point3d.new(0,  ty, z0),  # B5 — far-top-left
        ]
        local_top = local_bot.map { |p| Geom::Point3d.new(p.x, p.y, z1) }

        tr  = placement_transform
        bot = local_bot.map { |p| tr * p }
        top = local_top.map { |p| tr * p }

        # ── Blue outer walls ────────────────────────────────────────
        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(100, 150, 255, 255)

        [[0,1],[1,2],[4,5],[5,0]].each do |a, b|
          view.draw_line(bot[a], bot[b])
          view.draw_line(top[a], top[b])
        end
        [0, 1, 5].each { |i| view.draw_line(bot[i], top[i]) }

        # ── Green open / front faces ─────────────────────────────────
        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(50, 200, 50, 255)

        [[2,3],[3,4]].each do |a, b|
          view.draw_line(bot[a], bot[b])
          view.draw_line(top[a], top[b])
        end
        [2, 3, 4].each { |i| view.draw_line(bot[i], top[i]) }

        # ── Diagonal outward arrow from inner corner ─────────────────
        tr_mid_z = z0 + (z1 - z0) * 0.5
        inner_world = tr * Geom::Point3d.new(d, d, tr_mid_z)
        back_world  = tr * Geom::Point3d.new(0, 0, tr_mid_z)
        dir = inner_world - back_world
        horiz = Geom::Vector3d.new(dir.x, dir.y, 0)
        if horiz.length > 0.01
          horiz.normalize!
          arrow_start = inner_world.offset(horiz, 5.cm)
          arrow_end   = arrow_start.offset(horiz, 15.cm)
          view.draw_line(arrow_start, arrow_end)
          perp = Geom::Vector3d.new(-horiz.y, horiz.x, 0).normalize!
          back_tip = arrow_end.offset(horiz, -5.cm)
          view.draw_line(arrow_end, back_tip.offset(perp,          3.cm))
          view.draw_line(arrow_end, back_tip.offset(perp.reverse!, 3.cm))
        end

        # ── Floor footprint (when elevated) ──────────────────────────
        if @hff > 0
          floor_z  = @cursor_pos.z
          floor    = bot.map { |p| Geom::Point3d.new(p.x, p.y, floor_z) }
          view.line_width = 1
          view.line_stipple = '_'
          view.drawing_color = Sketchup::Color.new(100, 150, 255, 180)
          6.times { |i| view.draw_line(floor[i], floor[(i + 1) % 6]) }
          view.line_stipple = '.'
          view.drawing_color = Sketchup::Color.new(100, 150, 255, 120)
          6.times { |i| view.draw_line(floor[i], bot[i]) }
          view.line_stipple = ''
        end

        draw_anchor_marker(view)
        @input_point.draw(view) if @input_point
      end

      # Floor-level footprint rectangle + vertical dashed leader lines
      # connecting the footprint to the elevated bounding box bottom face.
      def draw_floor_footprint(view, corners)
        # Project the 4 bottom-face corners down to z = cursor z (floor level)
        floor_z = @cursor_pos.z
        floor_corners = corners[0..3].map do |pt|
          Geom::Point3d.new(pt.x, pt.y, floor_z)
        end

        # Draw footprint rectangle (thin blue, stippled)
        view.line_width = 1
        view.line_stipple = '_'
        view.drawing_color = Sketchup::Color.new(100, 150, 255, 180)
        4.times { |i| view.draw_line(floor_corners[i], floor_corners[(i + 1) % 4]) }

        # Vertical leader lines from each floor corner up to the box bottom
        view.line_stipple = '.'
        view.drawing_color = Sketchup::Color.new(100, 150, 255, 120)
        4.times { |i| view.draw_line(floor_corners[i], corners[i]) }

        # Reset stipple for subsequent drawing
        view.line_stipple = ''
      end

      # Green arrow extending from the front face centre.
      def draw_front_arrow(view, corners)
        front_center = Geom::Point3d.linear_combination(0.5, corners[2], 0.5, corners[3])
        back_center  = Geom::Point3d.linear_combination(0.5, corners[0], 0.5, corners[1])

        dir = front_center - back_center
        horiz = Geom::Vector3d.new(dir.x, dir.y, 0)
        return if horiz.length < 0.01

        horiz.normalize!

        arrow_start = front_center.offset(horiz, 5.cm)
        arrow_end   = arrow_start.offset(horiz, 15.cm)

        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(50, 200, 50, 255)
        view.draw_line(arrow_start, arrow_end)

        # Arrowhead
        perp = Geom::Vector3d.new(-horiz.y, horiz.x, 0).normalize!
        back_pt = arrow_end.offset(horiz, -5.cm)
        view.draw_line(arrow_end, back_pt.offset(perp, 3.cm))
        view.draw_line(arrow_end, back_pt.offset(perp.reverse, 3.cm))
      end

      # Orange cross at the anchor point in world space.
      def draw_anchor_marker(view)
        t  = placement_transform
        wa = t * anchor_point

        view.line_width = 3
        view.drawing_color = Sketchup::Color.new(255, 165, 0, 255)

        arm = 15.cm
        x_axis = Geom::Vector3d.new(1, 0, 0)
        y_axis = Geom::Vector3d.new(0, 1, 0)

        view.draw_line(wa.offset(x_axis, -arm), wa.offset(x_axis, arm))
        view.draw_line(wa.offset(y_axis, -arm), wa.offset(y_axis, arm))
      end

      # Place the real cabinet instance at the current cursor location.
      def place_cabinet
        # The preview bounding box is elevated by hff, but the actual cabinet
        # definition geometry starts at z=0. Apply the hff offset so the real
        # cabinet matches the preview position.
        hff_lift = @hff > 0 ? Geom::Transformation.new([0, 0, @hff]) : Geom::Transformation.new
        final = placement_transform * hff_lift

        instance = MLCabinets::CabinetDC.place_instance(
          @defn, @parent_name, @params, final
        )

        if instance
          # Persist session state
          @@last_corner_index = @corner_index
          @@last_vertical_top = @is_top
          @@last_rotation_deg = @rotation_deg
        end

        # Deactivate tool after placement
        @model.select_tool(nil)
      end

    end # class PlacementTool
  end # module UI
end # module MLCabinets
