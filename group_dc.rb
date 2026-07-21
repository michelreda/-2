module MLCabinets
  module GroupDC

    DA         = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Build the Group ComponentDefinition.
    # The Group is a pure container — no geometry of its own.
    # Each group exposes g_width, g_height, g_depth as named attributes
    # (not DC's reserved lenx/y/z) to avoid scaling artefacts when
    # ----------------------------------------------------------------
    def self.create_group(model, parent, cabinet_name, id, drawer_face_defn: nil, door_leaf_defn: nil, panel_face_defn: nil, door_handle_defn: nil, drawer_handle_defn: nil, groups_count: 0, above_ext: nil, below_ext: nil, x_offset_in: nil, materials: {}, layers: nil)
      name = 'Group'

      defn = model.definitions.add(name)

      defn.description = 'Cabinet Group DC — ML Cabinets'
      
      defn.set_attribute(DA, 'name',         name)
      defn.set_attribute(DA, '_name_access', 'NONE')
      defn.set_attribute(DA, 'id', "#{id}")
      da_attr(defn, 'thickness',    "#{cabinet_name}!Thickness")
      da_attr(defn, 'bp_thickness', "#{cabinet_name}!bp_thickness")
      da_attr(defn, 'bp_setback',   "#{cabinet_name}!bp_setback")
      da_attr(defn, 'bk_type',      "#{cabinet_name}!bk_type")
      da_attr(defn, 'clearance',    "#{cabinet_name}!clearance")
      da_attr(defn, 'sp_type',      "#{cabinet_name}!sp_type")
      da_attr(defn, 'ov_type',      "#{cabinet_name}!ov_type")

      group_key = id.to_s.delete_prefix('g')

      # group_type: 0 = items stacked (vertical dividers)
      #             1 = items side by side     (horizontal dividers)
      groups_raw = parent.get_attribute(DA, 'groups').to_s
      groups_str = groups_raw.delete_prefix('"').delete_suffix('"')
      group_type = groups_str.match(/g#{group_key}:\s*\{[^}]*:gt=>(\w+)/) ? groups_str.match(/g#{group_key}:\s*\{[^}]*:gt=>(\w+)/)[1].strip : 'vert'
      defn.set_attribute(DA, 'g_type', "#{group_type}")
      defn.set_attribute(DA, 'groups_count', "#{groups_count}")
      
      add_to_cabinet(parent, defn, "#{cabinet_name}", model, drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn, panel_face_defn: panel_face_defn, door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn, above_ext: above_ext, below_ext: below_ext, x_offset_in: x_offset_in, materials: materials, layers: layers)
    end
    
    # ----------------------------------------------------------------
    # Add one group instance (1-based index) inside cabinet_defn.
    # Position and size reference the cabinet's computed helpers.
    # ----------------------------------------------------------------
    def self.add_to_cabinet(cabinet_defn, group_defn, cabinet_name, model, drawer_face_defn: nil, door_leaf_defn: nil, panel_face_defn: nil, door_handle_defn: nil, drawer_handle_defn: nil, above_ext: nil, below_ext: nil, x_offset_in: nil, materials: {}, layers: nil)
      p    = cabinet_name
      inst = cabinet_defn.entities.add_instance(group_defn, Geom::Transformation.new([0, 0, 0]))
      
      inst.name = "Group"
      group_key  = group_defn.get_attribute(DA, 'id').to_s.delete_prefix('g')

      # DC position within the cabinet
      # Blind corner cabinets pass x_offset_in so groups sit on the accessible face;
      # acc_offset is stored as a DA attribute on the cabinet definition.
      x_formula = (x_offset_in && x_offset_in > 0) ? "#{p}!acc_offset" : "#{p}!Thickness"
      da_attr(inst, 'x', x_formula)
      da_attr(inst, 'y', '0')
      da_attr(inst, 'z', "(#{p}!Toekick * #{p}!tk_height) + #{p}!Thickness + VALUE(MID(#{p}!groups, FIND(\":gz=>\", #{p}!groups, FIND(\"g\" & #{group_key} & \":\", #{p}!groups)) + 5, FIND(\"}\", #{p}!groups, FIND(\":gz=>\", #{p}!groups, FIND(\"g\" & #{group_key} & \":\", #{p}!groups))) - (FIND(\":gz=>\", #{p}!groups, FIND(\"g\" & #{group_key} & \":\", #{p}!groups)) + 5)))")
  
      # Size forwarded to child items (custom names avoid DC scaling)
      # Blind corner: use the pre-computed acc_width attribute (w - Thickness),
      # which is correct for both left and right accessible sides.
      g_width_formula = (x_offset_in && x_offset_in > 0) ? "#{p}!acc_width" : "#{p}!cab_width - 2 * #{p}!Thickness"
      da_attr(inst, 'g_width',  g_width_formula)
      da_attr(inst, 'shlf_width', "#{p}!shlf_width")
      da_attr(inst, 'shlf_x',     "#{p}!shlf_x")
      da_attr(inst, 'g_depth',  "#{p}!cab_depth")
      da_attr(inst, 'g_height', "VALUE(MID(#{p}!groups, FIND(\":gh=>\", #{p}!groups, FIND(\"g\" & #{group_key} & \":\", #{p}!groups)) + 5, FIND(\"}\", #{p}!groups, FIND(\":gh=>\", #{p}!groups, FIND(\"g\" & #{group_key} & \":\", #{p}!groups))) - (FIND(\":gh=>\", #{p}!groups, FIND(\"g\" & #{group_key} & \":\", #{p}!groups)) + 5)))")
      
      # DC reserved attributes — cause the engine to scale the placeholder
      # box geometry to exactly match the group zone dimensions
      da_attr(inst, 'lenx', 'g_width')
      da_attr(inst, 'leny', 'g_depth')
      da_attr(inst, 'lenz', 'g_height')
      
  
      # Parse serialized items string: "i1:[it:open,ih:7.874015,shlv:0];i2:[it:open,ih:0.0,shlv:2]"
      items_str = "" # default to empty string if not found
      groups_raw = cabinet_defn.get_attribute(DA, 'groups').to_s
      groups_str = groups_raw.delete_prefix('"').delete_suffix('"')

      # Hide auto-inserted divider/separator groups
      hdn_match = groups_str.match(/g#{group_key}:\s*\{[^}]*:hdn=>(\d+)/)
      da_attr(inst, 'hidden', "True") if hdn_match && hdn_match[1].to_i == 1

      interior_h = 0.0
      gz_in      = 0.0

      groups_str.scan(/g(\w+):\s*\{([^}]*):it=>([^}]*)\}/) do |gkey, attrs, items_part|
        next unless gkey == group_key
        items_str  = items_part.to_s.strip
        gh_match   = attrs.match(/:gh=>([\d.]+)/)
        interior_h = gh_match ? gh_match[1].to_f * 2.54 : 0.0
        gz_match   = attrs.match(/:gz=>([-\d.]+)/)
        gz_in      = gz_match ? gz_match[1].to_f : 0.0
      end

      items_array = []
      items_str.scan(/(i\d+):\[([^\]]*)\]/) do |ikey, kvs|
        h = { key: ikey }
        kvs.split(',').each { |pair| k, v = pair.split(':'); h[k.to_sym] = v }
        items_array << h
      end
      
      # Determine group type to decide layout axis
      gt_match = groups_str.match(/g#{group_key}:\s*\{[^}]*:gt=>(\w+)/)
      g_type   = gt_match ? gt_match[1].strip : 'vert'

      # Read group width (in inches) from the serialized groups string
      gw_match = groups_str.match(/g#{group_key}:\s*\{[^}]*:gw=>([\d.]+)/)
      interior_w = gw_match ? gw_match[1].to_f * 2.54 : 0.0

      # Compute fill sizes for whichever axis this group uses
      if g_type == 'hori'
        # Pre-resolve profile item widths so they don't consume fill space.
        # A 'prof' item with iw=0 takes its preset cross-section width, not
        # an equal share of the remaining room.
        items_array.each do |v|
          next unless v[:it] == 'prof' && v[:iw].to_f == 0 && v[:prid]
          pw = ProfileDC.preset_width_in(v[:prid])
          v[:iw] = pw.to_s if pw && pw > 0
        end

        # Horizontal: items side by side along X; fill based on width
        fill_count  = items_array.count { |v| v[:iw].to_f == 0 }
        fixed_w_sum = items_array.reject { |v| v[:iw].to_f == 0 }.sum { |v| v[:iw].to_f * 2.54 }
        fill_w      = fill_count > 0 ? (interior_w - fixed_w_sum) / fill_count : 0.0
      end
      # Vertical: items stacked along Z; fill based on height
      fill_count_h  = items_array.count { |v| v[:ih].to_f == 0 }
      fixed_h_sum   = items_array.reject { |v| v[:ih].to_f == 0 }.sum { |v| v[:ih].to_f * 2.54 }
      fill_h        = fill_count_h > 0 ? (interior_h - fixed_h_sum) / fill_count_h : 0.0

      z_offset = g_type == 'vert' ? interior_h : 0.0
      x_offset = 0.0

      # Compute position and size for every item once so the same values can be
      # written to both the g_items serialisation string and the Item DC attributes.
      positioned_items = items_array.map { |v|
        # Vertical axis (height / z) — placed top-to-bottom to match JS list order
        ih_cm   = v[:ih].to_f * 2.54
        ih_cm   = ih_cm == 0 ? fill_h : ih_cm
        it_fill = v[:ih].to_f == 0 ? 1 : 0
        z_offset -= ih_cm if g_type == 'vert'
        z_in    = z_offset / 2.54
        ih_in   = ih_cm / 2.54

        # Horizontal axis (width / x)
        iw_cm    = v[:iw].to_f * 2.54
        iw_cm    = iw_cm == 0 ? (g_type == 'hori' ? fill_w : 0.0) : iw_cm
        iwf      = v[:iw].to_f == 0 ? 1 : 0
        x_in     = x_offset / 2.54
        iw_in    = iw_cm / 2.54
        x_offset += iw_cm if g_type == 'hori'

        v.merge(iz: z_in.round(6), ih: ih_in.round(6), if: it_fill,
                ix: x_in.round(6), iw: iw_in.round(6), iwf: iwf)
      }

      entries = positioned_items.map { |v|
        computed = { it: v[:it], iz: v[:iz], ih: v[:ih], if: v[:if],
                     ix: v[:ix], iw: v[:iw], iwf: v[:iwf] }
        extra    = v.reject { |k, _| [:key, :it, :ih, :iz, :if, :iw, :ix, :iwf, :df_zt, :df_zb, :df_xl, :df_xr, :dl_zt, :dl_zb, :dl_xl, :dl_xr, :dsub].include?(k) }
        parts    = computed.merge(extra).map { |k, val| ":#{k}=>#{val}" }
        "#{v[:key]}: [#{parts.join(', ')}]"
      }
      items_str = entries.join('; ')
  
      # g_items: extracts the items string for this group from the cabinet's groups.
      # Items are delimited with [] to avoid conflicting with the } used as outer group boundary.
      inst.set_attribute(DA, 'g_items', "#{items_str}")
      inst.set_attribute(DA, '_g_items_formlabel', "Items")
      inst.set_attribute(DA, '_g_items_units', 'STRING')
      inst.set_attribute(DA, "_g_items_access", "TEXTBOX")
  
      # Compute drawer face overlay extensions for each drawer item.
      # Extensions depend on what's adjacent: cabinet panel → thickness, separator/divider → half its size.
      # Profile items are capped at 2 cm to avoid the face covering the profile entirely.
      t_in = cabinet_defn.get_attribute(DA, 'thickness').to_f
      above_ext ||= t_in
      below_ext ||= t_in
      prof_ext_max = 1.5 / 2.54  # 1.5 cm max profile extension in inches
      # Absolute Z of this group's bottom from the scene floor (inches).
      # Used by HandleDC to decide whether handles go at top or bottom of door.
      tk_h_in        = cabinet_defn.get_attribute(DA, 'tk_height').to_f
      hff_in         = cabinet_defn.get_attribute('ml_cabinets', 'hff_in').to_f
      group_abs_z_in = hff_in + tk_h_in + t_in + gz_in
      adj_ext = ->(adj, dim) {
        case adj[:it]
        when 'sepa', 'devi' then adj[dim].to_f / 2.0
        when 'prof' then [adj[dim].to_f / 2.0, prof_ext_max].min
        else 0.0
        end
      }

      positioned_items.each_with_index do |item, idx|
        next unless item[:it] == 'drwr' || item[:it] == 'fdrw'

        if g_type == 'vert'
          # Z top: first item uses group boundary, otherwise look at previous item
          item[:df_zt] = if idx == 0
                           above_ext
                         else
                           adj_ext.(positioned_items[idx - 1], :ih)
                         end
          # Z bottom: last item uses group boundary, otherwise look at next item
          item[:df_zb] = if idx == positioned_items.size - 1
                           below_ext
                         else
                           adj_ext.(positioned_items[idx + 1], :ih)
                         end
          # X: always panel thickness (side panels border vertical groups)
          item[:df_xl] = t_in
          item[:df_xr] = t_in

        elsif g_type == 'hori'
          # X left: first item uses side panel, otherwise look at previous item
          item[:df_xl] = if idx == 0
                           t_in
                         else
                           adj_ext.(positioned_items[idx - 1], :iw)
                         end
          # X right: last item uses side panel, otherwise look at next item
          item[:df_xr] = if idx == positioned_items.size - 1
                           t_in
                         else
                           adj_ext.(positioned_items[idx + 1], :iw)
                         end
          # Z: group boundary extensions for horizontal groups
          item[:df_zt] = above_ext
          item[:df_zb] = below_ext
        end
      end

      # Compute door leaf overlay extensions for each door item.
      # Same adjacency logic as drawer faces — door leaves extend to cover
      # adjacent cabinet panels and separator/divider items.
      positioned_items.each_with_index do |item, idx|
        next unless item[:it] == 'door'

        if g_type == 'vert'
          item[:dl_zt] = if idx == 0
                           above_ext
                         else
                           adj_ext.(positioned_items[idx - 1], :ih)
                         end
          item[:dl_zb] = if idx == positioned_items.size - 1
                           below_ext
                         else
                           adj_ext.(positioned_items[idx + 1], :ih)
                         end
          item[:dl_xl] = t_in
          item[:dl_xr] = t_in

        elsif g_type == 'hori'
          item[:dl_xl] = if idx == 0
                           t_in
                         else
                           adj_ext.(positioned_items[idx - 1], :iw)
                         end
          item[:dl_xr] = if idx == positioned_items.size - 1
                           t_in
                         else
                           adj_ext.(positioned_items[idx + 1], :iw)
                         end
          item[:dl_zt] = above_ext
          item[:dl_zb] = below_ext
        end
      end

      # Compute panel face overlay extensions for each panel item.
      # Same adjacency logic as door leaves — panel faces extend to cover
      # adjacent cabinet panels and separator/divider items.
      positioned_items.each_with_index do |item, idx|
        next unless item[:it] == 'panl'

        if g_type == 'vert'
          item[:pl_zt] = if idx == 0
                           above_ext
                         else
                           adj_ext.(positioned_items[idx - 1], :ih)
                         end
          item[:pl_zb] = if idx == positioned_items.size - 1
                           below_ext
                         else
                           adj_ext.(positioned_items[idx + 1], :ih)
                         end
          item[:pl_xl] = t_in
          item[:pl_xr] = t_in

        elsif g_type == 'hori'
          item[:pl_xl] = if idx == 0
                           t_in
                         else
                           adj_ext.(positioned_items[idx - 1], :iw)
                         end
          item[:pl_xr] = if idx == positioned_items.size - 1
                           t_in
                         else
                           adj_ext.(positioned_items[idx + 1], :iw)
                         end
          item[:pl_zt] = above_ext
          item[:pl_zb] = below_ext
        end
      end

      # Create children based on group type
      if g_type == 'separator' || g_type == 'divider'
        # Separator/divider groups are a single panel — no child items
        panel_inst = create_group_panel(model, group_defn, inst.name, g_type)
        MaterialHelper.apply(panel_inst, materials[:carcass]) if panel_inst
        panel_inst.layer = layers[:panels] if panel_inst && layers && layers[:panels]
      elsif g_type == 'prof'
        # Profile group — a profile shape extruded across the full cabinet width
        prid_match = groups_str.match(/g#{group_key}:\s*\{[^}]*:prid=>([^,}]+)/)
        prid = prid_match ? prid_match[1].strip : nil
        profile_inst = create_profile_group(model, group_defn, inst.name, prid)

        # Resolve per-group profile material override, or fall back to
        # the cabinet-level Handle material.
        if profile_inst
          prmid_match = groups_str.match(/g#{group_key}:\s*\{[^}]*:prmid=>([^,}]+)/)
          prmg_match  = groups_str.match(/g#{group_key}:\s*\{[^}]*:prmg=>([^,}]+)/)
          prmid = prmid_match ? prmid_match[1].strip : nil
          prmg  = prmg_match  ? prmg_match[1].strip  : 'horizontal'
          prof_mat = if prmid && !prmid.empty?
                       MaterialHelper.resolve(model, prmid, prmg)
                     else
                       materials[:handle]
                     end
          MaterialHelper.apply(profile_inst, prof_mat) if prof_mat
          profile_inst.layer = layers[:profiles] if profile_inst && layers && layers[:profiles]
        end
      else
        positioned_items.each do |item|
          # For drawer items, resolve per-item face override or fall back to cabinet-level preset
          item_face_defn = nil
          if item[:it] == 'drwr' || item[:it] == 'fdrw'
            if item[:dfid]
              item_face_defn = DrawerFaceDC.load_definition(model, item[:dfid])
            end
            item_face_defn ||= drawer_face_defn
          end

          # For door items, resolve per-item leaf override or fall back to cabinet-level preset
          item_leaf_defn = nil
          if item[:it] == 'door'
            if item[:dlid]
              item_leaf_defn = DoorLeafDC.load_definition(model, item[:dlid])
            end
            item_leaf_defn ||= door_leaf_defn
          end

          # For panel items, resolve per-item face override or fall back to cabinet-level preset
          item_panel_defn = nil
          if item[:it] == 'panl'
            if item[:plid] && !item[:plid].to_s.strip.empty?
              item_panel_defn = PanelDC.load_definition(model, item[:plid])
            end
            item_panel_defn ||= panel_face_defn
          end

          # For door/drawer items, resolve per-item handle override or fall back to cabinet-level preset
          item_handle_defn = nil
          if item[:it] == 'door' || item[:it] == 'drwr' || item[:it] == 'fdrw'
            if item[:hdl] && !item[:hdl].to_s.strip.empty?
              item_handle_defn = HandleDC.load_definition(model, item[:hdl].to_s)
            end
            item_handle_defn ||= (item[:it] == 'door' ? door_handle_defn : drawer_handle_defn)
          end

          # For appliance items, resolve the preset component definition
          item_appliance_defn = nil
          if item[:it] == 'appl' && item[:apid] && !item[:apid].to_s.strip.empty?
            item_appliance_defn = ApplianceDC.load_definition(model, item[:apid])
          end

          item_data = {
            iz:   item[:iz].to_f,
            ix:   item[:ix].to_f,
            ih:   item[:ih].to_f,
            iw:   item[:iw].to_f,
            it:   item[:it].to_s,
            shlv: item[:shlv].to_i,
            tclr: item[:tclr].to_f,
            bclr: item[:bclr].to_f,
            df_zt: item[:df_zt].to_f,
            df_zb: item[:df_zb].to_f,
            df_xl: item[:df_xl].to_f,
            df_xr: item[:df_xr].to_f,
            dl_zt: item[:dl_zt].to_f,
            dl_zb: item[:dl_zb].to_f,
            dl_xl: item[:dl_xl].to_f,
            dl_xr: item[:dl_xr].to_f,
            pl_zt: item[:pl_zt].to_f,
            pl_zb: item[:pl_zb].to_f,
            pl_xl: item[:pl_xl].to_f,
            pl_xr: item[:pl_xr].to_f,
            dsub:  item[:dsub].to_s,
            hoff:  item[:hoff].to_f,
            voff:  item[:voff].to_f,
            hrot:  item[:hrot].to_f,
            hdl:   item[:hdl].to_s,
            abs_z: (group_abs_z_in + item[:iz].to_f).round(6),
            mat:   item[:mat].to_s,
            matg:  item[:matg].to_s,
            prmid: item[:prmid].to_s,
            prmg:  item[:prmg].to_s,
            oa:    item[:oa].to_f,
            apid:  item[:apid].to_s,
          }
          ItemDC.build_definition(model, group_defn, "#{inst.name}", item[:key],
            item_type: item[:it], profile_id: item[:prid], g_type: g_type,
            drawer_face_defn: item_face_defn,
            door_leaf_defn: item_leaf_defn,
            panel_face_defn: item_panel_defn,
            handle_defn: item_handle_defn,
            appliance_defn: item_appliance_defn,
            hidden: item[:hdn].to_s == "1",
            item_data: item_data,
            materials: materials,
            layers: layers)
        end
      end

      inst
    end

    # ----------------------------------------------------------------
    # Create a panel inside a separator or divider group.
    # Separator: full depth (front to back panel).
    # Divider:   thin strip (panel-thickness deep) at the front.
    # ----------------------------------------------------------------
    def self.create_group_panel(model, parent_defn, group_name, panel_type)
      name = panel_type == 'separator' ? 'Separator' : 'Divider'

      defn = model.definitions.add(name)
      defn.description = "Cabinet #{name} DC — ML Cabinets"

      # Placeholder box — the DC engine resizes via lenx/leny/lenz
      w = 1.cm
      face = defn.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, w, 0),
        Geom::Point3d.new(0, w, 0)
      )
      face.pushpull(-w)

      defn.set_attribute(DA, 'name', name)
      defn.set_attribute(DA, '_name_access', 'NONE')

      p = group_name
      inst = parent_defn.entities.add_instance(defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = name

      # Position
      da_attr(inst, 'x', '0')
      if panel_type == 'separator'
        da_attr(inst, 'y', "CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) + #{p}!clearance")
      else
        da_attr(inst, 'y', "#{p}!g_depth - #{p}!thickness")
      end
      da_attr(inst, 'z', '0')

      # Size
      da_attr(inst, 'lenx', "#{p}!g_width")
      if panel_type == 'separator'
        da_attr(inst, 'leny', "#{p}!g_depth - CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) - #{p}!clearance")
      else
        da_attr(inst, 'leny', "#{p}!thickness")
      end
      da_attr(inst, 'lenz', "#{p}!g_height")

      inst
    end

    def self.create_profile_group(model, parent_defn, group_name, profile_id)
      return unless profile_id && !profile_id.to_s.strip.empty?

      result = ProfileDC.load_and_build(model, profile_id, g_type: 'vert')
      return unless result

      profile_defn, _profile_w_in, profile_h_in = result

      p    = group_name
      inst = parent_defn.entities.add_instance(profile_defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = 'ProfileGroup'

      # Position — flush with the front face of the cabinet
      da_attr(inst, 'x', '0')
      da_attr(inst, 'y', "#{p}!g_depth - #{profile_h_in.round(6)}")
      da_attr(inst, 'z', '0')

      # Size — full cabinet interior width; lenz driven by user-set group height
      da_attr(inst, 'lenx', "#{p}!g_width")
      da_attr(inst, 'leny', "#{profile_h_in.round(6)}")
      da_attr(inst, 'lenz', "#{p}!g_height")

      inst
    end

    # ================================================================
    # Private helpers
    # ================================================================

    def self.da_attr(defn, key, value, label: " ", units: 'STRING', access: "NONE")
      defn.set_attribute(DA, key,                 value)
      defn.set_attribute(DA, "_#{key}_formula",   value)
      defn.set_attribute(DA, "_#{key}_formlabel", label)
      defn.set_attribute(DA, "_#{key}_units",     units)
      defn.set_attribute(DA, "_#{key}_access",    access)
    end
    private_class_method :da_attr, :add_to_cabinet, :create_group_panel, :create_profile_group

  end
end
