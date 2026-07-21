# ML Cabinets — Apply Preset Tool
#
# Activated from the Library dialog when the user clicks a door-panel,
# door-handle, drawer-front, drawer-handle, panel, leg, material, or appliance preset card. The tool then
# lets the user click cabinets (or individual items with Alt/Option, where supported) in the scene
# to apply the chosen preset. The tool stays active so multiple cabinets
# can be updated in one go; pressing Escape or picking a new preset
# deactivates it.
#
# Two interaction modes (toggled by the Alt/Option key):
#
#   Normal  — click the cabinet body → updates the cabinet-level preset
#             that affects ALL doors/drawers of that kind.
#
#   Alt/Option — click a single door or drawer → overrides only that item's
#             per-item preset (shape_id / handle_id in the stored config).
#
# Preset kinds:
#   :door_panel     → doors.preset_id          / item[:shape_id]  (door items)
#   :door_handle    → doors.handle_preset_id   / item[:handle_id] (door items)
#   :drawer_front   → drawers.preset_id        / item[:shape_id]  (drwr items)
#   :drawer_handle  → drawers.handle_preset_id / item[:handle_id] (drwr items)
#   :leg            → toe_kick.create_legs + toe_kick.legs_preset (cabinet level)
#   :material       → materials[target] or item-level material override
#   :appliance      → item[:appliance_id] (appliance items only)

require 'sketchup.rb'
require 'json'

