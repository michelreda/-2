# ML Cabinets — Swap Door Opening Tool
#
# Activates an interactive tool: click a single door to flip its
# opening direction. The tool extracts the cabinet config, swaps the
# item type, and rebuilds the cabinet via CabinetDC.update_cabinet —
# the same path used by the Edit Cabinet dialog.
#
# Swap rules:
#   door-hinge-right  ↔  door-hinge-left  (default / "door")
#   door-hinge-top    ↔  door-hinge-bottom
#
# Double-doors are not swappable and are ignored.

require 'sketchup.rb'

module MLCabinets
  module UI

    class SwapDoorTool

      DA          = 'dynamic_attributes'.freeze unless defined?(DA)
      CURSOR_HAND = 671 unless defined?(CURSOR_HAND)

      # Swap map: config item type → swapped config item type
      SWAP_MAP = {
        'door-hinge-right'  => 'door-hinge-left',
        'door-hinge-left'   => 'door-hinge-right',
        'door'              => 'door-hinge-right',   # bare 'door' = hinge-left
        'door-hinge-top'    => 'door-hinge-bottom',
        'door-hinge-bottom' => 'door-hinge-top',
      }.freeze unless defined?(SWAP_MAP)

      # -----------------------------------------------------------------------
      # Tool lifecycle
      # -----------------------------------------------------------------------

      def initialize
        @hover_bounds = nil
        @cursor_id    = _load_cursor
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
        'Click a door to swap its hinge direction (left↔right, top↔bottom).'
      end

      # -----------------------------------------------------------------------
      # Mouse move — highlight hovered door
      # -----------------------------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        result = _find_door(ph)
        @hover_bounds = result ? _world_bounds(result[:leaf_inst], result[:world_t]) : nil
        view.invalidate
      end

      # -----------------------------------------------------------------------
      # Click — swap door direction via full cabinet rebuild
      # -----------------------------------------------------------------------

      def onLButtonDown(_flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        result = _find_door(ph)
        return unless result

        cabinet_inst = result[:cabinet_inst]
        group_idx    = result[:group_idx]
        item_idx     = result[:item_idx]
        old_type     = result[:door_type]

        new_type = SWAP_MAP[old_type]
        unless new_type
          puts "[SwapDoorTool] Unsupported door type '#{old_type}' — cannot swap." if MLCabinets::DEBUG
          return
        end

        # Extract the stored config from the cabinet
        config = CabinetDC.extract_config(cabinet_inst)
        unless config
          puts '[SwapDoorTool] Could not extract cabinet config.' if MLCabinets::DEBUG
          return
        end

        # Locate the item in the config and swap its type
        groups = config[:groups]
        unless groups && groups[group_idx] && groups[group_idx][:items] && groups[group_idx][:items][item_idx]
          puts "[SwapDoorTool] Config item not found at group #{group_idx}, item #{item_idx}." if MLCabinets::DEBUG
          return
        end

        groups[group_idx][:items][item_idx][:type] = new_type

        # Rebuild the cabinet with the updated config
        CabinetDC.update_cabinet(cabinet_inst, config)

        @hover_bounds = nil
        view.invalidate
      end

      # -----------------------------------------------------------------------
      # Draw — bounding-box hover highlight
      # -----------------------------------------------------------------------

      def draw(view)
        return unless @hover_bounds && @hover_bounds.size == 8

        pts = @hover_bounds
        edges = [
          [0,1],[1,2],[2,3],[3,0],
          [4,5],[5,6],[6,7],[7,4],
          [0,4],[1,5],[2,6],[3,7]
        ]
        view.drawing_color = Sketchup::Color.new(255, 165, 0, 200)
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

      def _load_cursor
        path = File.join(MLCabinets::PLUGIN_DIR, 'icons', 'swap_door_cursor.png')
        if File.exist?(path)
          begin
            @cursor = ::UI.create_cursor(path, 0, 0)
            @cursor
          rescue => e
            warn "[MLCabinets::UI::SwapDoorTool] Failed to create cursor: #{e.message}"
            CURSOR_HAND
          end
        else
          CURSOR_HAND
        end
      end

      # Walk the pick path looking for a DoorLeaf instance whose parent
      # Item has i_type == 'door' and is NOT a double-door. Also locates
      # the cabinet root and determines group/item indices for config lookup.
      #
      # Corner doors (L-shaped cabinets) are direct children of the cabinet
      # definition with 'ml_cabinets/corner_door' marker attributes. For
      # these, the group/item indices are resolved by scanning config[:groups]
      # for the first door item.
      #
      # Returns a hash or nil:
      #   cabinet_inst: the root Cabinet ComponentInstance
      #   leaf_inst:    the DoorLeaf instance (for hover highlight)
      #   world_t:      world-space transform of the leaf
      #   door_type:    config-level type string (e.g. 'door-hinge-right')
      #   group_idx:    0-based index into config[:groups]
      #   item_idx:     0-based index into config[:groups][g][:items]
      def _find_door(ph)
        count = ph.count
        return nil if count == 0

        best_path = nil
        (count - 1).downto(0) do |pick_idx|
          p = ph.path_at(pick_idx)
          best_path = p if p && p.length > (best_path&.length || 0)
        end
        return nil unless best_path

        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)

          # ── Corner door detection (direct child of cabinet, no Item/Group) ──
          # Corner doors use the raw panel preset definition (not a DoorLeaf
          # wrapper), so check the marker attribute before the name filter.
          corner_tag = entity.get_attribute('ml_cabinets', 'corner_door').to_s
          if !corner_tag.empty?
            # Find the parent cabinet
            cabinet_inst = nil
            (idx - 1).downto(0) do |ai|
              anc = best_path[ai]
              next unless anc.is_a?(Sketchup::ComponentInstance)
              if CabinetDC.cabinet_instance?(anc)
                cabinet_inst = anc
                break
              end
            end
            next unless cabinet_inst

            door_sub  = entity.get_attribute(DA, 'door_sub').to_s
            door_type = door_sub.empty? ? 'door' : door_sub
            next unless SWAP_MAP.key?(door_type)

            # Find the first door item in config to determine group/item indices
            config = CabinetDC.extract_config(cabinet_inst)
            g_idx, i_idx = _find_first_door_indices(config)
            next unless g_idx && i_idx

            leaf_world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
              e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
            } * entity.transformation

            return {
              cabinet_inst: cabinet_inst,
              leaf_inst:    entity,
              world_t:      leaf_world_t,
              door_type:    door_type,
              group_idx:    g_idx,
              item_idx:     i_idx,
            }
          end

          # ── Standard door detection (DoorLeaf → Item → Group → Cabinet) ──
          next unless entity.definition.name.start_with?('DoorLeaf')
          # Walk backwards to find the parent Item, Group, and Cabinet
          item_inst    = nil
          group_inst   = nil
          cabinet_inst = nil
          (idx - 1).downto(0) do |ai|
            anc = best_path[ai]
            next unless anc.is_a?(Sketchup::ComponentInstance)
            if item_inst.nil? && anc.get_attribute(DA, 'i_type').to_s == 'door'
              item_inst = anc
            elsif group_inst.nil? && anc.definition.get_attribute(DA, 'id').to_s.start_with?('g')
              group_inst = anc
            elsif cabinet_inst.nil? && CabinetDC.cabinet_instance?(anc)
              cabinet_inst = anc
            end
          end
          next unless item_inst && group_inst && cabinet_inst

          door_sub = item_inst.get_attribute(DA, 'door_sub').to_s

          # Skip double-doors — they have no single hinge to swap
          next if door_sub == 'double-door'

          # Map DA door_sub back to config-level type string
          door_type = door_sub.empty? ? 'door' : door_sub
          next unless SWAP_MAP.key?(door_type)

          # Derive 0-based group and item indices from DA 'id' attributes
          group_id = group_inst.definition.get_attribute(DA, 'id').to_s  # e.g. "g1"
          item_id  = item_inst.definition.get_attribute(DA, 'id').to_s   # e.g. "i1"
          g_idx = group_id.delete_prefix('g').to_i - 1
          i_idx = item_id.delete_prefix('i').to_i - 1

          next if g_idx < 0 || i_idx < 0

          # Compute world transform of the leaf for hover highlight
          leaf_world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
            e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
          } * entity.transformation

          return {
            cabinet_inst: cabinet_inst,
            leaf_inst:    entity,
            world_t:      leaf_world_t,
            door_type:    door_type,
            group_idx:    g_idx,
            item_idx:     i_idx,
          }
        end
        nil
      end

      # Scan config[:groups] for the first item whose :type is a door type.
      # Returns [group_idx, item_idx] (0-based) or [nil, nil].
      DOOR_TYPES = %w[door door-hinge-right door-hinge-left door-hinge-top door-hinge-bottom double-door].freeze unless defined?(DOOR_TYPES)

      def _find_first_door_indices(config)
        return [nil, nil] unless config.is_a?(Hash) && config[:groups].is_a?(Array)

        config[:groups].each_with_index do |grp, gi|
          next unless grp[:items].is_a?(Array)
          grp[:items].each_with_index do |item, ii|
            return [gi, ii] if DOOR_TYPES.include?(item[:type].to_s)
          end
        end
        [nil, nil]
      end

      # Compute 8-point world-space bounding box for hover highlight.
      def _world_bounds(inst, world_t)
        bb = inst.definition.bounds
        corners = (0..7).map { |i| bb.corner(i) }
        corners.map { |pt| pt.transform(world_t) }
      rescue
        nil
      end

    end # class SwapDoorTool
  end # module UI
end # module MLCabinets
