# ML Cabinets — Open / Close Tool
#
# Activates an interactive tool: click a door or drawer item to animate
# it open or closed. Clicking again toggles back.
#
# Architecture
# ------------
# 1.  onLButtonDown picks the deepest component under the cursor.
# 2.  find_openable walks the path upward to find a DoorLeaf*/DrawerFace
#     wrapper and its parent Item.
# 3.  compute_animation_data returns the closed and open world-space
#     Geom::Transformation values for the wrapper(s).
# 4.  OpenCloseAnimation drives frame-by-frame interpolation via the
#     Sketchup::Animation protocol.
# 5.  On completion the animation writes door_open (0/1) to the Item
#     instance attribute so DC re-evaluation (resize, reopen SketchUp)
#     snaps back to the correct pose via the rotz/rotx formula.
#
# Drawer specifics
# ----------------
# A drawer opens by sliding its Item container (not just the face) along
# the +Y axis (outward from the cabinet front). The Item holds both the
# DrawerBox and the DrawerFace, so they move together.

require 'sketchup.rb'

module MLCabinets
  module UI

    class OpenCloseTool

      DA             = 'dynamic_attributes'.freeze unless defined?(DA)
      ANIM_FRAMES    = 24   unless defined?(ANIM_FRAMES)   # total animation frames
      ANIM_INTERVAL  = 0.04 unless defined?(ANIM_INTERVAL) # seconds per frame (~50fps target)
      CURSOR_ARROW   = 0    unless defined?(CURSOR_ARROW)  # fallback built-in arrow cursor
      CURSOR_HAND    = 671  unless defined?(CURSOR_HAND)   # built-in hand/finger cursor

      # -----------------------------------------------------------------------
      # Tool lifecycle
      # -----------------------------------------------------------------------

      def initialize
        @hover_bounds  = nil   # Array of 3D points for bounding box wire (hover highlight)
        @cursor_id     = _load_cursor
        @running       = false # block double-clicks while animating
      end

      def activate
        update_cursor
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        @hover_bounds = nil
        view.invalidate
      end

      def resume(view)
        update_cursor
        view.invalidate
      end

      def onSetCursor
        update_cursor
      end

      def getExtents
        Geom::BoundingBox.new
      end

      def statusText
        'Click a door or drawer to open / close it. Click again to toggle.'
      end

      # -----------------------------------------------------------------------
      # Mouse move — highlight hovered door/drawer
      # -----------------------------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        return if @running

        ph = view.pick_helper(x, y, 10)
        result = _find_openable(ph)
        @hover_bounds = result ? _world_bounds(result[:anim_inst], result[:world_t]) : nil
        view.invalidate
      end

      # -----------------------------------------------------------------------
      # Click — toggle open/close
      # -----------------------------------------------------------------------

      def onLButtonDown(_flags, x, y, view)
        return if @running

        ph = view.pick_helper(x, y, 10)
        result = _find_openable(ph)
        return unless result

        item_inst   = result[:item_inst]
        anim_inst   = result[:anim_inst]
        world_t     = result[:world_t]
        item_type   = result[:item_type]
        door_sub    = result[:door_sub]
        oa          = result[:oa]
        is_open     = result[:is_open]
        is_corner   = result[:corner_door] == true
        target_open = !is_open

        item_depth_in = result[:item_depth_in]
        thickness_in  = result[:thickness_in] || 0.0
        anim_data = _compute_animation_data(
          anim_inst, world_t, item_inst, item_type, door_sub, oa, target_open,
          item_depth_in, result[:item_world_t], thickness_in,
          corner_inst:     result[:corner_inst],
          cabinet_world_t: result[:cabinet_world_t]
        )
        return unless anim_data

        @running   = true
        @hover_bounds = nil
        view.invalidate

        anim = OpenCloseAnimation.new(
          anim_data,
          on_complete: lambda {
            Sketchup.active_model.start_operation('Open / Close', true)
            item_inst.set_attribute('ml_cabinets', 'is_open', target_open)
            item_inst.set_attribute(DA, 'door_open', target_open ? '1' : '0')
            item_inst.set_attribute(DA, '_door_open_formula', target_open ? '1' : '0')
            # Corner doors: also mark the partner leaf's is_open state.
            result[:corner_inst]&.set_attribute('ml_cabinets', 'is_open', target_open) if is_corner
            # Corner doors have DC position formulas (x/y/z referencing the cabinet
            # parent) that snap the leaf back to its closed position on DC re-eval.
            # Skip redraw for corner doors to preserve the animated transform.
            _redraw_item_dc(item_inst) unless is_corner
            # Re-apply transforms that include the world-space shift (DC formulas
            # only handle rotation; the shift is maintained manually).
            # anim_data may contain both wing door entries for corner-fold.
            if target_open && item_type != 'drwr'
              anim_data.each do |d|
                # Persist the local closed-state transform so closing can reverse cleanly.
                d[:inst].set_attribute('ml_cabinets', 'closed_t', d[:from_t].to_a)
                d[:inst].transformation = d[:to_t]
              end
            elsif is_corner && !target_open
              # Closing corner doors: snap each leaf to its exact saved closed transform
              # and clear the persisted closed_t so the next open starts from scratch.
              anim_data.each do |d|
                d[:inst].transformation = d[:to_t]
                d[:inst].delete_attribute('ml_cabinets', 'closed_t')
              end
            end
            Sketchup.active_model.commit_operation
            @running = false
          }
        )
        view.animation = anim
      end

      # -----------------------------------------------------------------------
      # Draw — bounding-box hover highlight
      # -----------------------------------------------------------------------

      def draw(view)
        return unless @hover_bounds && @hover_bounds.size == 8

        pts = @hover_bounds
        edges = [
          [0,1],[1,2],[2,3],[3,0],  # bottom face
          [4,5],[5,6],[6,7],[7,4],  # top face
          [0,4],[1,5],[2,6],[3,7]   # verticals
        ]
        view.drawing_color = Sketchup::Color.new(30, 120, 255, 200)
        view.line_width    = 2
        view.line_stipple  = ''
        edges.each do |a, b|
          view.draw(GL_LINES, pts[a], pts[b])
        end
      end

      # -----------------------------------------------------------------------
      # Private helpers
      # -----------------------------------------------------------------------
      private

      def update_cursor
        ::UI.set_cursor(@cursor_id)
      end

      # Try to load the custom cursor icon; fall back to built-in hand cursor.
      def _load_cursor
        path = File.join(MLCabinets::PLUGIN_DIR, 'icons', 'open_close_cursor.png')
        if File.exist?(path)
          begin
            @cursor = ::UI.create_cursor(path, 0, 0)
            @cursor
          rescue => e
            warn "[MLCabinets::UI::OpenCloseTool] Failed to create cursor from #{path}: #{e.message}"
            CURSOR_HAND
          end
        else
          CURSOR_HAND
        end
      end

      # Walk the pick path from deepest to shallowest, looking for a
      # DoorLeaf* or DrawerFace wrapper whose parent Item has the expected
      # i_type attribute.
      #
      # Returns a hash or nil:
      #   item_inst:  the Item ComponentInstance (carries door_open / oa attrs)
      #   anim_inst:  the DoorLeaf / DrawerFace / Item instance to animate
      #   world_t:    world-space Geom::Transformation of anim_inst
      #   item_type:  'door' | 'drwr'
      #   door_sub:   string (door-hinge-left etc.) or nil
      #   oa:         opening amount 0–100
      #   is_open:    current open state (bool)
      def _find_openable(ph)
        count = ph.count
        return nil if count == 0

        # Use the deepest pick path — it contains the full ancestor chain from
        # the model root down to whatever face/edge was hit.
        best_path = nil
        (count - 1).downto(0) do |pick_idx|
          p = ph.path_at(pick_idx)
          best_path = p if p && p.length > (best_path&.length || 0)
        end
        return nil unless best_path

        # Walk the path looking for a DoorLeaf* or DrawerFace instance.
        # The nearest Item ancestor (searching backwards from the leaf) is the
        # animated container. This handles arbitrary nesting depth (Cabinet >
        # Group > Item > DoorLeaf > DoorLeafPanel etc.).
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          defn_name = entity.definition.name
          is_leaf   = defn_name.start_with?('DoorLeaf')
          is_face   = defn_name.start_with?('DrawerFace')
          next unless is_leaf || is_face

          # Search backwards through ancestors for the nearest Item
          item_inst  = nil
          item_idx   = nil
          (idx - 1).downto(0) do |ai|
            anc = best_path[ai]
            next unless anc.is_a?(Sketchup::ComponentInstance)
            i_type_check = anc.get_attribute(DA, 'i_type').to_s
            if i_type_check == 'door' || i_type_check == 'drwr'
              item_inst = anc
              item_idx  = ai
              break
            end
          end
          next unless item_inst

          i_type = item_inst.get_attribute(DA, 'i_type').to_s
          door_sub = item_inst.get_attribute(DA, 'door_sub').to_s
          oa       = item_inst.get_attribute(DA, 'oa').to_f
          oa       = 50.0 if oa <= 0
          is_open  = item_inst.get_attribute('ml_cabinets', 'is_open') == true

          # Cumulative world transform up to (but not including) the target instance
          ancestors_t = lambda { |upto_idx|
            best_path[0...upto_idx].inject(Geom::Transformation.new) { |t, e|
              e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
            }
          }

          if i_type == 'drwr'
            item_world_t = ancestors_t.(item_idx) * item_inst.transformation
            # Item DC is a pure geometry-less container — item_inst.bounds.depth = 0.
            # Read depth from the parent Group (best_path[item_idx-1]) whose child
            # items/panels have real geometry, giving the evaluated cabinet depth.
            parent_inst = item_idx > 0 ? best_path[item_idx - 1] : nil
            item_depth_in = parent_inst.is_a?(Sketchup::ComponentInstance) ? parent_inst.bounds.depth : 0.0
            item_depth_in = item_depth_in.to_f
            return {
              item_inst:    item_inst,
              anim_inst:    item_inst,
              world_t:      item_world_t,
              item_type:    'drwr',
              door_sub:     nil,
              oa:           oa,
              is_open:      is_open,
              item_depth_in: item_depth_in
            }
          else
            item_world_t = ancestors_t.(item_idx) * item_inst.transformation
            leaf_world_t = ancestors_t.(idx) * entity.transformation
            leaf_leny    = entity.get_attribute(DA, 'leny').to_f
            thk_in       = leaf_leny > 0 ? leaf_leny : entity.definition.bounds.depth
            return {
              item_inst:     item_inst,
              anim_inst:     entity,
              world_t:       leaf_world_t,
              item_world_t:  item_world_t,
              item_type:     'door',
              door_sub:      door_sub,
              oa:            oa,
              is_open:       is_open,
              thickness_in:  thk_in
            }
          end
        end

        # --- Fallback: L-shaped corner cabinet doors ---
        # Corner cabinet doors are placed directly on the cabinet definition
        # without a Group > Item wrapper.  Both doors are found and animated
        # together as a single 90-degree fold (both leaves rotate around the
        # shared inner-corner hinge simultaneously).
        #
        # Detection uses:
        #   1. ml_cabinets/corner_door attribute  (new + old cabinets)
        #   2. Instance name pattern              (old cabinets without the attribute)
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)

          is_corner_door =
            !entity.get_attribute('ml_cabinets', 'corner_door').to_s.empty? ||
            entity.name.to_s =~ /\ACorner (Left|Right) Wing Door\z/

          next unless is_corner_door

          # Find the partner door (sibling in the same parent entities).
          # entity.parent is a ComponentDefinition — use .entities to iterate.
          partner = entity.parent.entities.grep(Sketchup::ComponentInstance).find do |e|
            e != entity &&
              (!e.get_attribute('ml_cabinets', 'corner_door').to_s.empty? ||
               e.name.to_s =~ /\ACorner (Left|Right) Wing Door\z/)
          end

          # Compute cabinet-world transform from pick path.
          # When the user is in the cabinet's edit context the cabinet instance
          # is not in the path — use identity in that case (camera space = model).
          cab_world_t = Geom::Transformation.new
          idx.downto(0) do |ai|
            anc = best_path[ai]
            next unless anc.is_a?(Sketchup::ComponentInstance)
            next if anc.equal?(entity)
            if CabinetDC.cabinet_instance?(anc)
              cab_world_t = best_path[0...ai].inject(Geom::Transformation.new) { |t, e|
                e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
              } * anc.transformation
              break
            end
          end

          oa      = entity.get_attribute(DA, 'oa').to_f
          oa      = 50.0 if oa <= 0
          # is_open state: check lwd (left wing door) as the canonical source.
          # Use corner_door attribute ('lw'/'rw') for reliable identification,
          # with name-based fallback for old cabinets.
          tag = entity.get_attribute('ml_cabinets', 'corner_door').to_s
          lwd = if tag == 'lw'
                  entity
                elsif tag == 'rw' && partner
                  partner
                elsif entity.name.to_s.include?('Left Wing')
                  entity
                else
                  partner
                end
          lwd   ||= entity
          is_open = lwd.get_attribute('ml_cabinets', 'is_open') == true

          world_t   = cab_world_t * entity.transformation
          leaf_leny = entity.get_attribute(DA, 'leny').to_f
          thk_in    = leaf_leny > 0 ? leaf_leny : entity.definition.bounds.depth

          return {
            item_inst:       entity,
            anim_inst:       entity,
            world_t:         world_t,
            item_world_t:    world_t,
            item_type:       'door',
            door_sub:        'corner-fold',   # signals _corner_fold_anim_data
            oa:              oa,
            is_open:         is_open,
            thickness_in:    thk_in,
            corner_door:     true,
            corner_inst:     partner,
            corner_lwd:      lwd,
            cabinet_world_t: cab_world_t,
          }
        end

        nil
      end

      # Returns [{inst:, from_t:, to_t:}] or nil.
      # For double-door, the Item contains DoorLeafL and DoorLeafR — both
      # are collected and animated simultaneously.
      # For corner-fold, both corner door leaves rotate around a shared hinge.
      def _compute_animation_data(anim_inst, world_t, item_inst, item_type, door_sub, oa, target_open,
                                  item_depth_in = nil, item_world_t = nil, thickness_in = 0.0,
                                  corner_inst: nil, cabinet_world_t: nil)
        if item_type == 'drwr'
          return _drawer_anim_data(anim_inst, world_t, item_inst, oa, target_open, item_depth_in)
        end

        if door_sub == 'double-door'
          return _double_door_anim_data(item_inst, item_world_t || world_t, oa, target_open, thickness_in)
        end

        if door_sub == 'corner-fold'
          return _corner_fold_anim_data(anim_inst, corner_inst, cabinet_world_t || world_t, oa, target_open)
        end

        _single_door_anim_data(anim_inst, world_t, item_inst, door_sub, oa, target_open, thickness_in, item_world_t)
      end

      # Single door animation data.
      #
      # Coordinate system contract:
      #   world_t   = world-space transform of leaf_inst
      #               (= ancestors_world_t * leaf_inst.transformation)
      #   from_t    = leaf_inst.transformation  (leaf local → parent space)
      #   parent_t  = world_t * from_t.inverse  (parent → world)
      #
      # DC rotz/rotx pivot is always at the leaf's local origin (0,0,0).
      # We express the hinge edge in leaf-LOCAL space, convert to world space
      # for the rotation call, then convert the resulting world transform back
      # into parent space so it can be assigned to inst.transformation.
      #
      # to_t = parent_t.inverse * R_world * parent_t * from_t
      #      where R_world = Geom::Transformation.rotation(pivot_world, axis_world, angle)
      def _single_door_anim_data(leaf_inst, world_t, item_inst, door_sub, oa, target_open, thickness_in = 0.0, item_world_t = nil)
        angle_deg = oa / 100.0 * 90.0
        angle_rad = angle_deg * Math::PI / 180.0

        from_t    = leaf_inst.transformation
        parent_t  = world_t * from_t.inverse   # parent → world

        # When closing, recover the CLOSED-state world transform from the saved
        # attribute so that pivot, axis, and shift are computed from a stable
        # reference frame (the hinge hasn't moved, the axes aren't rotated).
        closing = !target_open
        if closing
          closed_arr = leaf_inst.get_attribute('ml_cabinets', 'closed_t')
          if closed_arr
            closed_local_t = Geom::Transformation.new(closed_arr)
            world_closed   = parent_t * closed_local_t
          else
            # No saved closed transform — use item_world_t as best available
            # stable reference for axes (it doesn't rotate with the leaf).
            world_closed = world_t
          end
        else
          world_closed = world_t
        end

        # Stable reference frame: use item_world_t when available — its axes
        # don't change between open / closed states. Fall back to world_closed.
        ref_t   = item_world_t || world_closed
        local_x = ref_t.xaxis
        local_z = ref_t.zaxis

        # Pivot, axis, and shift are always expressed from the CLOSED state so
        # they remain correct for both opening and closing.
        # Sign is always the OPENING direction; closing uses 1-t interpolation.
        # When the parent is mirrored, CCW becomes CW — negate all signs.
        msign = _mirrored?(parent_t) ? -1 : 1

        case door_sub.to_s
        when 'door-hinge-left'
          leaf_lenx = _dc_lenx(leaf_inst)
          pivot_local = Geom::Point3d.new(leaf_lenx, 0, 0)
          pivot = pivot_local.transform(world_closed)
          axis  = world_closed.zaxis
          sign  = -1 * msign   # opening direction for left hinge
          base_shift = Geom::Vector3d.new(
            -local_x.x * thickness_in, -local_x.y * thickness_in, -local_x.z * thickness_in
          )

        when 'door-hinge-top'
          leaf_lenz = _dc_lenz(leaf_inst)
          pivot_local = Geom::Point3d.new(0, 0, leaf_lenz)
          pivot = pivot_local.transform(world_closed)
          axis  = world_closed.xaxis
          sign  = 1 * msign    # opening direction for top hinge
          base_shift = Geom::Vector3d.new(
            -local_z.x * thickness_in, -local_z.y * thickness_in, -local_z.z * thickness_in
          )

        when 'door-hinge-bottom'
          pivot = world_closed.origin
          axis  = world_closed.xaxis
          sign  = -1 * msign   # opening direction for bottom hinge
          base_shift = Geom::Vector3d.new(
            local_z.x * thickness_in, local_z.y * thickness_in, local_z.z * thickness_in
          )

        else
          pivot = world_closed.origin
          axis  = world_closed.zaxis
          sign  = 1 * msign    # opening direction for right hinge
          base_shift = Geom::Vector3d.new(
            local_x.x * thickness_in, local_x.y * thickness_in, local_x.z * thickness_in
          )
        end

        # Compute the OPEN transform from the closed reference
        r_world = Geom::Transformation.rotation(pivot, axis, sign * angle_rad)
        shift_t = Geom::Transformation.translation(base_shift)
        open_local_t = parent_t.inverse * shift_t * r_world * world_closed

        if closing
          to_t = (closed_arr ? closed_local_t : from_t)
          [{ inst: leaf_inst, from_t: from_t, to_t: to_t,
             pivot: pivot, axis: axis, sign: sign, angle_rad: angle_rad,
             world_closed: world_closed, parent_t: parent_t, shift_vec: base_shift,
             closing: true }]
        else
          [{ inst: leaf_inst, from_t: from_t, to_t: open_local_t,
             pivot: pivot, axis: axis, sign: sign, angle_rad: angle_rad,
             world_closed: world_closed, parent_t: parent_t, shift_vec: base_shift }]
        end
      rescue => e
        puts "MLCabinets OpenCloseTool: _single_door_anim_data error — #{e.message}" if MLCabinets::DEBUG
        nil
      end

      # Return the evaluated lenx of a leaf instance.
      # Try the DA attribute first (set as a float string after DC evaluation),
      # fall back to the bounding box width.
      def _dc_lenx(inst)
        v = inst.get_attribute(DA, 'lenx').to_f
        v > 0 ? v : inst.bounds.width.to_f
      end

      def _dc_lenz(inst)
        v = inst.get_attribute(DA, 'lenz').to_f
        v > 0 ? v : inst.bounds.height.to_f
      end

      # Detect mirrored transform (Flip Along / Scale -1).
      # Returns true when the 3x3 rotation-scale part has a negative determinant,
      # meaning the coordinate system is left-handed (an odd number of axis flips).
      def _mirrored?(t)
        a = t.to_a
        det = a[0] * (a[5] * a[10] - a[6] * a[9]) -
              a[4] * (a[1] * a[10] - a[2] * a[9]) +
              a[8] * (a[1] * a[6]  - a[2] * a[5])
        det < 0
      end

      # Double door: both DoorLeafL and DoorLeafR in the Item's entities.
      # Left leaf: hinge at its local origin (x=0) — opens CCW (+rotz).
      # Right leaf: hinge at its right edge (x=lenx) — opens CW (-rotz).
      def _double_door_anim_data(item_inst, item_world_t, oa, target_open, thickness_in = 0.0)
        angle_deg = oa / 100.0 * 90.0
        angle_rad = angle_deg * Math::PI / 180.0
        closing   = !target_open

        # item_world_t is the Item's world transform (ancestors * item.transformation),
        # so leaves' world transform = item_world_t * leaf.transformation.
        # Use item_world_t axes for stable shift direction (doesn't rotate with leaf).
        results = []
        item_inst.definition.entities.each do |e|
          next unless e.is_a?(Sketchup::ComponentInstance)
          defn_name = e.definition.name
          is_left  = defn_name.start_with?('DoorLeafL')
          is_right = defn_name.start_with?('DoorLeafR')
          next unless is_left || is_right

          from_t   = e.transformation
          parent_t = item_world_t   # leaves' parent IS the Item

          # Recover the closed-state world transform when closing
          if closing
            closed_arr = e.get_attribute('ml_cabinets', 'closed_t')
            if closed_arr
              closed_local_t = Geom::Transformation.new(closed_arr)
              leaf_world_closed = parent_t * closed_local_t
            else
              leaf_world_closed = parent_t * from_t
            end
          else
            leaf_world_closed = parent_t * from_t
          end

          # Pivot, axis, and shift from the CLOSED state (stable reference)
          lx = item_world_t.xaxis  # stable X axis from Item
          # When mirrored, negate rotation signs.
          msign = _mirrored?(parent_t) ? -1 : 1

          if is_left
            pivot = leaf_world_closed.origin
            axis  = leaf_world_closed.zaxis
            sign  = 1 * msign   # opening direction
            base_shift = Geom::Vector3d.new(
              lx.x * thickness_in, lx.y * thickness_in, lx.z * thickness_in
            )
          else
            leaf_lenx = _dc_lenx(e)
            pivot_local = Geom::Point3d.new(leaf_lenx, 0, 0)
            pivot = pivot_local.transform(leaf_world_closed)
            axis  = leaf_world_closed.zaxis
            sign  = -1 * msign  # opening direction
            base_shift = Geom::Vector3d.new(
              -lx.x * thickness_in, -lx.y * thickness_in, -lx.z * thickness_in
            )
          end

          r_world = Geom::Transformation.rotation(pivot, axis, sign * angle_rad)
          shift_t = Geom::Transformation.translation(base_shift)
          open_local_t = parent_t.inverse * shift_t * r_world * leaf_world_closed

          if closing
            to_t = closed_arr ? closed_local_t : from_t
            results << { inst: e, from_t: from_t, to_t: to_t,
                         pivot: pivot, axis: axis, sign: sign, angle_rad: angle_rad,
                         world_closed: leaf_world_closed, parent_t: parent_t,
                         shift_vec: base_shift, closing: true }
          else
            results << { inst: e, from_t: from_t, to_t: open_local_t,
                         pivot: pivot, axis: axis, sign: sign, angle_rad: angle_rad,
                         world_closed: leaf_world_closed, parent_t: parent_t,
                         shift_vec: base_shift }
          end
        end

        results.empty? ? nil : results
      rescue => e
        puts "MLCabinets OpenCloseTool: _double_door_anim_data error — #{e.message}" if MLCabinets::DEBUG
        nil
      end

      # Corner bi-fold: RWD is hinged to the Left Wing Side panel,
      # LWD is hinged to RWD at the inner junction and folds onto it.
      #
      #   RWD (rotz=-90): pivot at its origin (near the side panel).
      #     Swings outward — CCW from above (sign = +1).
      #
      #   LWD (no rotation): hinge at its origin (inner junction ≈ RWD far end).
      #     Rides with RWD's swing, then folds at the moving junction — CCW (sign = +1).
      #     At full open (90°) LWD lies flat against RWD.
      #
      # Handles ride with their respective door.
      def _corner_fold_anim_data(primary_door, partner_door, cabinet_world_t, oa, target_open)
        angle_deg = oa / 100.0 * 90.0
        angle_rad = angle_deg * Math::PI / 180.0
        closing   = !target_open
        parent_t  = cabinet_world_t

        # Identify lwd (Left Wing Door) and rwd (Right Wing Door)
        lwd = nil; rwd = nil
        [primary_door, partner_door].compact.each do |d|
          tag = d.get_attribute('ml_cabinets', 'corner_door').to_s
          case tag
          when 'lw' then lwd = d
          when 'rw' then rwd = d
          else
            if d.name.to_s.include?('Left')
              lwd = d
            else
              rwd = d
            end
          end
        end
        lwd ||= primary_door
        rwd ||= partner_door || primary_door

        all_siblings = primary_door.parent.entities.grep(Sketchup::ComponentInstance)
        lw_handle = all_siblings.find { |e| e.name.to_s.include?('Left Wing Door Handle') }
        rw_handle = all_siblings.find { |e| e.name.to_s.include?('Right Wing Door Handle') }

        axis = cabinet_world_t.zaxis   # stable vertical axis

        # ---- Closed-state world transforms ----
        rwd_from = rwd.transformation
        rwd_closed_arr = rwd.get_attribute('ml_cabinets', 'closed_t')
        rwd_closed_local = rwd_closed_arr ? Geom::Transformation.new(rwd_closed_arr) : rwd_from
        rwd_world_closed = parent_t * (closing ? rwd_closed_local : rwd_from)

        lwd_from = lwd.transformation
        lwd_closed_arr = lwd.get_attribute('ml_cabinets', 'closed_t')
        lwd_closed_local = lwd_closed_arr ? Geom::Transformation.new(lwd_closed_arr) : lwd_from
        lwd_world_closed = parent_t * (closing ? lwd_closed_local : lwd_from)

        # When mirrored, negate rotation signs.
        msign = _mirrored?(parent_t) ? -1 : 1

        # ---- RWD: swing around its origin (hinged to Left Wing Side panel) ----
        rwd_pivot = rwd_world_closed.origin
        rwd_sign  = 1 * msign   # CCW from above — swings outward (flipped when mirrored)

        r_rwd_full = Geom::Transformation.rotation(rwd_pivot, axis, rwd_sign * angle_rad)

        results = []

        if closing
          to_t = rwd_closed_arr ? Geom::Transformation.new(rwd_closed_arr) : rwd_from
          results << { inst: rwd, from_t: rwd_from, to_t: to_t,
                       pivot: rwd_pivot, axis: axis, sign: rwd_sign, angle_rad: angle_rad,
                       world_closed: rwd_world_closed, parent_t: parent_t, closing: true }
        else
          rwd_open_world = r_rwd_full * rwd_world_closed
          to_t = parent_t.inverse * rwd_open_world
          results << { inst: rwd, from_t: rwd_from, to_t: to_t,
                       pivot: rwd_pivot, axis: axis, sign: rwd_sign, angle_rad: angle_rad,
                       world_closed: rwd_world_closed, parent_t: parent_t }
        end

        # RW handle rides with RWD swing
        if rw_handle
          _add_rider(results, rw_handle, parent_t, r_rwd_full,
                     rwd_pivot, axis, rwd_sign, angle_rad, closing)
        end

        # ---- LWD: bi-fold (rides with RWD swing + folds at junction) ----
        # Junction = LWD's origin in world space (where LWD meets RWD at inner corner)
        junction_closed = lwd_world_closed.origin
        fold_sign = 1 * msign   # CCW — folds LWD flat onto RWD (flipped when mirrored)

        # Compute full-open transform for to_t
        junction_open = junction_closed.transform(r_rwd_full)
        r_fold_full = Geom::Transformation.rotation(junction_open, axis, fold_sign * angle_rad)
        lwd_open_world = r_fold_full * r_rwd_full * lwd_world_closed

        if closing
          to_t = lwd_closed_arr ? Geom::Transformation.new(lwd_closed_arr) : lwd_from
          results << { inst: lwd, from_t: lwd_from, to_t: to_t,
                       bifold: true,
                       swing_pivot: rwd_pivot, fold_junction_closed: junction_closed,
                       axis: axis, swing_sign: rwd_sign, fold_sign: fold_sign,
                       angle_rad: angle_rad,
                       world_closed: lwd_world_closed, parent_t: parent_t, closing: true }
        else
          to_t = parent_t.inverse * lwd_open_world
          results << { inst: lwd, from_t: lwd_from, to_t: to_t,
                       bifold: true,
                       swing_pivot: rwd_pivot, fold_junction_closed: junction_closed,
                       axis: axis, swing_sign: rwd_sign, fold_sign: fold_sign,
                       angle_rad: angle_rad,
                       world_closed: lwd_world_closed, parent_t: parent_t }
        end

        # LW handle rides with LWD (compound: swing + fold)
        if lw_handle
          h_from = lw_handle.transformation
          h_closed_arr = lw_handle.get_attribute('ml_cabinets', 'closed_t')
          h_closed_local = h_closed_arr ? Geom::Transformation.new(h_closed_arr) : h_from
          h_world_closed = parent_t * (closing ? h_closed_local : h_from)
          h_open_world = r_fold_full * r_rwd_full * h_world_closed

          if closing
            to_t = h_closed_arr ? Geom::Transformation.new(h_closed_arr) : h_from
            results << { inst: lw_handle, from_t: h_from, to_t: to_t,
                         bifold: true,
                         swing_pivot: rwd_pivot, fold_junction_closed: junction_closed,
                         axis: axis, swing_sign: rwd_sign, fold_sign: fold_sign,
                         angle_rad: angle_rad,
                         world_closed: h_world_closed, parent_t: parent_t, closing: true }
          else
            to_t = parent_t.inverse * h_open_world
            results << { inst: lw_handle, from_t: h_from, to_t: to_t,
                         bifold: true,
                         swing_pivot: rwd_pivot, fold_junction_closed: junction_closed,
                         axis: axis, swing_sign: rwd_sign, fold_sign: fold_sign,
                         angle_rad: angle_rad,
                         world_closed: h_world_closed, parent_t: parent_t }
          end
        end

        results.empty? ? nil : results
      rescue => e
        puts "MLCabinets OpenCloseTool: _corner_fold_anim_data error — #{e.message}" if MLCabinets::DEBUG
        nil
      end

      # Helper: add a handle (or other rider) to the animation results,
      # rotating around the same pivot as its parent door.
      def _add_rider(results, rider, parent_t, rotation_t, pivot, axis, sign, angle_rad, closing)
        h_from = rider.transformation
        h_closed_arr = rider.get_attribute('ml_cabinets', 'closed_t')
        h_closed_local = h_closed_arr ? Geom::Transformation.new(h_closed_arr) : h_from
        h_world_closed = parent_t * (closing ? h_closed_local : h_from)

        if closing
          to_t = h_closed_arr ? Geom::Transformation.new(h_closed_arr) : h_from
          results << { inst: rider, from_t: h_from, to_t: to_t,
                       pivot: pivot, axis: axis, sign: sign, angle_rad: angle_rad,
                       world_closed: h_world_closed, parent_t: parent_t, closing: true }
        else
          open_world = rotation_t * h_world_closed
          to_t = parent_t.inverse * open_world
          results << { inst: rider, from_t: h_from, to_t: to_t,
                       pivot: pivot, axis: axis, sign: sign, angle_rad: angle_rad,
                       world_closed: h_world_closed, parent_t: parent_t }
        end
      end

      # Drawer: translate the Item along its local Y axis (outward).
      # depth_in: pre-measured item depth in inches (passed from _find_openable to avoid
      # re-reading DC formula strings that haven't been evaluated to a number yet).
      def _drawer_anim_data(item_inst, item_world_t, item_defn_or_inst, oa, target_open, depth_in = nil)
        # Prefer the DrawerBox child's actual depth (Y dimension in its local space).
        # The DrawerBox lives inside the Item definition — find it by name prefix.
        box_depth = nil
        item_inst.definition.entities.each do |e|
          next unless e.is_a?(Sketchup::ComponentInstance)
          next unless e.definition.name.start_with?('DrawerBox')
          box_depth = e.definition.bounds.height
          box_depth = e.bounds.height if box_depth.nil? || box_depth <= 0
          break
        end

        # Fall back to the cabinet depth captured at pick time.
        box_depth = depth_in if box_depth.nil? || box_depth <= 0
        box_depth ||= item_inst.bounds.height
        box_depth   = item_inst.definition.bounds.height if box_depth <= 0

        # oa is a 0–100 percentage of the drawer box depth.
        travel = oa / 100.0 * box_depth

        # Item's local Y axis in world space (outward from cabinet front)
        y_axis = item_world_t.yaxis

        from_t   = item_inst.transformation
        parent_t = item_world_t * from_t.inverse  # Group → world

        delta  = target_open ? travel : -travel
        offset_vec = Geom::Vector3d.new(
          y_axis.x * delta,
          y_axis.y * delta,
          y_axis.z * delta
        )
        # Convert the world-space translation back into parent (Group) space
        shift_world = Geom::Transformation.translation(offset_vec)
        to_t = parent_t.inverse * shift_world * item_world_t

        [{ inst: item_inst, from_t: from_t, to_t: to_t }]
      rescue => e
        puts "MLCabinets OpenCloseTool: _drawer_anim_data error — #{e.message}" if MLCabinets::DEBUG
        nil
      end

      # 8 corner points of the bounding box of inst in world space.
      def _world_bounds(inst, world_t)
        bb = inst.definition.bounds
        corners = [
          bb.corner(0), bb.corner(1), bb.corner(2), bb.corner(3),
          bb.corner(4), bb.corner(5), bb.corner(6), bb.corner(7)
        ]
        corners.map { |pt| pt.transform(world_t) }
      rescue
        nil
      end

      # Trigger DC re-evaluation on the item's parent cabinet.
      def _redraw_item_dc(item_inst)
        return unless defined?($dc_observers)
        $dc_observers.get_latest.redraw_with_undo(item_inst) rescue nil
      end

    end # class OpenCloseTool

    # =========================================================================
    # Animation
    # =========================================================================

    class OpenCloseAnimation

      # anim_data: Array of { inst:, from_t:, to_t: }
      # on_complete: lambda called when the animation finishes
      def initialize(anim_data, on_complete:)
        @data        = anim_data
        @on_complete = on_complete
        @frame       = 0
        @total       = OpenCloseTool::ANIM_FRAMES
      end

      def nextFrame(view)
        @frame += 1
        t = _ease(@frame.to_f / @total)
        @data.each do |d|
          d[:inst].transformation = _interpolate(d[:from_t], d[:to_t], t, d)
        end
        view.invalidate

        if @frame >= @total
          # Snap to exact target
          @data.each { |d| d[:inst].transformation = d[:to_t] }
          view.invalidate
          @on_complete.call
          return false
        end
        true
      end

      def stop
        @data.each { |d| d[:inst].transformation = d[:to_t] }
        @on_complete.call
      end

      private

      # Smooth ease-in-out (cubic)
      def _ease(t)
        t * t * (3 - 2 * t)
      end

      # Interpolate between two Geom::Transformation values at parameter t (0..1).
      # For door data that carries pivot/axis/sign/angle_rad, we re-compute the
      # rotation incrementally to avoid matrix-lerp squashing.
      # For drawers (pure translation) we lerp the origin directly.
      # Interpolate between closed (from_t) and open (to_t) at parameter t (0..1).
      #
      # For door data (d has :pivot, :axis, :sign, :angle_rad, :world_closed, :parent_t):
      #   We re-derive the rotation at fraction t using the original pivot and axis,
      #   then convert from world space back to parent space. This avoids ALL matrix
      #   lerp squashing because we never interpolate the rotation matrix elements.
      #
      # For drawer data (pure translation, no :pivot key):
      #   Plain matrix lerp on the 16 elements is safe — translation lerp has no squash.
      def _interpolate(from_t, to_t, t, d = nil)
        if d && d[:bifold]
          # Bi-fold compound rotation: swing with RWD + fold at moving junction.
          frac = d[:closing] ? 1.0 - t : t
          # Step 1: RWD swing rotation
          swing_angle = d[:swing_sign] * d[:angle_rad] * frac
          r_swing = Geom::Transformation.rotation(d[:swing_pivot], d[:axis], swing_angle)
          # Step 2: Junction moves with RWD
          junction_moved = d[:fold_junction_closed].transform(r_swing)
          # Step 3: Fold rotation at the moved junction
          fold_angle = d[:fold_sign] * d[:angle_rad] * frac
          r_fold = Geom::Transformation.rotation(junction_moved, d[:axis], fold_angle)
          # Combined: fold * swing * world_closed → parent space
          combined = r_fold * r_swing * d[:world_closed]
          d[:parent_t].inverse * combined
        elsif d && d[:pivot] && d[:axis] && d[:angle_rad] && d[:world_closed] && d[:parent_t]
          # For closing: reverse the fraction so we animate open → closed.
          # sign and shift_vec are always the OPENING direction.
          frac = d[:closing] ? 1.0 - t : t
          partial_angle = d[:sign] * d[:angle_rad] * frac
          r_world = Geom::Transformation.rotation(d[:pivot], d[:axis], partial_angle)
          combined = r_world * d[:world_closed]
          # Apply partial world-axis shift (panel-thickness translation)
          if d[:shift_vec]
            sv = d[:shift_vec]
            partial_shift = Geom::Transformation.translation(
              Geom::Vector3d.new(sv.x * frac, sv.y * frac, sv.z * frac)
            )
            combined = partial_shift * combined
          end
          d[:parent_t].inverse * combined
        else
          m_from = from_t.to_a
          m_to   = to_t.to_a
          m_lerp = m_from.each_with_index.map { |v, i| _lerp(v, m_to[i], t) }
          Geom::Transformation.new(m_lerp)
        end
      end

      def _lerp(a, b, t)
        a + (b - a) * t
      end

    end # class OpenCloseAnimation

  end # module UI
end # module MLCabinets