module MLCabinets
  module UI

    class ApplyPresetTool

      DA          = 'dynamic_attributes'.freeze unless defined?(DA)
      CURSOR_HAND = 671 unless defined?(CURSOR_HAND)

      # VK_MENU (Alt key) on Windows; SketchUp maps Option to the same modifier on macOS.
      VK_ALT = 18 unless defined?(VK_ALT)

      # Maps kind symbol → which DA i_type string to look for in alt mode
      TARGET_TYPE = {
        door_panel:    'door',
        door_handle:   'door',
        drawer_front:  'drwr',
        drawer_handle: 'drwr',
        panel:         'panl',
      }.freeze unless defined?(TARGET_TYPE)

      MATERIAL_TARGET_ITEM_TYPES = {
        door:   %w[door],
        drawer: %w[drwr fdrw],
        panel:  %w[panl],
        handle: %w[door drwr fdrw],
      }.freeze unless defined?(MATERIAL_TARGET_ITEM_TYPES)

      MATERIAL_TARGET_LABEL = {
        carcass: 'Carcass',
        door:    'Door',
        drawer:  'Drawer',
        panel:   'Panel',
        handle:  'Handle',
      }.freeze unless defined?(MATERIAL_TARGET_LABEL)

      # Human-readable names used in status / undo strings
      KIND_LABEL = {
        door_panel:    'Door Panel',
        door_handle:   'Door Handle',
        drawer_front:  'Drawer Front',
        drawer_handle: 'Drawer Handle',
        panel:         'Panel',
        leg:           'Leg',
        material:      'Material',
        appliance:     'Appliance',
      }.freeze unless defined?(KIND_LABEL)

      # -----------------------------------------------------------------------
      # Lifecycle
      # -----------------------------------------------------------------------

      def initialize(preset_id, kind, material_target: nil, material_grain: nil)
        @preset_id    = preset_id
        @kind         = kind.to_sym
        @material_target = material_target.to_s
        @material_grain  = material_grain.to_s
        @alt_down     = false
        @hover_bounds = nil
        @cursor_id    = _load_cursor
      end

      def activate
        update_cursor
        Sketchup.active_model.active_view.invalidate
        update_status
      end

      def deactivate(view)
        @hover_bounds = nil
        view.invalidate
      end

      def resume(view)
        update_cursor
        view.invalidate
        update_status
      end

      def onSetCursor
        update_cursor
      end

      def getExtents
        Geom::BoundingBox.new
      end

      # -----------------------------------------------------------------------
      # Keyboard — track Alt/Option
      # -----------------------------------------------------------------------

      def onKeyDown(key, _repeat, _flags, view)
        if key == VK_ALT && _item_mode_supported?
          @alt_down = true
          update_status
          view.invalidate
        end
        false
      end

      def onKeyUp(key, _repeat, _flags, view)
        if key == VK_ALT && _item_mode_supported?
          @alt_down = false
          update_status
          view.invalidate
        end
        false
      end

      # -----------------------------------------------------------------------
      # Mouse move — hover highlight
      # -----------------------------------------------------------------------

      def onMouseMove(flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        @hover_bounds = if _item_only_mode?
          result = _find_target_item(ph)
          result ? _world_bounds(result[:item_inst], result[:item_world_t]) : nil
        elsif _item_modifier_down?(flags) && _item_mode_supported?
          result = _find_target_item(ph)
          result ? _world_bounds(result[:item_inst], result[:item_world_t]) : nil
        else
          result = _find_cabinet(ph)
          if result
            _world_bounds(result[:cabinet_inst], result[:cabinet_world_t])
          elsif @kind == :panel
            ep = _find_end_panel(ph)
            ep ? _world_bounds(ep[:end_panel_inst], ep[:end_panel_inst].transformation) : nil
          end
        end
        view.invalidate
      end

      # -----------------------------------------------------------------------
      # Click — apply preset
      # -----------------------------------------------------------------------

      def onLButtonDown(flags, x, y, view)
        ph = view.pick_helper(x, y, 10)

        if _item_only_mode?
          _apply_to_item(ph, view)
        elsif _item_modifier_down?(flags) && _item_mode_supported?
          _apply_to_item(ph, view)
        elsif @kind == :panel && (ep = _find_end_panel(ph))
          _apply_to_end_panel(ep, view)
        else
          _apply_to_cabinet(ph, view)
        end
      end

      # -----------------------------------------------------------------------
      # Draw — bounding-box highlight
      # -----------------------------------------------------------------------

      def draw(view)
        return unless @hover_bounds && @hover_bounds.size == 8

        pts = @hover_bounds
        edges = [
          [0,1],[1,2],[2,3],[3,0],
          [4,5],[5,6],[6,7],[7,4],
          [0,4],[1,5],[2,6],[3,7]
        ]
        view.drawing_color = Sketchup::Color.new(30, 144, 255, 220)
        view.line_width    = 2
        view.line_stipple  = ''
        edges.each { |a, b| view.draw(GL_LINES, pts[a], pts[b]) }
      end

      # -----------------------------------------------------------------------
      # Private
      # -----------------------------------------------------------------------
      private

      def update_cursor
        ::UI.set_cursor(@cursor_id)
      end

      def _load_cursor
        path = File.join(MLCabinets::PLUGIN_DIR, 'icons', 'preset_cursor.png')
        if File.exist?(path)
          begin
            ::UI.create_cursor(path, 0, 0)
          rescue => e
            warn "[MLCabinets::UI::ApplyPresetTool] Failed to create cursor: #{e.message}"
            CURSOR_HAND
          end
        else
          CURSOR_HAND
        end
      end

      def update_status
        label = _tool_label
        if _item_only_mode?
          Sketchup.set_status_text(
            "Click an appliance item in a cabinet to replace it with the selected #{label}. Esc to cancel.",
            SB_PROMPT
          )
        elsif @alt_down && _item_mode_supported?
          target = _status_item_target_label
          Sketchup.set_status_text(
            "Click a #{target} to override it with the selected #{label}. " \
            "Release Alt/Option to switch to cabinet-level mode. Esc to cancel.",
            SB_PROMPT
          )
        elsif @kind == :panel
          Sketchup.set_status_text(
            "Click a cabinet or end panel to apply the #{label}. " \
            "Hold Alt/Option to override a single item. Esc to cancel.",
            SB_PROMPT
          )
        elsif @kind == :leg
          Sketchup.set_status_text(
            "Click a cabinet to enable legs and apply the selected #{label}. Esc to cancel.",
            SB_PROMPT
          )
        elsif @kind == :material
          phrase = case _material_target_sym
                   when :door then 'all doors'
                   when :drawer then 'all drawers'
                   when :panel then 'all panels'
                   when :handle then 'all handles'
                   else 'the carcass'
                   end
          suffix = _item_mode_supported? ?
            " Hold Alt/Option to override a single #{_status_item_target_label}. Esc to cancel." :
            ' Esc to cancel.'
          Sketchup.set_status_text(
            "Click a cabinet to apply the selected #{label} to #{phrase}.#{suffix}",
            SB_PROMPT
          )
        else
          Sketchup.set_status_text(
            "Click a cabinet to apply the #{label} to all items. " \
            "Hold Alt/Option to override a single item. Esc to cancel.",
            SB_PROMPT
          )
        end
      end

      def _item_modifier_down?(flags)
        @alt_down || ((flags.to_i & ALT_MODIFIER_MASK) != 0)
      end

      def _tool_label
        return "#{_material_target_label} Material" if @kind == :material
        KIND_LABEL[@kind] || @kind.to_s
      end

      def _material_target_sym
        target = @material_target.to_s.strip.downcase.to_sym
        MATERIAL_TARGET_LABEL.key?(target) ? target : :carcass
      end

      def _material_target_label
        MATERIAL_TARGET_LABEL[_material_target_sym] || 'Material'
      end

      def _status_item_target_label
        return 'appliance item' if _item_only_mode?

        return case _material_target_sym
               when :door then 'door'
               when :drawer then 'drawer'
               when :panel then 'panel'
               when :handle then 'door or drawer item'
               else 'item'
               end if @kind == :material

        case TARGET_TYPE[@kind]
        when 'door' then 'door'
        when 'panl' then 'panel'
        else 'drawer'
        end
      end

      def _target_item_types
        return %w[appl] if _item_only_mode?
        return MATERIAL_TARGET_ITEM_TYPES[_material_target_sym] || [] if @kind == :material

        target_itype = TARGET_TYPE[@kind]
        return %w[drwr fdrw] if target_itype == 'drwr'
        target_itype ? [target_itype] : []
      end

      def _selected_material_grain(fallback = 'vertical')
        grain = @material_grain.to_s.strip
        grain.empty? ? fallback : grain
      end

      def _item_mode_supported?
        return false if _item_only_mode?
        return !(_target_item_types.empty?) if @kind == :material
        TARGET_TYPE.key?(@kind)
      end

      def _item_only_mode?
        @kind == :appliance
      end

      # ------------------------------------------------------------------
      # Normal mode: apply preset at the cabinet level
      # ------------------------------------------------------------------

      def _apply_to_cabinet(ph, view)
        result = _find_cabinet(ph)
        unless result
          puts "[ApplyPresetTool] No cabinet under cursor." if MLCabinets::DEBUG
          return
        end

        cabinet_inst = result[:cabinet_inst]
        config = CabinetDC.extract_config(cabinet_inst)
        unless config
          puts "[ApplyPresetTool] Could not extract config." if MLCabinets::DEBUG
          return
        end

        label = _tool_label
        model = Sketchup.active_model
        model.start_operation("Apply #{label}", true)
        begin
          _set_cabinet_preset(config, @preset_id)
          CabinetDC.update_cabinet(cabinet_inst, config)
          model.commit_operation
        rescue => e
          model.abort_operation
          puts "[ApplyPresetTool] cabinet apply error — #{e.message}" if MLCabinets::DEBUG
        end

        @hover_bounds = nil
        view.invalidate
      end

      # ------------------------------------------------------------------
      # Alt/Option mode: apply preset at the item level
      # ------------------------------------------------------------------

      def _apply_to_item(ph, view)
        result = _find_target_item(ph)
        unless result
          puts "[ApplyPresetTool] No target item under cursor." if MLCabinets::DEBUG
          return
        end

        # Corner cabinet doors have no per-item config index — route to
        # cabinet-level apply (same effect as normal mode).
        if result[:corner_door]
          cabinet_inst = result[:cabinet_inst]
          config = CabinetDC.extract_config(cabinet_inst)
          unless config
            puts "[ApplyPresetTool] Could not extract config for corner door." if MLCabinets::DEBUG
            return
          end
          label = _tool_label
          model = Sketchup.active_model
          model.start_operation("Apply #{label}", true)
          begin
            _set_cabinet_preset(config, @preset_id)
            CabinetDC.update_cabinet(cabinet_inst, config)
            model.commit_operation
          rescue => e
            model.abort_operation
            puts "[ApplyPresetTool] corner door apply error — #{e.message}" if MLCabinets::DEBUG
          end
          @hover_bounds = nil
          view.invalidate
          return
        end

        cabinet_inst = result[:cabinet_inst]
        g_idx        = result[:group_idx]
        i_idx        = result[:item_idx]

        config = CabinetDC.extract_config(cabinet_inst)
        unless config
          puts "[ApplyPresetTool] Could not extract config." if MLCabinets::DEBUG
          return
        end

        groups = config[:groups]
        unless groups && groups[g_idx] && groups[g_idx][:items] && groups[g_idx][:items][i_idx]
          puts "[ApplyPresetTool] Item not found at group #{g_idx}, item #{i_idx}." if MLCabinets::DEBUG
          return
        end

        label = _tool_label
        model = Sketchup.active_model
        model.start_operation("Apply #{label} (item)", true)
        begin
          _set_item_preset(groups[g_idx][:items][i_idx], @preset_id)
          CabinetDC.update_cabinet(cabinet_inst, config)
          model.commit_operation
        rescue => e
          model.abort_operation
          puts "[ApplyPresetTool] item apply error — #{e.message}" if MLCabinets::DEBUG
        end

        @hover_bounds = nil
        view.invalidate
      end

      # ------------------------------------------------------------------
      # Config mutation helpers
      # ------------------------------------------------------------------

      def _set_cabinet_preset(config, preset_id)
        case @kind
        when :door_panel
          config[:doors] ||= {}
          config[:doors][:preset_id] = preset_id
        when :door_handle
          config[:doors] ||= {}
          config[:doors][:handle_preset_id] = preset_id
        when :drawer_front
          config[:drawers] ||= {}
          config[:drawers][:preset_id] = preset_id
        when :drawer_handle
          config[:drawers] ||= {}
          config[:drawers][:handle_preset_id] = preset_id
        when :panel
          config[:panels] ||= {}
          config[:panels][:preset_id] = preset_id
        when :leg
          config[:toe_kick] ||= {}
          config[:toe_kick][:create_legs] = true
          config[:toe_kick][:legs_preset] = preset_id
        when :material
          config[:materials] ||= {}
          key = _material_target_sym
          current = config[:materials][key] || {}
          config[:materials][key] = {
            id: preset_id,
            grain: _selected_material_grain(current[:grain].to_s.empty? ? 'vertical' : current[:grain].to_s)
          }
        end
      end

      def _set_item_preset(item, preset_id)
        case @kind
        when :door_panel, :drawer_front, :panel
          item[:shape_id] = preset_id
        when :door_handle, :drawer_handle
          item[:handle_id] = preset_id
        when :material
          case _material_target_sym
          when :door, :drawer, :panel
            item[:material_id] = preset_id
            item[:material_grain] = _selected_material_grain(item[:material_grain].to_s.empty? ? 'vertical' : item[:material_grain].to_s)
          when :handle
            item[:handle_material_id] = preset_id
            item[:handle_material_grain] = _selected_material_grain(item[:handle_material_grain].to_s.empty? ? 'vertical' : item[:handle_material_grain].to_s)
          end
        when :appliance
          item[:appliance_id] = preset_id
        end
      end

      # ------------------------------------------------------------------
      # Pick helpers
      # ------------------------------------------------------------------

      # Returns { cabinet_inst:, cabinet_world_t: } or nil.
      # Finds the outermost ML Cabinets component in the pick path.
      def _find_cabinet(ph)
        best_path = _best_path(ph)
        return nil unless best_path

        t = Geom::Transformation.new
        best_path.each do |entity|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          if CabinetDC.cabinet_instance?(entity)
            return { cabinet_inst: entity, cabinet_world_t: t * entity.transformation }
          end
          t = t * entity.transformation
        end
        nil
      end

      # Returns { cabinet_inst:, item_inst:, item_world_t:, group_idx:, item_idx: } or nil.
      # Finds an item of the correct type (door / drwr) in the pick path.
      def _find_target_item(ph)
        best_path = _best_path(ph)
        return nil unless best_path

        target_itypes = _target_item_types
        return nil if target_itypes.empty?

        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          itype = entity.get_attribute(DA, 'i_type').to_s
          next unless target_itypes.include?(itype)

          # Walk backward to find the parent Group and Cabinet
          group_inst   = nil
          cabinet_inst = nil
          cab_start_t  = Geom::Transformation.new

          (idx - 1).downto(0) do |ai|
            anc = best_path[ai]
            next unless anc.is_a?(Sketchup::ComponentInstance)
            if group_inst.nil? && anc.definition.get_attribute(DA, 'id').to_s.match?(/\Ag\d+\z/)
              group_inst = anc
            elsif cabinet_inst.nil? && CabinetDC.cabinet_instance?(anc)
              cabinet_inst = anc
              # cab_start_t is the transform of all ancestors above the cabinet
              cab_start_t = best_path[0...ai].inject(Geom::Transformation.new) { |acc, e|
                e.is_a?(Sketchup::ComponentInstance) ? acc * e.transformation : acc
              }
            end
          end
          next unless group_inst && cabinet_inst

          group_id = group_inst.definition.get_attribute(DA, 'id').to_s  # e.g. "g1"
          item_id  = entity.definition.get_attribute(DA, 'id').to_s       # e.g. "i2"
          g_idx = group_id.delete_prefix('g').to_i - 1
          i_idx = item_id.delete_prefix('i').to_i - 1
          next if g_idx < 0 || i_idx < 0

          # World transform of the item for hover highlight
          item_world_t = best_path[0...idx].inject(Geom::Transformation.new) { |acc, e|
            e.is_a?(Sketchup::ComponentInstance) ? acc * e.transformation : acc
          } * entity.transformation

          return {
            cabinet_inst: cabinet_inst,
            item_inst:    entity,
            item_world_t: item_world_t,
            group_idx:    g_idx,
            item_idx:     i_idx,
          }
        end

        # --- Fallback: L-shaped corner cabinet doors ---
        # Corner cabinet doors carry ml_cabinets/corner_door and i_type = 'door'
        # but have no Group > Item wrapper hierarchy and no per-item config index.
        # Alt/Option-clicking them falls back to a cabinet-level preset apply.
        best_path.each_with_index do |entity, idx|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          next if entity.get_attribute('ml_cabinets', 'corner_door').to_s.empty?
          next unless target_itypes.include?(entity.get_attribute(DA, 'i_type').to_s)

          cabinet_inst = nil
          (idx - 1).downto(0) do |ai|
            anc = best_path[ai]
            if anc.is_a?(Sketchup::ComponentInstance) && CabinetDC.cabinet_instance?(anc)
              cabinet_inst = anc
              break
            end
          end
          next unless cabinet_inst

          item_world_t = best_path[0...idx].inject(Geom::Transformation.new) { |acc, e|
            e.is_a?(Sketchup::ComponentInstance) ? acc * e.transformation : acc
          } * entity.transformation

          return {
            cabinet_inst: cabinet_inst,
            item_inst:    entity,
            item_world_t: item_world_t,
            group_idx:    nil,
            item_idx:     nil,
            corner_door:  true,
          }
        end
        nil
      end

      # Pick the longest path from the pick helper (deepest entity).
      def _best_path(ph)
        count = ph.count
        return nil if count == 0
        best = nil
        (count - 1).downto(0) do |i|
          p = ph.path_at(i)
          best = p if p && p.length > (best&.length || 0)
        end
        best
      end

      # 8-point world-space bounding box for the hover highlight.
      def _world_bounds(inst, world_t)
        bb = inst.definition.bounds
        (0..7).map { |i| bb.corner(i).transform(world_t) }
      rescue
        nil
      end

      # ------------------------------------------------------------------
      # Find a standalone end panel in the pick path (panel kind only).
      # Returns { end_panel_inst: } or nil.
      # ------------------------------------------------------------------
      def _find_end_panel(ph)
        best_path = _best_path(ph)
        return nil unless best_path

        best_path.each do |entity|
          next unless entity.is_a?(Sketchup::ComponentInstance)
          # Don't descend into cabinets — end panels are standalone.
          break if CabinetDC.cabinet_instance?(entity)
          if entity.get_attribute('ml_cabinets', 'type').to_s == 'end_panel' ||
             entity.name == 'End Panel'
            return { end_panel_inst: entity }
          end
        end
        nil
      end

      # ------------------------------------------------------------------
      # Apply the active panel preset to a standalone end panel.
      #
      # The transformation stored on the instance encodes position +
      # rotation + scale.  We undo the old definition's scale, then
      # re-apply the new definition's scale, using the ep_side attribute
      # to handle the extra local-space translate on right-side panels:
      #
      #   'L' (left / left-wing):
      #     T_new = T_old * Scaling(old_bw/new_bw, 1, old_bd/new_bd)
      #
      #   'R' (right / right-wing):
      #     T_new = T_old * Translation(old_bw,0,0)
      #           * Scaling(old_bw/new_bw, 1, old_bd/new_bd)
      #           * Translation(-new_bw, 0, 0)
      # ------------------------------------------------------------------
      def _apply_to_end_panel(result, view)
        old_inst = result[:end_panel_inst]
        old_defn = old_inst.definition
        old_t    = old_inst.transformation

        lenx    = old_inst.get_attribute(DA, 'lenx').to_f   # depth in inches
        lenz    = old_inst.get_attribute(DA, 'lenz').to_f   # height in inches
        ep_side = old_inst.get_attribute('ml_cabinets', 'ep_side').to_s  # 'L' or 'R'

        if lenx <= 0 || lenz <= 0
          puts "[ApplyPresetTool] End panel has no stored dimensions — cannot replace." if MLCabinets::DEBUG
          return
        end

        model    = Sketchup.active_model
        new_defn = PanelDC.load_definition(model, @preset_id)
        unless new_defn
          puts "[ApplyPresetTool] Could not load panel definition for preset #{@preset_id}." if MLCabinets::DEBUG
          return
        end

        old_bw = old_defn.bounds.width.to_f   # local X extent of old definition
        old_bd = old_defn.bounds.depth.to_f   # local Z extent of old definition
        new_bw = new_defn.bounds.width.to_f
        new_bd = new_defn.bounds.depth.to_f

        return if old_bw <= 0 || old_bd <= 0 || new_bw <= 0 || new_bd <= 0

        ratio_x = old_bw / new_bw
        ratio_d = old_bd / new_bd

        new_t = if ep_side == 'R'
          old_t *
            Geom::Transformation.translation(Geom::Vector3d.new(old_bw, 0, 0)) *
            Geom::Transformation.scaling(ratio_x, 1.0, ratio_d) *
            Geom::Transformation.translation(Geom::Vector3d.new(-new_bw, 0, 0))
        else
          old_t * Geom::Transformation.scaling(ratio_x, 1.0, ratio_d)
        end

        old_mat   = old_inst.material
        old_layer = old_inst.layer
        old_name  = old_inst.name

        model.start_operation('Apply Panel Preset (End Panel)', true)
        begin
          new_inst      = model.active_entities.add_instance(new_defn, new_t)
          new_inst.name = old_name
          new_inst.layer = old_layer if old_layer
          MaterialHelper.apply(new_inst, old_mat) if old_mat
          new_inst.set_attribute(DA,            'lenx',    lenx)
          new_inst.set_attribute(DA,            'lenz',    lenz)
          new_inst.set_attribute('ml_cabinets', 'type',    'end_panel')
          new_inst.set_attribute('ml_cabinets', 'ep_side', ep_side) unless ep_side.empty?

          old_inst.erase!
          model.commit_operation
          CabinetDC.redraw_dc(new_inst)
        rescue => e
          model.abort_operation
          puts "[ApplyPresetTool] end panel apply error — #{e.message}" if MLCabinets::DEBUG
          puts e.backtrace.first(4).join("\n") if MLCabinets::DEBUG
        end

        @hover_bounds = nil
        view.invalidate
      end

    end # class ApplyPresetTool
  end # module UI
end # module MLCabinets
