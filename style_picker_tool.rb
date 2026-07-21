# ML Cabinets — Style Picker Tool
#
# Eyedropper / Format-Painter for cabinets. Two-phase workflow:
#   1. PICK  — click a cabinet to capture its config.
#              Hold Alt/Option to open the filter dialog (choose which properties).
#   2. APPLY — click other cabinets to overwrite them with the picked style.
#              Each click is a separate undo operation. Esc returns to PICK.

module MLCabinets
  module UI
    class StylePickerTool

      STATE_PICK  = :pick
      STATE_APPLY = :apply

      # Persist the last filter selection across tool activations (within session)
      @@last_filter = nil

      # Colors for wireframe overlays
      COLOR_PICK_HOVER   = Sketchup::Color.new(26, 111, 196, 180)    # blue
      COLOR_SOURCE       = Sketchup::Color.new(39, 160, 88, 200)     # green
      COLOR_APPLY_HOVER  = Sketchup::Color.new(217, 119, 6, 200)     # orange
      MAC_OPTION_MODIFIER_MASK = 524_288 unless defined?(MAC_OPTION_MODIFIER_MASK)



      # -------------------------------------------------------------------
      # Tool lifecycle
      # -------------------------------------------------------------------

      def initialize
        @state         = STATE_PICK
        @hover_entity  = nil
        @hover_bounds  = nil
        @source_entity = nil
        @source_bounds = nil
        @picked_config = nil
        @property_filter = nil   # nil = copy everything
      end

      def activate
        @state = STATE_PICK
        _update_status_text
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        @hover_entity  = nil
        @hover_bounds  = nil
        @source_entity = nil
        @source_bounds = nil
        @picked_config = nil
        @property_filter = nil
        view.invalidate
      end

      def resume(view)
        _update_status_text
        view.invalidate
      end

      def onSetCursor
        if @state == STATE_APPLY
          @cursor_apply ||= ::UI.create_cursor(
            File.join(MLCabinets::PLUGIN_DIR, 'icons', 'edit_cabinet_cursor.png'), 0, 0
          )
          ::UI.set_cursor(@cursor_apply)
        else
          @cursor_pick ||= ::UI.create_cursor(
            File.join(MLCabinets::PLUGIN_DIR, 'icons', 'style_picker_cursor.png'), 6, 27
          )
          ::UI.set_cursor(@cursor_pick)
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@hover_bounds)  if @hover_bounds
        bb.add(@source_bounds) if @source_bounds
        bb
      end

      # -------------------------------------------------------------------
      # Mouse move — highlight hovered cabinet
      # -------------------------------------------------------------------

      def onMouseMove(_flags, x, y, view)
        ph = view.pick_helper
        ph.do_pick(x, y)
        entity = ph.best_picked

        cabinet = _find_cabinet(entity, ph)

        if cabinet != @hover_entity
          @hover_entity = cabinet
          @hover_bounds = cabinet ? _world_bounds(cabinet) : nil
          view.invalidate
        end
      end

      # -------------------------------------------------------------------
      # Click — pick source or apply style
      # -------------------------------------------------------------------

      def onLButtonDown(flags, _x, _y, view)
        return unless @hover_entity

        if @state == STATE_PICK
          _handle_pick(flags, view)
        else
          _handle_apply(view)
        end
      end

      # -------------------------------------------------------------------
      # Keyboard
      # -------------------------------------------------------------------

      def onKeyDown(key, _repeat, _flags, _view)
        if key == 27 # Escape
          if @state == STATE_APPLY
            # Return to pick mode
            @state = STATE_PICK
            @source_entity = nil
            @source_bounds = nil
            @picked_config = nil
            @property_filter = nil
            _update_status_text
            Sketchup.active_model.active_view.invalidate
          else
            # Deactivate tool
            Sketchup.active_model.select_tool(nil)
          end
        end
      end

      # -------------------------------------------------------------------
      # Draw — wireframe overlays
      # -------------------------------------------------------------------

      def draw(view)
        # Source cabinet highlight (green, persistent in apply mode)
        if @source_bounds && @source_bounds.size >= 8
          _draw_wireframe(view, @source_bounds, COLOR_SOURCE)
        end

        # Hover highlight
        if @hover_bounds && @hover_bounds.size >= 8
          color = (@state == STATE_PICK) ? COLOR_PICK_HOVER : COLOR_APPLY_HOVER
          _draw_wireframe(view, @hover_bounds, color)
        end
      end

      private

      # -------------------------------------------------------------------
      # PICK handler
      # -------------------------------------------------------------------

      def _handle_pick(flags, view)
        entity = @hover_entity
        config = MLCabinets::CabinetDC.extract_config(entity)
        unless config
          Sketchup.status_text = 'Style Picker: no config found on this cabinet.'
          return
        end

        alt_held =
          (flags & ALT_MODIFIER_MASK) != 0 ||
          (flags & MAC_OPTION_MODIFIER_MASK) != 0

        if alt_held
          # Open filter dialog — user chooses which properties to copy
          @source_entity = entity
          @source_bounds = _world_bounds(entity)
          @picked_config = config

          MLCabinets::Dialogs::StylePickerDialog.show(config, @@last_filter) do |filter|
            if filter
              @@last_filter    = filter
              @property_filter = filter
              @state = STATE_APPLY
              _update_status_text
              Sketchup.active_model.active_view.invalidate
            else
              # User cancelled — stay in pick mode
              @source_entity = nil
              @source_bounds = nil
              @picked_config = nil
              _update_status_text
              Sketchup.active_model.active_view.invalidate
            end
          end
        else
          # No Ctrl — reuse last filter if one was set, otherwise copy all
          @source_entity   = entity
          @source_bounds   = _world_bounds(entity)
          @picked_config   = config
          @property_filter = @@last_filter
          @state = STATE_APPLY
          _update_status_text
          view.invalidate
        end
      end

      # -------------------------------------------------------------------
      # APPLY handler
      # -------------------------------------------------------------------

      def _handle_apply(view)
        target = @hover_entity
        return if target == @source_entity  # skip self

        target_config = MLCabinets::CabinetDC.extract_config(target)
        unless target_config
          Sketchup.status_text = 'Style Picker: target has no config — skipped.'
          return
        end

        merged = _merge_filtered_config(@picked_config, target_config, @property_filter)

        model = Sketchup.active_model
        model.start_operation('Style Picker', true)
        begin
          MLCabinets::CabinetDC.update_cabinet(target, merged)
          model.commit_operation
          Sketchup.status_text = 'Style Picker: style applied. Click another cabinet or press Esc.'
        rescue => e
          model.abort_operation
          puts "MLCabinets StylePicker: apply error — #{e.message}" if MLCabinets::DEBUG
          Sketchup.status_text = 'Style Picker: apply failed.'
        end

        view.invalidate
      end

      # -------------------------------------------------------------------
      # Config merge logic
      # -------------------------------------------------------------------

      # Mapping of filter keys → config paths.
      # Each entry is  filter_key => [array of top-level or nested key paths]
      FILTER_KEY_MAP = {
        # General
        'cabinetType'    => { top: [:type] },
        'dimensions'     => { top: [:width, :height, :depth] },
        'heightFromFloor'=> { top: [:height_from_floor] },
        'toeKick'        => { top: [:toe_kick] },

        # Construction
        'carcass'        => { nested: [:construction, [:top_panel, :base_panel, :side_panels, :panel_thickness]] },
        'backPanel'      => { nested: [:construction, [:back_panel_type, :back_panel_thickness, :back_panel_recess, :stretcher_count, :stretcher_width]] },
        'overlay'        => { nested: [:construction, [:overlay_type, :overlay_clearance]] },

        # Configuration
        'configuration'  => { top: [:groups] },

        # Doors
        'doorShape'      => { nested: [:doors, [:preset_id]] },
        'doorHandle'     => { nested: [:doors, [:handle_preset_id]] },
        'doorHandleOffsets' => { nested: [:doors, [:handle_offset_h, :handle_offset_v]] },
        'doorMaterial'   => { nested: [:materials, [:door]] },

        # Drawers
        'drawerShape'    => { nested: [:drawers, [:preset_id]] },
        'drawerHandle'   => { nested: [:drawers, [:handle_preset_id]] },
        'drawerHandleOffsets' => { nested: [:drawers, [:handle_offset_h, :handle_offset_v]] },
        'drawerMaterial' => { nested: [:materials, [:drawer]] },

        # Materials
        'panelMaterial'  => { nested: [:materials, [:carcass, :edge]] },
        'handleMaterial' => { nested: [:materials, [:handle]] },
        'glassMaterial'  => { nested: [:materials, [:glass]] },
      }.freeze

      def _merge_filtered_config(source, target, filter)
        # Deep-copy target as the base
        merged = JSON.parse(JSON.generate(target), symbolize_names: true)

        if filter.nil?
          # Copy everything from source, but preserve target's name
          result = JSON.parse(JSON.generate(source), symbolize_names: true)
          result[:name] = merged[:name]
          return result
        end

        # filter is a Hash like { "general" => ["cabinetType", "dimensions"], ... }
        checked_keys = filter.values.flatten

        checked_keys.each do |key|
          mapping = FILTER_KEY_MAP[key]
          next unless mapping

          if mapping[:top]
            # Copy top-level keys
            mapping[:top].each do |k|
              merged[k] = _deep_copy(source[k]) if source.key?(k)
            end
          end

          if mapping[:nested]
            parent_key, child_keys = mapping[:nested]
            merged[parent_key] ||= {}
            source_parent = source[parent_key] || {}
            child_keys.each do |ck|
              merged[parent_key][ck] = _deep_copy(source_parent[ck]) if source_parent.key?(ck)
            end
          end
        end

        merged
      end

      def _deep_copy(obj)
        return obj if obj.nil? || obj.is_a?(Numeric) || obj.is_a?(Symbol) ||
                       obj == true || obj == false
        JSON.parse(JSON.generate(obj), symbolize_names: true)
      rescue
        obj
      end

      # -------------------------------------------------------------------
      # Cabinet detection (same pattern as EditCabinetTool)
      # -------------------------------------------------------------------

      def _find_cabinet(entity, pick_helper)
        return nil unless entity

        if entity.is_a?(Sketchup::ComponentInstance) && MLCabinets::CabinetDC.cabinet_instance?(entity)
          return entity
        end

        path = pick_helper.path_at(0)
        return nil unless path

        path.reverse_each do |e|
          if e.is_a?(Sketchup::ComponentInstance) && MLCabinets::CabinetDC.cabinet_instance?(e)
            return e
          end
        end
        nil
      end

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

      def _draw_wireframe(view, pts, color)
        view.line_stipple = ''
        view.line_width = 2
        view.drawing_color = color

        # Bottom face
        view.draw_polyline(pts[0], pts[1], pts[2], pts[3], pts[0])
        # Top face
        view.draw_polyline(pts[4], pts[5], pts[6], pts[7], pts[4])
        # Verticals
        4.times { |i| view.draw_line(pts[i], pts[i + 4]) }
      end

      def _update_status_text
        if @state == STATE_PICK
          Sketchup.status_text = 'Style Picker: click a cabinet to pick its style. Hold Alt/Option to choose properties. Esc to cancel.'
        else
          Sketchup.status_text = 'Style Picker: click a cabinet to apply the picked style. Esc to re-pick.'
        end
      end

    end # class StylePickerTool
  end # module UI
end # module MLCabinets
