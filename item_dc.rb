module MLCabinets
  module ItemDC

    DA         = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Build (or reuse) the Item ComponentDefinition.
    # The Item is a pure container — no geometry of its own.
    # Each item exposes g_width, g_height, g_depth as named attributes
    # (not DC's reserved lenx/y/z) to avoid scaling artefacts when
    # multiple item instances share the same definition.
    # ----------------------------------------------------------------
    def self.build_definition(model, parent, group_name, id, item_type: 'open', profile_id: nil, g_type: 'vert', drawer_face_defn: nil, door_leaf_defn: nil, panel_face_defn: nil, handle_defn: nil, appliance_defn: nil, hidden: false, item_data: {}, materials: {}, layers: nil)
      name = 'Item'
      
      defn = model.definitions.add(name)

      defn.description = 'Cabinet Item DC — ML Cabinets'

      defn.set_attribute(DA, 'name',         name)
      defn.set_attribute(DA, '_name_access', 'NONE')      
      defn.set_attribute(DA, 'id', "#{id}")
      da_attr(defn, 'thickness',    "#{group_name}!Thickness")
      da_attr(defn, 'bp_thickness', "#{group_name}!bp_thickness")
      da_attr(defn, 'bp_setback',   "#{group_name}!bp_setback")
      da_attr(defn, 'bk_type',      "#{group_name}!bk_type")
      da_attr(defn, 'clearance',    "#{group_name}!clearance")
      da_attr(defn, 'sp_type',      "#{group_name}!sp_type")
      da_attr(defn, 'ov_type',      "#{group_name}!ov_type")

      add_to_group(parent, defn, "#{group_name}", model, item_type: item_type, profile_id: profile_id, g_type: g_type, drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn, panel_face_defn: panel_face_defn, handle_defn: handle_defn, appliance_defn: appliance_defn, hidden: hidden, item_data: item_data, materials: materials, layers: layers)
    end
    
    # ----------------------------------------------------------------
    # Add one item instance (1-based index) inside cabinet_defn.
    # Position and size reference the cabinet's computed helpers.
    # ----------------------------------------------------------------
    def self.add_to_group(parent_defn, item_defn, cabinet_name, model, item_type: 'open', profile_id: nil, g_type: 'vert', drawer_face_defn: nil, door_leaf_defn: nil, panel_face_defn: nil, handle_defn: nil, appliance_defn: nil, hidden: false, item_data: {}, materials: {}, layers: nil)
      p    = cabinet_name
      inst = parent_defn.entities.add_instance(item_defn, Geom::Transformation.new([0, 0, 0]))

      is_hori = (g_type == 'hori') ? 1 : 0
      x_val   = is_hori == 1 ? item_data[:ix].to_f : 0.0
      z_val   = is_hori == 1 ? 0.0 : item_data[:iz].to_f

      # DC position within the group — stored as computed values, updated by recalculate_items on resize.
      da_attr(inst, 'is_hori', is_hori.to_s, units: "NUMBER")
      da_attr(inst, 'x', x_val.round(6).to_s)
      da_attr(inst, 'y', '0')
      da_attr(inst, 'z', z_val.round(6).to_s)

      # Size: axis that matches the layout direction uses the pre-computed per-item value;
      # the other axis always spans the full group and is driven by the parent formula.
      i_width_val  = is_hori == 1 ? item_data[:iw].to_f.round(6).to_s : "#{p}!LenX"
      i_height_val = is_hori == 1 ? "#{p}!LenZ"                       : item_data[:ih].to_f.round(6).to_s

      da_attr(inst, 'i_width',  i_width_val)
      # In horizontal groups each item has its own width, so shelves must
      # fit inside that item — not span the entire cabinet.
      shlf_w_val = is_hori == 1 ? 'i_width' : "#{p}!shlf_width"
      shlf_x_val = is_hori == 1 ? '0'       : "#{p}!shlf_x"
      da_attr(inst, 'shlf_width', shlf_w_val)
      da_attr(inst, 'shlf_x',     shlf_x_val)
      da_attr(inst, 'i_depth',  "#{p}!LenY")
      da_attr(inst, 'i_height', i_height_val)

      inst.set_attribute(DA, 'i_type', item_data[:it].to_s)

      # DC reserved attributes — cause the engine to scale the placeholder
      # box geometry to exactly match the group zone dimensions
      da_attr(inst, 'lenx', 'i_width')
      da_attr(inst, 'leny', 'i_depth')
      da_attr(inst, 'lenz', 'i_height')

      da_attr(inst, 'shlvs_cnt', item_data[:shlv].to_i.to_s, units: "NUMBER")

      # Drawer-specific: top/bottom clearance in inches (matches the units stored in g_items).
      da_attr(inst, 'tclr', item_data[:tclr].to_f.round(6).to_s)
      da_attr(inst, 'bclr', item_data[:bclr].to_f.round(6).to_s)

      # Drawer face overlay extensions (inches) — how far the face extends
      # beyond the item envelope on each side to cover adjacent panels/separators.
      if item_type == 'drwr' || item_type == 'fdrw'
        da_attr(inst, 'df_zt', item_data[:df_zt].to_f.round(6).to_s)
        da_attr(inst, 'df_zb', item_data[:df_zb].to_f.round(6).to_s)
        da_attr(inst, 'df_xl', item_data[:df_xl].to_f.round(6).to_s)
        da_attr(inst, 'df_xr', item_data[:df_xr].to_f.round(6).to_s)
      end

      # Door leaf overlay extensions (inches) — same pattern as drawer faces.
      if item_type == 'door'
        da_attr(inst, 'dl_zt', item_data[:dl_zt].to_f.round(6).to_s)
        da_attr(inst, 'dl_zb', item_data[:dl_zb].to_f.round(6).to_s)
        da_attr(inst, 'dl_xl', item_data[:dl_xl].to_f.round(6).to_s)
        da_attr(inst, 'dl_xr', item_data[:dl_xr].to_f.round(6).to_s)
        inst.set_attribute(DA, 'door_sub', item_data[:dsub].to_s)
      end

      # Panel face overlay extensions (inches) — static cladding, no rotation.
      if item_type == 'panl'
        da_attr(inst, 'pl_zt', item_data[:pl_zt].to_f.round(6).to_s)
        da_attr(inst, 'pl_zb', item_data[:pl_zb].to_f.round(6).to_s)
        da_attr(inst, 'pl_xl', item_data[:pl_xl].to_f.round(6).to_s)
        da_attr(inst, 'pl_xr', item_data[:pl_xr].to_f.round(6).to_s)
      end

      # Handle offsets — stored in cm with CENTIMETERS units so SketchUp DC
      # converts to inches correctly in formula evaluation.
      # item_data[:hoff] is in inches (serialized format); multiply by 2.54 to get cm.
      if item_type == 'door' || item_type == 'drwr' || item_type == 'fdrw'
        da_attr(inst, 'hdl_hoff', (item_data[:hoff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
        da_attr(inst, 'hdl_voff', (item_data[:voff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
        da_attr(inst, 'hdl_rot', item_data[:hrot].to_f.round(3).to_s, units: 'DEGREES')
      end

      # Open/close state and design-time opening amount (0–100 %).
      # door_open: 0 = closed, 1 = open. Used by OpenCloseTool to persist
      # state across DC re-evaluations. oa is the target opening percentage.
      # false-drawer (fdrw) is intentionally excluded — it cannot be opened.
      if item_type == 'door' || item_type == 'drwr'
        da_attr(inst, 'door_open', '0', units: 'NUMBER')
        da_attr(inst, 'oa',        item_data[:oa].to_f.round(2).to_s, units: 'NUMBER')
      end

      inst.name = "Item"

      # Hide auto-inserted divider/separator items
      da_attr(inst, 'hidden', "True") if hidden

      # Add children based on item type
      #
      # Per-item material override: if the item has a :mat field, resolve
      # it and use that material for the door leaf / drawer face instead of
      # the cabinet-level :door / :drawer material.
      #
      # Grain-only override: if :matg is set but :mat is empty, re-resolve
      # the category material with the per-item grain so a grain swap
      # doesn't force a per-item material_id that blocks future category
      # changes.
      item_mat_id    = item_data[:mat].to_s
      item_mat_grain = item_data[:matg].to_s
      item_override_mat = nil
      if !item_mat_id.empty?
        item_override_mat = MaterialHelper.resolve(model, item_mat_id,
                              item_mat_grain.empty? ? 'vertical' : item_mat_grain)
      end

      # Grain-only override: re-resolve the category material with the
      # per-item grain so the grain swap tool does not need to stamp a
      # per-item material_id (which would block future category changes).
      grain_only_mat = nil
      if item_override_mat.nil? && !item_mat_grain.empty?
        cat_key = { 'door' => :door, 'drwr' => :drawer, 'fdrw' => :drawer, 'panl' => :panel }[item_type]
        cat_mat = materials[cat_key] if cat_key
        if cat_mat
          cat_pid = cat_mat.get_attribute('ml_cabinets', 'preset_id')
          grain_only_mat = MaterialHelper.resolve(model, cat_pid, item_mat_grain) if cat_pid && !cat_pid.empty?
        end
      end

      item_handle_mat_id    = item_data[:hmat].to_s
      item_handle_mat_grain = item_data[:hmatg].to_s
      item_handle_override_mat = nil
      if !item_handle_mat_id.empty?
        item_handle_override_mat = MaterialHelper.resolve(
          model,
          item_handle_mat_id,
          item_handle_mat_grain.empty? ? 'vertical' : item_handle_mat_grain
        )
      end

      if item_type == 'sepa' || item_type == 'devi'
        panel_inst = create_item_panel(model, item_defn, inst.name, item_type)
        MaterialHelper.apply(panel_inst, materials[:carcass]) if panel_inst
        panel_inst.layer = layers[:panels] if panel_inst && layers && layers[:panels]
      elsif item_type == 'blnk'
        blank_inst = BlankDC.create_blank(model, item_defn, "#{inst.name}")
        MaterialHelper.apply(blank_inst, materials[:carcass]) if blank_inst
        blank_inst.layer = layers[:carcass] if blank_inst && layers && layers[:carcass]
      elsif item_type == 'drwr'
        drawer_box_inst = DrawerDC.create_drawer_box(model, item_defn, "#{inst.name}")
        MaterialHelper.apply(drawer_box_inst, materials[:carcass]) if drawer_box_inst
        drawer_box_inst.layer = layers[:drawers] if drawer_box_inst && layers && layers[:drawers]
        if drawer_face_defn
          face_inst, face_panel_inst, face_hdl_inst = DrawerFaceDC.create_drawer_face(
            model, item_defn, inst.name, drawer_face_defn,
            handle_defn: handle_defn, item_data: item_data,
            indication_layer: layers&.[](:indications)
          )
          face_mat = item_override_mat || grain_only_mat || materials[:drawer]
          handle_mat = item_handle_override_mat || materials[:handle]
          MaterialHelper.apply(face_panel_inst, face_mat, glass_material: materials[:glass], metal_material: handle_mat) if face_panel_inst
          MaterialHelper.apply(face_hdl_inst,   handle_mat) if face_hdl_inst
          face_inst.layer     = layers[:drawers] if face_inst     && layers && layers[:drawers]
          face_hdl_inst.layer = layers[:handles] if face_hdl_inst && layers && layers[:handles]
        end
      elsif item_type == 'fdrw'
        # False drawer — face panel only, no drawer box, cannot be opened.
        if drawer_face_defn
          face_inst, face_panel_inst, face_hdl_inst = DrawerFaceDC.create_drawer_face(
            model, item_defn, inst.name, drawer_face_defn,
            handle_defn: handle_defn, item_data: item_data,
            indication_layer: nil
          )
          face_mat = item_override_mat || grain_only_mat || materials[:drawer]
          handle_mat = item_handle_override_mat || materials[:handle]
          MaterialHelper.apply(face_panel_inst, face_mat, glass_material: materials[:glass], metal_material: handle_mat) if face_panel_inst
          MaterialHelper.apply(face_hdl_inst,   handle_mat) if face_hdl_inst
          face_inst.layer     = layers[:drawers] if face_inst     && layers && layers[:drawers]
          face_hdl_inst.layer = layers[:handles] if face_hdl_inst && layers && layers[:handles]
        end
      elsif item_type == 'door'
        shelf_inst = ShelfDC.create_shelf(model, item_defn, "#{inst.name}")
        MaterialHelper.apply(shelf_inst, materials[:carcass]) if shelf_inst
        shelf_inst.layer = layers[:carcass] if shelf_inst && layers && layers[:carcass]
        if door_leaf_defn
          leaf_mat = item_override_mat || grain_only_mat || materials[:door]
          handle_mat = item_handle_override_mat || materials[:handle]
          if item_data[:dsub].to_s == 'double-door'
            leaves, panels, handle_insts = DoorLeafDC.create_double_door_leaf(
              model, item_defn, inst.name, door_leaf_defn,
              handle_defn: handle_defn, item_data: item_data, abs_z_in: item_data[:abs_z].to_f,
              indication_layer: layers&.[](:indications)
            )
            Array(panels).each       { |pi| MaterialHelper.apply(pi, leaf_mat, glass_material: materials[:glass], metal_material: handle_mat) if pi }
            Array(handle_insts).each { |hi| MaterialHelper.apply(hi, handle_mat) if hi }
            Array(leaves).each       { |l|  l.layer  = layers[:doors]   if l  && layers && layers[:doors] }
            Array(handle_insts).each { |hi| hi.layer = layers[:handles] if hi && layers && layers[:handles] }
          else
            leaf_inst, panel_inst, handle_inst = DoorLeafDC.create_door_leaf(
              model, item_defn, inst.name, door_leaf_defn,
              handle_defn: handle_defn, item_data: item_data,
              door_sub: item_data[:dsub].to_s, abs_z_in: item_data[:abs_z].to_f,
              indication_layer: layers&.[](:indications)
            )
            MaterialHelper.apply(panel_inst,  leaf_mat, glass_material: materials[:glass], metal_material: handle_mat) if panel_inst
            MaterialHelper.apply(handle_inst, handle_mat) if handle_inst
            leaf_inst.layer   = layers[:doors]   if leaf_inst   && layers && layers[:doors]
            handle_inst.layer = layers[:handles] if handle_inst && layers && layers[:handles]
          end
        end
      elsif item_type == 'prof'
        profile_inst = profile_id ? ProfileDC.create_profile(model, item_defn, inst.name, profile_id, g_type: g_type) : nil
        if profile_inst
          # Per-item profile material override, or fall back to cabinet-level Handle material
          prof_mat_id    = item_data[:prmid].to_s
          prof_mat_grain = item_data[:prmg].to_s
          prof_mat = if !prof_mat_id.empty?
                       MaterialHelper.resolve(model, prof_mat_id,
                         prof_mat_grain.empty? ? 'horizontal' : prof_mat_grain)
                     else
                       materials[:handle]
                     end
          MaterialHelper.apply(profile_inst, prof_mat) if prof_mat
          profile_inst.layer = layers[:profiles] if layers && layers[:profiles]
        else
          panel_inst = create_item_panel(model, item_defn, inst.name, 'devi')
          MaterialHelper.apply(panel_inst, materials[:carcass]) if panel_inst
          panel_inst.layer = layers[:panels] if panel_inst && layers && layers[:panels]
        end
      elsif item_type == 'panl'
        shelf_inst = ShelfDC.create_shelf(model, item_defn, "#{inst.name}")
        MaterialHelper.apply(shelf_inst, materials[:carcass]) if shelf_inst
        shelf_inst.layer = layers[:carcass] if shelf_inst && layers && layers[:carcass]
        if panel_face_defn
          face_mat = item_override_mat || grain_only_mat || materials[:panel]
          face_inst, face_panel_inst = PanelDC.create_panel_face(
            model, item_defn, inst.name, panel_face_defn,
            item_data: item_data
          )
          MaterialHelper.apply(face_panel_inst, face_mat, glass_material: materials[:glass], metal_material: materials[:handle]) if face_panel_inst
          face_panel_inst.layer = layers[:panels] if face_panel_inst && layers && layers[:panels]
        end
      elsif item_type == 'appl'
        ApplianceDC.create_appliance(model, item_defn, inst.name, appliance_defn,
          appliance_id: item_data[:apid], abs_z_in: item_data[:abs_z].to_f)
      else
        shelf_inst = ShelfDC.create_shelf(model, item_defn, "#{inst.name}")
        MaterialHelper.apply(shelf_inst, materials[:carcass]) if shelf_inst
        shelf_inst.layer = layers[:carcass] if shelf_inst && layers && layers[:carcass]
      end

      inst
    end

    # ----------------------------------------------------------------
    # Create a panel inside a separator or divider item.
    # Separator: full depth (front to back panel).
    # Divider:   thin strip (panel-thickness deep) at the front.
    # ----------------------------------------------------------------
    def self.create_item_panel(model, parent_defn, item_name, panel_type)
      name = panel_type == 'sepa' ? 'Separator' : 'Divider'

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

      p = item_name
      inst = parent_defn.entities.add_instance(defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = name

      # Position
      da_attr(inst, 'x', '0')
      if panel_type == 'sepa'
        da_attr(inst, 'y', "CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) + #{p}!clearance")
      else
        da_attr(inst, 'y', "#{p}!i_depth - #{p}!thickness")
      end
      da_attr(inst, 'z', '0')

      # Size
      da_attr(inst, 'lenx', "#{p}!i_width")
      if panel_type == 'sepa'
        da_attr(inst, 'leny', "#{p}!i_depth - CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) - #{p}!clearance")
      else
        da_attr(inst, 'leny', "#{p}!thickness")
      end
      da_attr(inst, 'lenz', "#{p}!i_height")

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
    # Update position/size attributes on an existing item instance after a cabinet resize.
    # Only the axis values that can change with dimensions are written — the other axis
    # is already driven by a parent formula (LenX or LenZ) and stays live.
    def self.update_item_position(inst, item_data, g_type)
      if g_type == 'hori'
        inst.set_attribute(DA, 'x',                item_data[:ix].to_f.round(6).to_s)
        inst.set_attribute(DA, '_x_formula',       item_data[:ix].to_f.round(6).to_s)
        inst.set_attribute(DA, 'i_width',          item_data[:iw].to_f.round(6).to_s)
        inst.set_attribute(DA, '_i_width_formula', item_data[:iw].to_f.round(6).to_s)
      else
        inst.set_attribute(DA, 'z',                 item_data[:iz].to_f.round(6).to_s)
        inst.set_attribute(DA, '_z_formula',        item_data[:iz].to_f.round(6).to_s)
        inst.set_attribute(DA, 'i_height',          item_data[:ih].to_f.round(6).to_s)
        inst.set_attribute(DA, '_i_height_formula', item_data[:ih].to_f.round(6).to_s)
      end
    end

    private_class_method :da_attr, :add_to_group, :create_item_panel

  end
end
