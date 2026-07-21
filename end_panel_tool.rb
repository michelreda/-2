# ML Cabinets — End Panel Tool
#
# Activates an interactive tool: click a cabinet side panel to place
# a standalone decorative end panel covering that side.
#
# The end panel:
#   - Height = full cabinet height (including toe kick)
#   - Depth  = cabinet depth + 1.8 cm (if overlay is not inset)
#   - Uses the panel face preset (fallback: door → drawer → plain box)
#   - Material from the cabinet's :panel material
#   - Is a standalone component (survives cabinet edits)
#   - Decorative face points outward (away from cabinet)
#
# The tool remains active after each placement so the user can add
# end panels to multiple sides/cabinets without reactivating.

require 'sketchup.rb'

module MLCabinets
  module UI

    class EndPanelTool

      DA          = 'dynamic_attributes'.freeze unless defined?(DA)
      CURSOR_HAND = 671 unless defined?(CURSOR_HAND)
      OVERLAY_EXT_CM = 1.8  # depth extension for non-inset overlay

      SIDE_PANEL_NAMES = ['Left Side Panel', 'Right Side Panel', 'Left Wing Side', 'Right Wing Side'].freeze

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
        'Click a cabinet side panel to add a decorative end panel.'
      end

      # -----------------------------------------------------------------------
      # Mouse move — highlight hovered side panel
      # -----------------------------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        result = _find_side_panel(ph)
        @hover_bounds = result ? _world_bounds(result[:side_inst], result[:world_t]) : nil
        view.invalidate
      end

      # -----------------------------------------------------------------------
      # Click — create end panel adjacent to the clicked side
      # -----------------------------------------------------------------------

      def onLButtonDown(_flags, x, y, view)
        ph = view.pick_helper(x, y, 10)
        result = _find_side_panel(ph)
        return unless result

        cabinet_inst = result[:cabinet_inst]
        side         = result[:side]          # :left or :right
        panel_name   = result[:wing] ? (side == :left ? 'Left Wing Side' : 'Right Wing Side') : (side == :left ? 'Left Side Panel' : 'Right Side Panel')

        model = Sketchup.active_model
        defn  = cabinet_inst.definition

        # Read cabinet DA attributes (stored in inches internally)
        cab_w_in    = defn.get_attribute(DA, 'cab_width').to_f
        cab_h_in    = defn.get_attribute(DA, 'cab_height').to_f
        corner_type = defn.get_attribute('ml_cabinets', 'corner_type')
        cab_full_depth_in = defn.get_attribute(DA, 'cab_depth').to_f
        cab_d_in    = if corner_type == 'l-shaped'
                        defn.get_attribute(DA, 'wing_depth').to_f
                      else
                        cab_full_depth_in
                      end
        t_in        = defn.get_attribute(DA, 'thickness').to_f
        sp_type     = defn.get_attribute(DA, 'ov_type').to_i  # 1=inset, 2=overlay, 3=full

        # End panel depth: cabinet depth + extension for non-inset overlay (in inches)
        ep_depth_in  = cab_d_in + (sp_type != 1 ? OVERLAY_EXT_CM / 2.54 : 0.0)
        ep_height_in = cab_h_in

        # Determine panel preset (fallback chain: panel → door → drawer → plain box)
        config = CabinetDC.extract_config(cabinet_inst)
        preset_id = _resolve_preset_id(config)

        # Determine panel material
        mat_entry = _resolve_panel_material(config)
        panel_mat = mat_entry ? MaterialHelper.resolve(model, mat_entry[:id], mat_entry[:grain] || 'vertical') : nil

        model.start_operation('Add End Panel', true)
        begin
          ep_inst = _create_end_panel(model, preset_id, ep_depth_in, ep_height_in, t_in, panel_mat)

          # Assign to the Panels layer if the ML Cabinets layer structure exists
          layers = LayerManager.ensure_ml_layers(model)
          ep_inst.layer = layers[:panels] if layers && layers[:panels]

          # Position the end panel flush against the cabinet exterior
          cab_t = cabinet_inst.transformation
          scale_x = ep_depth_in / ep_inst.definition.bounds.width
          scale_z = ep_height_in / ep_inst.definition.bounds.depth
          sca_t = Geom::Transformation.scaling(scale_x, 1, scale_z)

          if panel_name == 'Left Wing Side'
            # L-shaped corner: outer face is at Y = total cabinet depth, panel runs in +X.
            # No rotation needed — end panel local X (depth) aligns with cabinet +X,
            # local Y (thickness) extends outward in cabinet +Y.
            local_origin = Geom::Point3d.new(0, cab_full_depth_in, 0)
            ep_t = cab_t * Geom::Transformation.new(local_origin) * sca_t
            puts "[EndPanelTool] Placing end panel on LEFT WING SIDE (L-shaped corner)" if MLCabinets::DEBUG
          elsif side == :left
            # Regular left side: outer face at X=0, depth runs along cabinet +Y.
            local_origin = Geom::Point3d.new(0, 0, 0)
            rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
            ep_t = cab_t * Geom::Transformation.new(local_origin) * rotation * sca_t
          else
            # Regular right side + Right Wing Side: outer face at X=cab_width.
            # Right Wing Side outer face is also at X=total_x (= cab_w_in for corner), same transform.
            local_origin = Geom::Point3d.new(cab_w_in, 0, 0)
            rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, -90.degrees)
            translate = Geom::Transformation.translation(Geom::Vector3d.new(-ep_depth_in / scale_x, 0, 0))
            ep_t = cab_t * Geom::Transformation.new(local_origin) * rotation * sca_t * translate
          end

          ep_inst.transformation = ep_t

          ep_inst.set_attribute(DA, 'lenx', ep_depth_in)
          ep_inst.set_attribute(DA, 'lenz', ep_height_in)

          # Tag the instance so ApplyPresetTool can identify and replace it.
          # ep_side: 'L' = left / left-wing (no trailing translate in sca_t chain)
          #          'R' = right / right-wing (has Translation(-def_bw, 0, 0) after sca_t)
          ep_side_str = (panel_name == 'Left Wing Side' || side == :left) ? 'L' : 'R'
          ep_inst.set_attribute('ml_cabinets', 'type',    'end_panel')
          ep_inst.set_attribute('ml_cabinets', 'ep_side', ep_side_str)

          model.commit_operation

          # Trigger DC evaluation
          CabinetDC.redraw_dc(ep_inst)

          @hover_bounds = nil
          view.invalidate
        rescue => e
          model.abort_operation
          puts "[EndPanelTool] Error — #{e.message}" if MLCabinets::DEBUG
          puts e.backtrace.first(4).join("\n") if MLCabinets::DEBUG
        end
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
        path = File.join(MLCabinets::PLUGIN_DIR, 'icons', 'end_panel_cursor.png')
        if File.exist?(path)
          begin
            ::UI.create_cursor(path, 0, 0)
          rescue => e
            warn "[MLCabinets::UI::EndPanelTool] Failed to create cursor: #{e.message}"
            CURSOR_HAND
          end
        else
          CURSOR_HAND
        end
      end

      # Walk the pick path looking for a side panel instance whose name
      # is "Left Side Panel" or "Right Side Panel", and whose ancestor
      # chain contains a valid cabinet root instance.
      def _find_side_panel(ph)
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
          next unless SIDE_PANEL_NAMES.include?(entity.name)

          side = entity.name.include?('Left') ? :left : :right
          wing = entity.name.include?('Wing') ? true : false

          # Walk backwards to find the parent Cabinet
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

          # Compute world transform of the side panel for hover highlight
          side_world_t = best_path[0...idx].inject(Geom::Transformation.new) { |t, e|
            e.is_a?(Sketchup::ComponentInstance) ? t * e.transformation : t
          } * entity.transformation

          return {
            cabinet_inst: cabinet_inst,
            side_inst:    entity,
            side:         side,
            wing:         wing,
            world_t:      side_world_t,
          }
        end
        nil
      end

      # Compute 8-point world-space bounding box for hover highlight.
      def _world_bounds(inst, world_t)
        bb = inst.definition.bounds
        corners = (0..7).map { |i| bb.corner(i) }
        corners.map { |pt| pt.transform(world_t) }
      rescue
        nil
      end

      # Determine panel preset ID from config (fallback chain)
      def _resolve_preset_id(config)
        return nil unless config.is_a?(Hash)

        # 1. Panel face preset
        panels = config[:panels] || {}
        pid = panels[:preset_id]
        return pid if pid && !pid.to_s.strip.empty?

        # 2. Door shape preset
        doors = config[:doors] || {}
        pid = doors[:shape] || doors[:preset_id]
        return pid if pid && !pid.to_s.strip.empty?

        # 3. Drawer shape preset
        drawers = config[:drawers] || {}
        pid = drawers[:shape] || drawers[:preset_id]
        return pid if pid && !pid.to_s.strip.empty?

        nil  # plain box fallback
      end

      # Determine panel material entry from config
      def _resolve_panel_material(config)
        return nil unless config.is_a?(Hash)
        mats = config[:materials] || {}
        entry = mats[:panel]
        return entry if entry && entry[:id] && !entry[:id].to_s.strip.empty?
        nil
      end

      # Create the end panel component and place it in model.active_entities.
      # All dimension arguments are in inches (SketchUp native).
      def _create_end_panel(model, preset_id, depth_in, height_in, thickness_in, panel_mat)
        ep_defn = PanelDC.load_definition(model, preset_id) if preset_id
        ep_defn ||= CabinetDC.make_panel(model, 'EndPanel', depth_in * 2.54, thickness_in * 2.54, -height_in * 2.54)

        inst = model.active_entities.add_instance(ep_defn, Geom::Transformation.new)
        inst.name = 'End Panel'

        MaterialHelper.apply(inst, panel_mat) if panel_mat

        inst
      end

    end # class EndPanelTool

  end # module UI
end # module MLCabinets
