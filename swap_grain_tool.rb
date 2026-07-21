# ML Cabinets — Swap Grain Direction Tool
#
# Activates an interactive tool that lets the user click any door, drawer face,
# or panel in the scene to toggle its material grain direction between vertical
# and horizontal. The tool stays active so multiple items can be updated in a
# single activation.
#
# Supported click targets:
#   DoorLeaf / DoorLeaf*   — door panel inside a cabinet Item (i_type = 'door')
#   DrawerFace             — drawer face panel inside a cabinet Item (i_type = 'drwr')
#   PanelFace              — decorative panel inside a cabinet Item (i_type = 'panl')
#   End Panel              — standalone end panel placed by EndPanelTool
#
# Grain persistence:
#   For cabinet items the grain is stored as :material_grain on the item in
#   config[:groups][g][:items][i]. If no per-item material override exists yet,
#   the cabinet-level category material ID is copied to :material_id so the
#   grain attribute takes effect. The cabinet is then rebuilt via
#   CabinetDC.update_cabinet (same path as the Edit dialog).
#
#   For standalone end panels the material is re-resolved with the toggled grain
#   and re-applied in-place using MaterialHelper.apply — no full rebuild needed.

require 'sketchup.rb'

module MLCabinets
  module UI

    class SwapGrainTool

      DA          = 'dynamic_attributes'.freeze unless defined?(DA)
      CURSOR_HAND = 671 unless defined?(CURSOR_HAND)

      # Wrapper component name prefixes that contain the painted panel face.
      FACE_WRAPPER_PREFIXES = %w[DoorLeaf DrawerFace PanelFace BlindFacePanel].freeze

      # Mapping from i_type DA value → config materials category key.
      ITEM_TYPE_TO_CATEGORY = {
        'door' => :door,
        'drwr' => :drawer,
        'fdrw' => :drawer,
        'panl' => :panel,
      }.freeze unless defined?(ITEM_TYPE_TO_CATEGORY)

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
        Sketchup.status_text =
          'Click a door, drawer, panel, or blind face to swap grain direction. Press Esc to exit.'
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

      # -----------------------------------------------------------------------
      # Keyboard — ESC exits the tool
      # -----------------------------------------------------------------------

      def onKeyDown(key, _repeat, _flags, _view)
        if key == 27
          Sketchup.active_model.select_tool(nil)
          return true
        end
        false
      end

      # -----------------------------------------------------------------------
      # Mouse move — hover highlight
      # -----------------------------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        result = _find_target(ph)
        new_bounds = result ? _world_bounds(result[:target_inst], result[:world_t]) : nil
        if new_bounds != @hover_bounds
          @hover_bounds = new_bounds
          view.invalidate
        end
      end

      # -----------------------------------------------------------------------
      # Click — swap grain direction
      # -----------------------------------------------------------------------

      def onLButtonDown(_flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        result = _find_target(ph)
        return unless result

        model = Sketchup.active_model

        if result[:end_panel]
          _swap_end_panel_grain(model, result[:target_inst])
        elsif result[:blind_face_panel]
          _swap_blind_face_grain(model, result[:cabinet_inst])
        else
          _swap_cabinet_item_grain(model, result)
        end

        @hover_bounds = nil
        view.invalidate
      end

      # -----------------------------------------------------------------------
      # Draw — bounding-box hover highlight (cyan/blue to distinguish from
      # the orange used by SwapDoorTool and EndPanelTool)
      # -----------------------------------------------------------------------

      def draw(view)
        return unless @hover_bounds && @hover_bounds.size == 8

        pts = @hover_bounds
        edges = [
          [0, 1], [1, 2], [2, 3], [3, 0],
          [4, 5], [5, 6], [6, 7], [7, 4],
          [0, 4], [1, 5], [2, 6], [3, 7],
        ]
        view.drawing_color = Sketchup::Color.new(0, 200, 255, 220)
        view.line_width    = 2
        view.line_stipple  = ''
        edges.each { |a, b| view.draw(GL_LINES, pts[a], pts[b]) }
      end

      # -----------------------------------------------------------------------
      # Private helpers
      # -----------------------------------------------------------------------
      private

      def update_cursor
        ::UI.set_cursor(@cursor_id)
      end

      def _load_cursor
        path = File.join(MLCabinets::PLUGIN_DIR, 'icons', 'grain_direction_cursor.png')
        if File.exist?(path)
          begin
            ::UI.create_cursor(path, 0, 0)
          rescue => e
            warn "[MLCabinets::SwapGrainTool] Failed to create cursor: #{e.message}"
            CURSOR_HAND
          end
        else
          CURSOR_HAND
        end
      end

      # Walk the pick-helper paths to find a grain-swappable component.
      #
      # Returns a hash describing the target or nil.
      # Hash keys:
      #   :end_panel   — true if a standalone end panel, false for cabinet items
      #   :target_inst — the wrapper ComponentInstance (DoorLeaf / DrawerFace /
      #                  PanelFace / end panel) used for the hover highlight
      #   :world_t     — world-space transform of :target_inst
      #   (cabinet items only)
      #   :cabinet_inst, :item_inst, :i_type, :group_idx, :item_idx
      def _find_target(ph)
        count = ph.count
        return nil if count == 0

        # Prefer the deepest (most specific) pick path.
        best_path = nil
        (count - 1).downto(0) do |pi|
          p = ph.path_at(pi)
          best_path = p if p && p.length > (best_path&.length || 0)
        end
        return nil unless best_path

        # ---- 1. Check for standalone end panels (can appear at any depth) ----
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          next unless entity.get_attribute('ml_cabinets', 'type').to_s == 'end_panel'

          world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
            e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
          } * entity.transformation

          return {
            end_panel:   true,
            target_inst: entity,
            world_t:     world_t,
          }
        end

        # ---- 2. Check for face wrappers (DoorLeaf / DrawerFace / PanelFace) ----
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)

          def_name = entity.definition.name.to_s
          next unless FACE_WRAPPER_PREFIXES.any? { |prefix| def_name.start_with?(prefix) }

          # Walk backwards in the path to find Item, Group, Cabinet ancestors.
          item_inst    = nil
          group_inst   = nil
          cabinet_inst = nil

          (idx - 1).downto(0) do |ai|
            anc = best_path[ai]
            next unless anc.is_a?(Sketchup::ComponentInstance)

            i_type_val = anc.get_attribute(DA, 'i_type').to_s
            if item_inst.nil? && ITEM_TYPE_TO_CATEGORY.key?(i_type_val)
              item_inst = anc
            elsif group_inst.nil? && anc.definition.get_attribute(DA, 'id').to_s =~ /\Ag\d+\z/
              group_inst = anc
            elsif cabinet_inst.nil? && CabinetDC.cabinet_instance?(anc)
              cabinet_inst = anc
            end
          end

          next unless item_inst && group_inst && cabinet_inst

          i_type   = item_inst.get_attribute(DA, 'i_type').to_s
          group_id = group_inst.definition.get_attribute(DA, 'id').to_s   # "g1"
          item_id  = item_inst.definition.get_attribute(DA, 'id').to_s    # "i1"
          g_idx    = group_id.delete_prefix('g').to_i - 1
          i_idx    = item_id.delete_prefix('i').to_i - 1

          next if g_idx < 0 || i_idx < 0

          world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
            e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
          } * entity.transformation

          return {
            end_panel:    false,
            target_inst:  entity,
            world_t:      world_t,
            cabinet_inst: cabinet_inst,
            item_inst:    item_inst,
            i_type:       i_type,
            group_idx:    g_idx,
            item_idx:     i_idx,
          }
        end

        # ---- 3. Blind face panels on blind corner cabinets ----
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          next unless entity.get_attribute('ml_cabinets', 'blind_face_panel')

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

          world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
            e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
          } * entity.transformation

          return {
            end_panel:        false,
            target_inst:      entity,
            world_t:          world_t,
            cabinet_inst:     cabinet_inst,
            item_inst:        nil,
            i_type:           nil,
            group_idx:        nil,
            item_idx:         nil,
            blind_face_panel: true,
          }
        end

        # ---- 4. Fallback: L-shaped corner cabinet doors ----
        # Corner cabinet doors are placed directly on the cabinet definition
        # without a Group > Item wrapper.  They carry ml_cabinets/corner_door
        # and i_type = 'door' DA attributes set by place_corner_doors.
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          next if entity.get_attribute('ml_cabinets', 'corner_door').to_s.empty?
          next unless ITEM_TYPE_TO_CATEGORY.key?(entity.get_attribute(DA, 'i_type').to_s)

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

          world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
            e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
          } * entity.transformation

          return {
            end_panel:    false,
            target_inst:  entity,
            world_t:      world_t,
            cabinet_inst: cabinet_inst,
            item_inst:    nil,
            i_type:       entity.get_attribute(DA, 'i_type').to_s,
            group_idx:    nil,
            item_idx:     nil,
            corner_door:  true,
          }
        end

        nil
      end

      # -----------------------------------------------------------------------
      # Swap grain for a cabinet item (door / drawer / panel).
      # Extracts config, toggles :material_grain on the item, rebuilds cabinet.
      # -----------------------------------------------------------------------
      def _swap_cabinet_item_grain(model, result)
        cabinet_inst = result[:cabinet_inst]
        group_idx    = result[:group_idx]
        item_idx     = result[:item_idx]
        i_type       = result[:i_type]

        # Corner cabinet doors have no per-item config index — update the
        # cabinet-level door material grain and rebuild.
        if result[:corner_door]
          _swap_corner_door_grain(model, cabinet_inst, i_type)
          return
        end

        config = CabinetDC.extract_config(cabinet_inst)
        unless config
          Sketchup.status_text = 'Could not read cabinet config — skipping.'
          return
        end

        groups = config[:groups]
        unless groups.is_a?(Array) &&
               groups[group_idx].is_a?(Hash) &&
               groups[group_idx][:items].is_a?(Array) &&
               groups[group_idx][:items][item_idx].is_a?(Hash)
          Sketchup.status_text = 'Cabinet item not found in config — skipping.'
          return
        end

        item     = groups[group_idx][:items][item_idx]
        cat_key  = ITEM_TYPE_TO_CATEGORY[i_type]

        unless cat_key
          Sketchup.status_text = 'Selected item does not support grain direction.'
          return
        end

        # Determine current effective grain.
        # Per-item :material_grain takes precedence; fall back to category grain.
        per_grain  = item[:material_grain].to_s
        cat_mat    = (config[:materials].is_a?(Hash) ? config[:materials][cat_key] : nil) || {}
        cat_grain  = cat_mat[:grain].to_s
        current    = per_grain.empty? ? (cat_grain.empty? ? 'vertical' : cat_grain) : per_grain
        new_grain  = (current == 'vertical') ? 'horizontal' : 'vertical'

        # Validate that a material is assigned (either per-item or category-level)
        # so the grain direction has a texture to apply to.
        has_mat = (item[:material_id] && !item[:material_id].to_s.strip.empty?) ||
                  !cat_mat[:id].to_s.strip.empty?
        unless has_mat
          Sketchup.status_text =
            'No material assigned to this item — assign a wood/texture material first.'
          return
        end

        item[:material_grain] = new_grain

        CabinetDC.update_cabinet(cabinet_inst, config)

        Sketchup.status_text =
          "Grain direction set to #{new_grain}. Click another item or press Esc to exit."
      rescue => e
        puts "MLCabinets: SwapGrainTool._swap_cabinet_item_grain error — #{e.message}" if MLCabinets::DEBUG
        Sketchup.status_text = "Grain swap failed: #{e.message}"
      end

      # -----------------------------------------------------------------------
      # Swap grain for an L-shaped corner cabinet door.
      # There is no per-item material config for corner doors, so the grain
      # is toggled at the cabinet-level door material category.
      # -----------------------------------------------------------------------
      def _swap_corner_door_grain(model, cabinet_inst, _i_type)
        config = CabinetDC.extract_config(cabinet_inst)
        unless config
          Sketchup.status_text = 'Could not read cabinet config — skipping.'
          return
        end

        mat_config = (config[:materials].is_a?(Hash) ? config[:materials][:door] : nil) || {}
        current_grain = mat_config[:grain].to_s
        current_grain = 'vertical' if current_grain.empty?
        new_grain = (current_grain == 'vertical') ? 'horizontal' : 'vertical'

        if mat_config[:id].to_s.strip.empty?
          Sketchup.status_text =
            'No material assigned to cabinet doors — assign a wood/texture material first.'
          return
        end

        config[:materials] ||= {}
        config[:materials][:door] ||= {}
        config[:materials][:door][:grain] = new_grain

        CabinetDC.update_cabinet(cabinet_inst, config)

        Sketchup.status_text =
          "Corner door grain direction set to #{new_grain}. Click another item or press Esc to exit."
      rescue => e
        puts "MLCabinets: SwapGrainTool._swap_corner_door_grain error — #{e.message}" if MLCabinets::DEBUG
        Sketchup.status_text = "Grain swap failed: #{e.message}"
      end

      # -----------------------------------------------------------------------
      # Swap grain for a standalone end panel.
      # Re-resolves the material with the opposite grain and re-applies it
      # in-place — no full cabinet rebuild required.
      # -----------------------------------------------------------------------
      def _swap_end_panel_grain(model, ep_inst)
        mat = ep_inst.material

        unless mat&.texture
          Sketchup.status_text =
            'No wood texture on this panel — assign a textured material first.'
          return
        end

        current_grain = mat.get_attribute('ml_cabinets', 'grain').to_s
        current_grain = 'vertical' if current_grain.empty?
        new_grain     = (current_grain == 'vertical') ? 'horizontal' : 'vertical'

        # Derive the preset name from the material name.
        # Library material names follow the pattern: MLC_<preset_name>_<grain>
        mat_name = mat.name.to_s
        preset_name = mat_name
                        .delete_prefix('MLC_')
                        .delete_suffix("_#{current_grain}")

        if preset_name.empty?
          Sketchup.status_text = 'Cannot determine material preset — skipping.'
          return
        end

        new_mat = MaterialHelper.resolve(model, preset_name, new_grain)
        unless new_mat
          Sketchup.status_text = "Could not resolve material '#{preset_name}' — skipping."
          return
        end

        model.start_operation('Swap Grain Direction', true)
        begin
          MaterialHelper.apply(ep_inst, new_mat)
          model.commit_operation
        rescue => e
          model.abort_operation
          raise
        end

        Sketchup.status_text =
          "Grain direction set to #{new_grain}. Click another item or press Esc to exit."
      rescue => e
        puts "MLCabinets: SwapGrainTool._swap_end_panel_grain error — #{e.message}" if MLCabinets::DEBUG
        Sketchup.status_text = "Grain swap failed: #{e.message}"
      end

      # -----------------------------------------------------------------------
      # Swap grain for the blind face panel on a blind corner cabinet.
      # Toggles :blind_face_grain in the config and rebuilds the cabinet.
      # -----------------------------------------------------------------------
      def _swap_blind_face_grain(model, cabinet_inst)
        config = CabinetDC.extract_config(cabinet_inst)
        unless config
          Sketchup.status_text = 'Could not read cabinet config — skipping.'
          return
        end

        door_mat = (config[:materials].is_a?(Hash) ? config[:materials][:door] : nil) || {}
        if door_mat[:id].to_s.strip.empty?
          Sketchup.status_text =
            'No material assigned to cabinet doors — assign a wood/texture material first.'
          return
        end

        current_grain = config[:blind_face_grain].to_s
        current_grain = (door_mat[:grain] || 'vertical').to_s if current_grain.empty?
        new_grain = (current_grain == 'vertical') ? 'horizontal' : 'vertical'

        config[:blind_face_grain] = new_grain

        CabinetDC.update_cabinet(cabinet_inst, config)

        Sketchup.status_text =
          "Blind face grain set to #{new_grain}. Click another item or press Esc to exit."
      rescue => e
        puts "MLCabinets: SwapGrainTool._swap_blind_face_grain error — #{e.message}" if MLCabinets::DEBUG
        Sketchup.status_text = "Grain swap failed: #{e.message}"
      end

      # Compute the 8 world-space corners of an instance's bounding box.
      def _world_bounds(inst, world_t)
        bb = inst.definition.bounds
        (0..7).map { |i| bb.corner(i).transform(world_t) }
      rescue
        nil
      end

    end # class SwapGrainTool
  end # module UI
end # module MLCabinets
