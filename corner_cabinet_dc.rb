# frozen_string_literal: true

module MLCabinets
  module CornerCabinetDC

    DA = 'dynamic_attributes' unless defined?(DA)

    BLIND_MARGIN_CM    = 8.0           # 8 cm blind margin (cm mode)
    BLIND_MARGIN_IN_CM  = 7.62     # 3 inch blind margin in cm (inches mode)

    # ================================================================
    # Entry point — dispatches to the correct sub-builder.
    # Called from CabinetDC.make_cabinet when cab_type ends with '-corner'.
    # Returns a ComponentDefinition.
    # ================================================================

    def self.build(model, parent_name, params, side, base, top, back,
                   toekick_front, toekick_side, toekick_back, leg_defn = nil,
                   drawer_face_defn: nil, door_leaf_defn: nil,
                   door_handle_defn: nil, drawer_handle_defn: nil, panel_face_defn: nil,
                   skirting_defn: nil, materials: {}, layers: nil, display_name: nil)
      corner_type = params[:corner_type] || 'l-shaped'
      if corner_type == 'blind'
        build_blind(model, parent_name, params, side, base, top, back,
                    toekick_front, toekick_side, toekick_back, leg_defn,
                    drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn,
                    door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn,
                    panel_face_defn: panel_face_defn, skirting_defn: skirting_defn,
                    materials: materials, layers: layers, display_name: display_name)
      else
        build_l_shaped(model, parent_name, params, side, base, top, back,
                       toekick_front, toekick_side, toekick_back, leg_defn,
                       drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn,
                       door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn,
                       panel_face_defn: panel_face_defn, skirting_defn: skirting_defn,
                       materials: materials, layers: layers, display_name: display_name)
      end
    end

    # ================================================================
    # Blind Corner — standard rectangular box.
    # Total width = user width + depth + thickness + blind margin
    # (3 in / 7.62 cm when unit is inches; 8 cm otherwise).
    # The "accessible" side has the group/items; the blind side is empty.
    # ================================================================

    def self.build_blind(model, parent_name, params, side, base, top, back,
                         toekick_front, toekick_side, toekick_back, leg_defn = nil,
                         drawer_face_defn: nil, door_leaf_defn: nil,
                         door_handle_defn: nil, drawer_handle_defn: nil, panel_face_defn: nil,
                         skirting_defn: nil, materials: {}, layers: nil, display_name: nil)
      defn = model.definitions.add(parent_name)
      defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
      defn.description = 'Blind Corner Cabinet — ML Cabinets'

      # Destructure params
      w_cm            = params[:w_cm]   # user "width" = accessible opening width
      h_cm            = params[:h_cm]
      d_cm            = params[:d_cm]   # cabinet depth
      t_cm            = params[:t_cm]
      bt_cm           = params[:bt_cm]
      bp_sb_cm        = params[:bp_sb_cm]
      bk_type         = params[:bk_type]
      bk_st_cnt       = params[:bk_st_cnt]
      tk              = params[:tk]
      fs              = params[:fs]
      fb              = params[:fb]
      tk_h_cm         = params[:tk_h_cm]
      tk_sb_cm        = params[:tk_sb_cm]
      cl              = params[:cl]
      st_w_cm         = params[:st_w_cm]
      tp_type         = params[:tp_type]
      bp_type         = params[:bp_type]
      sp_type         = params[:sp_type]
      ov_type         = params[:ov_type]
      grps            = params[:grps]
      cab_type        = params[:cab_type] || 'base-corner'
      accessible_side = params[:accessible_side] || 'right'
      unit            = params[:unit] || 'cm'

      # Total width = width + depth + blind margin
      # Margin is 3 in (7.62 cm) when the session unit is inches, 8 cm otherwise.
      margin_cm  = unit == 'in' ? BLIND_MARGIN_IN_CM : BLIND_MARGIN_CM
      total_w_cm = w_cm + d_cm + margin_cm

      # Convert to inches
      t_in      = t_cm.to_f / 2.54
      bt_in     = bt_cm.to_f / 2.54
      bp_sb_in  = bp_sb_cm.to_f / 2.54
      tk_h_in   = tk_h_cm.to_f / 2.54
      tk_sb_in  = tk_sb_cm.to_f / 2.54
      cl_in     = cl.to_f / 2.54
      st_w_in   = st_w_cm.to_f / 2.54
      tk_str    = tk ? 'True' : 'False'
      fs_str    = fs ? 'True' : 'False'
      fb_str    = fb ? 'True' : 'False'

      # The accessible opening interior dimensions
      interior_h = h_cm - (tk ? tk_h_cm : 0.0) - 2.0 * t_cm
      interior_w = w_cm - 2.0 * t_cm  # Only the accessible portion

      # Group layout uses the accessible interior width
      fill_count  = grps.values.count { |v| v[:gh] == 0 }
      fixed_h_sum = grps.values.reject { |v| v[:gh] == 0 }.sum { |v| v[:gh] }
      fill_h      = fill_count > 0 ? (interior_h - fixed_h_sum) / fill_count : 0.0
      z_offset    = interior_h

      # Adjust group widths to use accessible interior width
      entries = grps.map { |k, v|
        gh_cm = v[:gh] == 0 ? fill_h : v[:gh]
        gf    = v[:gh] == 0 ? 1 : 0
        z_offset -= gh_cm
        z_in  = z_offset / 2.54
        gh_in = gh_cm / 2.54
        gw_in = interior_w / 2.54
        hdn_part  = v[:hidden] ? ", :hdn=>1" : ""
        prid_part = (v[:gt].to_s == 'prof' && v[:prid] && !v[:prid].to_s.empty?) ? ", :prid=>#{v[:prid]}" : ""
        "#{k}: {:gt=>#{v[:gt]}, :gz=>#{z_in.round(6)}, :gh=>#{gh_in.round(6)}, :gw=>#{gw_in.round(6)}, :gf=>#{gf}#{hdn_part}#{prid_part}, :it=>#{CabinetDC.serialize_items(v[:items])}}"
      }
      groups_str = entries.join('; ')

      # Offset for accessible side (groups sit on the accessible side)
      # If accessible = right, groups start from Thickness (after left side panel)
      # If accessible = left, groups are offset by (d_cm + margin_cm) — no thickness added
      acc_offset_cm = accessible_side == 'right' ? t_cm : (d_cm + margin_cm)
      acc_offset_in = acc_offset_cm / 2.54

      # ---- DC Attributes ----
      CabinetDC.da_attr(defn, 'thickness',           "#{t_in}",                'Panel Thickness',       'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'toekick',             "#{tk_str}",              'Toe Kick Enabled',      'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'toekick_flat_sides',  "#{fs_str}",              'Toe Kick Flat Sides',   'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'toekick_flat_back',   "#{fb_str}",              'Toe Kick Flat Back',    'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'tk_height',           "#{tk_h_in}",             'Toe Kick Height',       'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'tk_setback',          "#{tk_sb_in}",            'Toe Kick Setback',      'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bp_thickness',        "#{bt_in}",               'Back Panel Thickness',  'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bp_setback',          "#{bp_sb_in}",            'Back Panel Setback',    'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bk_type',             "#{bk_type}",             'Back Panel Type',       'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'bk_st_count',         "#{bk_st_cnt}",           'Back Stretchers Count', 'STRING',      'TEXTBOX')
      CabinetDC.da_attr(defn, 'groups',              "\"#{groups_str}\"",      'Groups',                'STRING',      'TEXTBOX')
      CabinetDC.da_attr(defn, 'clearance',           "#{cl_in}",               'Clearance',             'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'tp_type',             "#{tp_type}",             'Top Panel Type',        'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'st_width',            "#{st_w_in}",             'Stretcher Width',       'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bp_type',             "#{bp_type}",             'Base Panel Type',       'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'sp_type',             "#{sp_type}",             'Side Panel Type',       'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'ov_type',             "#{ov_type}",             'Overlay Type',          'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'acc_offset',          "#{acc_offset_in}",       'Accessible Offset',     'CENTIMETERS', 'NONE')

      # Blind face panel — front-facing strip (XZ plane) that closes the visible blind-zone
      # gap at the same depth as the door.
      # RIGHT accessible: blind zone starts at w_cm → face panel starts there
      # LEFT  accessible: blind zone is on the LEFT  → face panel starts at 0
      blind_face_x_cm = accessible_side == 'right' ? w_cm + t_cm : 0
      blind_face_x_in = blind_face_x_cm / 2.54
      blind_zone_w_cm = d_cm + margin_cm
      blind_zone_w_in = blind_zone_w_cm / 2.54
      CabinetDC.da_attr(defn, 'blind_face_x',        "#{blind_face_x_in}",     'Blind Face Panel X',    'CENTIMETERS', 'NONE')
      CabinetDC.da_attr(defn, 'blind_zone_w',         "#{blind_zone_w_in}",     'Blind Zone Width',      'CENTIMETERS', 'NONE')

      # Accessible interior width: from the inner face of the boundary side panel
      # to the start of the blind zone (= w_cm - t_cm), same for left and right.
      acc_width_in = (w_cm - t_cm) / 2.54
      CabinetDC.da_attr(defn, 'acc_width',             "#{acc_width_in}",        'Accessible Width',      'CENTIMETERS', 'NONE') # use total_w_cm for the cabinet footprint
      total_w_in = (total_w_cm / 2.54).round(6)
      d_in       = (d_cm / 2.54).round(6)
      h_in       = (h_cm / 2.54).round(6)
      CabinetDC.da_attr(defn, 'cab_width',  "#{total_w_in}", 'Cabinet Width',  'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'cab_depth',  "#{d_in}",       'Cabinet Depth',  'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'cab_height', "#{h_in}",       'Cabinet Height', 'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'shlf_width', "cab_width - 2 * Thickness", 'Shelf Width', 'CENTIMETERS', 'NONE')
      CabinetDC.da_attr(defn, 'shlf_x',     "Thickness - acc_offset",    'Shelf X Offset', 'CENTIMETERS', 'NONE')

      defn.set_attribute(DA, 'name', parent_name)
      defn.set_attribute(DA, '_toekick_options', 'True = 1 & False = 0')
      defn.set_attribute(DA, '_toekick_flat_sides_options', 'True = 1 & False = 0')
      defn.set_attribute(DA, '_toekick_flat_back_options',  'True = 1 & False = 0')
      defn.set_attribute(DA, '_tp_type_options', 'Closed = 1 & Open = 2 & None = 3')
      defn.set_attribute(DA, '_sp_type_options', 'Inset = 1 & Overlay = 2 & Full Height = 3')
      defn.set_attribute(DA, '_bp_type_options', 'Closed = 1 & Open = 2')
      defn.set_attribute(DA, '_bk_type_options', 'Closed = 1 & Stretchers = 2 & None = 3')
      defn.set_attribute(DA, '_ov_type_options', 'Inset = 1 & Partial = 2 & Full = 3')

      defn.set_attribute('ml_cabinets', 'type',           cab_type)
      defn.set_attribute('ml_cabinets', 'corner_type',    'blind')
      defn.set_attribute('ml_cabinets', 'accessible_side', accessible_side)
      defn.set_attribute('ml_cabinets', 'hff_in',         (params[:hff_cm].to_f / 2.54).round(6))
      defn.set_attribute('ml_cabinets', 'version',        MLCabinets::VERSION)
      defn.set_attribute('ml_cabinets', 'cab_name',       display_name || parent_name)

      parent = defn.get_attribute(DA, 'name')

      # ---- Side Panels ----
      # Left side panel (full height)
      t = Geom::Transformation.new([0, 0, h_cm.cm])
      side_l = CabinetDC.add_child(defn, side, t, 'Left Side Panel')
      CabinetDC.da_attr(side_l, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(side_l, 'lenx', "#{parent}!Thickness")
      CabinetDC.da_attr(side_l, 'leny', "#{parent}!cab_depth")
      CabinetDC.da_attr(side_l, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")
      CabinetDC.da_attr(side_l, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(side_l, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")
      MaterialHelper.apply(side_l, materials[:carcass])
      side_l.layer = layers[:carcass] if layers && layers[:carcass]

      # Right side panel (full height)
      t = Geom::Transformation.new([(total_w_cm - t_cm).cm, 0, h_cm.cm])
      side_r = CabinetDC.add_child(defn, side, t, 'Right Side Panel')
      CabinetDC.da_attr(side_r, 'x',    "#{parent}!cab_width - #{parent}!Thickness")
      CabinetDC.da_attr(side_r, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(side_r, 'lenx', "#{parent}!Thickness")
      CabinetDC.da_attr(side_r, 'leny', "#{parent}!cab_depth")
      CabinetDC.da_attr(side_r, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")
      CabinetDC.da_attr(side_r, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(side_r, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")
      MaterialHelper.apply(side_r, materials[:carcass])
      side_r.layer = layers[:carcass] if layers && layers[:carcass]
      # Sits in the front face plane (XZ) — same depth as the door.
      # lenx spans the blind zone width; leny = one panel thickness.
      # y responds to ov_type:
      #   Inset (1)         : y = LenY - Thickness  (face recessed one thickness from front)
      #   Partial/Full (2,3): y = LenY              (face flush with the cabinet front)
      #
      # A dedicated panel definition is created with the correct initial
      # proportions (wide × thin × tall) so that DC scaling factors are
      # close to 1× and the UV mapping is not stretched.
      blind_face_h_cm = h_cm - (tk ? tk_h_cm : 0.0)
      blind_face_w_cm = blind_zone_w_cm - t_cm
      blind_face_defn = CabinetDC.make_panel(model, 'BlindFacePanel', blind_face_w_cm, t_cm, blind_face_h_cm)
      t = Geom::Transformation.new([0, 0, h_cm.cm])
      blind_front = CabinetDC.add_child(defn, blind_face_defn, t, 'Blind Face Panel')
      blind_front.set_attribute('ml_cabinets', 'blind_face_panel', true)
      CabinetDC.da_attr(blind_front, 'x',          "#{parent}!blind_face_x")
      CabinetDC.da_attr(blind_front, 'y',          "CHOOSE(#{parent}!ov_type, #{parent}!cab_depth - #{parent}!Thickness, #{parent}!cab_depth, #{parent}!cab_depth)")
      CabinetDC.da_attr(blind_front, 'z',          "#{parent}!cab_height - CHOOSE(#{parent}!ov_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(blind_front, 'lenx',       "#{parent}!blind_zone_w - #{parent}!Thickness")
      CabinetDC.da_attr(blind_front, 'leny',       "#{parent}!Thickness")
      CabinetDC.da_attr(blind_front, 'lenz',       "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!ov_type, #{parent}!Thickness, 0, 0))")
      # Resolve blind face material with per-panel grain override if present
      bf_grain = params[:blind_face_grain].to_s
      bf_mat   = if !bf_grain.empty? && materials[:door]
                   door_mat_id = (params[:materials][:door] || {})[:id].to_s
                   door_mat_id.empty? ? materials[:door] : MaterialHelper.resolve(model, door_mat_id, bf_grain)
                 else
                   materials[:door]
                 end
      MaterialHelper.apply(blind_front, bf_mat)
      blind_front.layer = layers[:doors] if layers && layers[:doors]

      # ---- Base Panel ----
      t = Geom::Transformation.new([t_cm.cm, 0, (tk_h_cm + t_cm).cm])
      base_panel = CabinetDC.add_child(defn, base, t, 'Base Panel')
      CabinetDC.da_attr(base_panel, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(base_panel, 'z',      "(#{parent}!Toekick * #{parent}!tk_height) + #{parent}!Thickness")
      CabinetDC.da_attr(base_panel, 'lenx',   "#{parent}!cab_width - 2 * CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(base_panel, 'leny',   "#{parent}!cab_depth")
      CabinetDC.da_attr(base_panel, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(base_panel, 'hidden', "CHOOSE(#{parent}!bp_type, False, True)")
      MaterialHelper.apply(base_panel, materials[:carcass])
      base_panel.layer = layers[:carcass] if layers && layers[:carcass]

      # ---- Top Panel ----
      t = Geom::Transformation.new([t_cm.cm, 0, (h_cm - t_cm).cm])
      top_panel = CabinetDC.add_child(defn, top, t, 'Top Panel')
      CabinetDC.da_attr(top_panel, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(top_panel, 'z',      "#{parent}!cab_height")
      CabinetDC.da_attr(top_panel, 'lenx',   "#{parent}!cab_width - 2 * CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(top_panel, 'leny',   "CHOOSE(#{parent}!tp_type, #{parent}!cab_depth, #{parent}!st_width, #{parent}!st_width)")
      CabinetDC.da_attr(top_panel, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(top_panel, 'hidden', "CHOOSE(#{parent}!tp_type, False, False, True)")
      MaterialHelper.apply(top_panel, materials[:carcass])
      top_panel.layer = layers[:carcass] if layers && layers[:carcass]

      # Top Front Panel (stretcher at front edge)
      t = Geom::Transformation.new([t_cm.cm, 0, (h_cm - t_cm).cm])
      top_front = CabinetDC.add_child(defn, top, t, 'Top Front Panel')
      CabinetDC.da_attr(top_front, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(top_front, 'y',      "#{parent}!cab_depth - #{parent}!st_width")
      CabinetDC.da_attr(top_front, 'z',      "#{parent}!cab_height")
      CabinetDC.da_attr(top_front, 'lenx',   "#{parent}!cab_width - 2 * CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(top_front, 'leny',   "#{parent}!st_width")
      CabinetDC.da_attr(top_front, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(top_front, 'hidden', "CHOOSE(#{parent}!tp_type, True, False, True)")
      MaterialHelper.apply(top_front, materials[:carcass])
      top_front.layer = layers[:carcass] if layers && layers[:carcass]

      # ---- Back Panel ----
      t = Geom::Transformation.new([t_cm.cm, bp_sb_cm.cm, (h_cm - t_cm).cm])
      back_panel = CabinetDC.add_child(defn, back, t, 'Back Panel')
      CabinetDC.da_attr(back_panel, 'x',    "#{parent}!Thickness")
      CabinetDC.da_attr(back_panel, 'y',    "#{parent}!bp_setback")
      CabinetDC.da_attr(back_panel, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!tp_type, #{parent}!Thickness, #{parent}!Thickness, 0)")
      CabinetDC.da_attr(back_panel, 'lenx', "#{parent}!cab_width - 2 * #{parent}!Thickness")
      CabinetDC.da_attr(back_panel, 'leny', "#{parent}!bp_thickness")
      CabinetDC.da_attr(back_panel, 'lenz', "#{parent}!cab_height - (tp_present + bp_present) * #{parent}!Thickness - (#{parent}!Toekick * #{parent}!tk_height)")
      CabinetDC.da_attr(back_panel, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(back_panel, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")
      CabinetDC.da_attr(back_panel, 'hidden', "CHOOSE(#{parent}!bk_type, False, True, True)")
      MaterialHelper.apply(back_panel, materials[:carcass])
      back_panel.layer = layers[:carcass] if layers && layers[:carcass]

      # ---- Back Stretchers ----
      t = Geom::Transformation.new([t_cm.cm, bp_sb_cm.cm, (h_cm - t_cm).cm])
      back_stretcher = CabinetDC.add_child(defn, back, t, 'Back Stretcher')
      back.entities.each { |e| e.layer = layers[:carcass] if layers && layers[:carcass] }
      CabinetDC.da_attr(back_stretcher, 'x',          "#{parent}!Thickness")
      CabinetDC.da_attr(back_stretcher, 'y',          '0')
      CabinetDC.da_attr(back_stretcher, 'z',          "#{parent}!tk_height * #{parent}!Toekick + #{parent}!st_width + bp_present * #{parent}!Thickness + copy * spacing")
      CabinetDC.da_attr(back_stretcher, 'lenx',       "#{parent}!cab_width - 2 * #{parent}!Thickness")
      CabinetDC.da_attr(back_stretcher, 'leny',       "#{parent}!Thickness")
      CabinetDC.da_attr(back_stretcher, 'lenz',       "#{parent}!st_width")
      CabinetDC.da_attr(back_stretcher, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(back_stretcher, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")
      CabinetDC.da_attr(back_stretcher, 'spacing',    "IF(copies > 0, (#{parent}!cab_height - (tp_present + bp_present) * #{parent}!Thickness - (#{parent}!Toekick * #{parent}!tk_height) - #{parent}!st_width) / copies, 0)")
      CabinetDC.da_attr(back_stretcher, 'copies',     "#{parent}!bk_st_count - 1")
      CabinetDC.da_attr(back_stretcher, 'hidden',     "CHOOSE(#{parent}!bk_type, True, False, True)")
      MaterialHelper.apply(back_stretcher, materials[:carcass])
      back_stretcher.layer = layers[:carcass] if layers && layers[:carcass]

      # ---- Toe Kick / Legs ----
      if tk
        if params[:create_legs]
          leg_defn = CabinetDC.load_leg_definition(model, params[:legs_preset], tk_h_cm) if leg_defn.nil?
          leg_bounds = leg_defn.bounds
          leg_w = leg_bounds.width.to_cm
          leg_d = leg_bounds.height.to_cm
          leg_w_in = (leg_w / 2.54).round(6)
          leg_d_in = (leg_d / 2.54).round(6)
          half_w = leg_w / 2.0
          half_d = leg_d / 2.0
          half_w_in = (half_w / 2.54).round(6)
          half_d_in = (half_d / 2.54).round(6)

          # Front-Left Leg
          t = Geom::Transformation.new([(tk_sb_cm + half_w).cm, (d_cm - tk_sb_cm - half_d).cm, 0])
          fl_leg = CabinetDC.add_child(defn, leg_defn, t, 'Front Left Leg')
          CabinetDC.da_attr(fl_leg, 'x', "#{parent}!tk_setback + #{half_w_in}")
          CabinetDC.da_attr(fl_leg, 'y', "#{parent}!cab_depth - #{parent}!tk_setback - #{half_d_in}")
          CabinetDC.da_attr(fl_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(fl_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(fl_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(fl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          fl_leg.layer = layers[:legs] if layers && layers[:legs]
          fl_leg.transform!(Geom::Transformation.scaling(-1, 1, 1))

          # Front-Right Leg
          t = Geom::Transformation.new([(total_w_cm - tk_sb_cm - half_w).cm, (d_cm - tk_sb_cm - half_d).cm, 0])
          fr_leg = CabinetDC.add_child(defn, leg_defn, t, 'Front Right Leg')
          CabinetDC.da_attr(fr_leg, 'x', "#{parent}!cab_width - #{parent}!tk_setback - #{half_w_in}")
          CabinetDC.da_attr(fr_leg, 'y', "#{parent}!cab_depth - #{parent}!tk_setback - #{half_d_in}")
          CabinetDC.da_attr(fr_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(fr_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(fr_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(fr_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          fr_leg.layer = layers[:legs] if layers && layers[:legs]

          # Back-Left Leg
          t = Geom::Transformation.new([(tk_sb_cm + half_w).cm, (tk_sb_cm + half_d).cm, 0])
          bl_leg = CabinetDC.add_child(defn, leg_defn, t, 'Back Left Leg')
          CabinetDC.da_attr(bl_leg, 'x', "#{parent}!tk_setback + #{half_w_in}")
          CabinetDC.da_attr(bl_leg, 'y', "#{parent}!tk_setback + #{half_d_in}")
          CabinetDC.da_attr(bl_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(bl_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(bl_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(bl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          bl_leg.layer = layers[:legs] if layers && layers[:legs]
          bl_leg.transform!(Geom::Transformation.scaling(-1, -1, 1))

          # Back-Right Leg
          t = Geom::Transformation.new([(total_w_cm - tk_sb_cm - half_w).cm, (tk_sb_cm + half_d).cm, 0])
          br_leg = CabinetDC.add_child(defn, leg_defn, t, 'Back Right Leg')
          CabinetDC.da_attr(br_leg, 'x', "#{parent}!cab_width - #{parent}!tk_setback - #{half_w_in}")
          CabinetDC.da_attr(br_leg, 'y', "#{parent}!tk_setback + #{half_d_in}")
          CabinetDC.da_attr(br_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(br_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(br_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(br_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          br_leg.layer = layers[:legs] if layers && layers[:legs]
          br_leg.transform!(Geom::Transformation.scaling(1, -1, 1))
        else
          # Front
          t = Geom::Transformation.new([0, (d_cm - tk_sb_cm - t_cm).cm, tk_h_cm.cm])
          tkf = CabinetDC.add_child(defn, toekick_front, t, 'Toe Kick Front Panel')
          CabinetDC.da_attr(tkf, 'x',      "IF(#{parent}!toekick_flat_sides, CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness), #{parent}!tk_setback)")
          CabinetDC.da_attr(tkf, 'y',      "#{parent}!cab_depth - #{parent}!tk_setback - #{parent}!thickness")
          CabinetDC.da_attr(tkf, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(tkf, 'lenx',   "#{parent}!cab_width - IF(#{parent}!toekick_flat_sides, 0, 2 * #{parent}!tk_setback) - 2 * CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness)")
          CabinetDC.da_attr(tkf, 'leny',   "#{parent}!Thickness")
          CabinetDC.da_attr(tkf, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(tkf, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!bp_type, False, True), True)")

          # Left side
          t = Geom::Transformation.new([0, 0, tk_h_cm.cm])
          tkl = CabinetDC.add_child(defn, toekick_side, t, 'Toe Kick Side Left')
          CabinetDC.da_attr(tkl, 'x',      "IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(tkl, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(tkl, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(tkl, 'lenx',   "#{parent}!Thickness")
          CabinetDC.da_attr(tkl, 'leny',   "#{parent}!cab_depth - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, #{parent}!tk_setback, 2 * #{parent}!tk_setback)")
          CabinetDC.da_attr(tkl, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(tkl, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!sp_type, False, False, True), True)")

          # Right side
          t = Geom::Transformation.new([(total_w_cm - t_cm).cm, 0, tk_h_cm.cm])
          tkr = CabinetDC.add_child(defn, toekick_side, t, 'Toe Kick Side Right')
          CabinetDC.da_attr(tkr, 'x',      "#{parent}!cab_width - #{parent}!Thickness - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(tkr, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(tkr, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(tkr, 'lenx',   "#{parent}!Thickness")
          CabinetDC.da_attr(tkr, 'leny',   "#{parent}!cab_depth - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, #{parent}!tk_setback, 2 * #{parent}!tk_setback)")
          CabinetDC.da_attr(tkr, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(tkr, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!sp_type, False, False, True), True)")

          # Back
          t = Geom::Transformation.new([t_cm.cm, 0, tk_h_cm.cm])
          tkb = CabinetDC.add_child(defn, toekick_back, t, 'Toe Kick Back Panel')
          CabinetDC.da_attr(tkb, 'x',      "#{parent}!Thickness + IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(tkb, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(tkb, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(tkb, 'lenx',   "#{parent}!cab_width - 2 * #{parent}!Thickness - IF(#{parent}!toekick_flat_sides, 0, 2 * #{parent}!tk_setback)")
          CabinetDC.da_attr(tkb, 'leny',   "#{parent}!Thickness")
          CabinetDC.da_attr(tkb, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(tkb, 'hidden', "IF(#{parent}!Toekick, False, True)")

          # Apply panel material to toekick panels
          panel_mat = materials[:carcass]
          MaterialHelper.apply(tkf, panel_mat) if panel_mat
          MaterialHelper.apply(tkl, panel_mat) if panel_mat
          MaterialHelper.apply(tkr, panel_mat) if panel_mat
          MaterialHelper.apply(tkb, panel_mat) if panel_mat
          if layers && layers[:carcass]
            tkf.layer = layers[:carcass]
            tkl.layer = layers[:carcass]
            tkr.layer = layers[:carcass]
            tkb.layer = layers[:carcass]
          end
        end
      end

      # ---- Skirting Strip ----
      if tk && params[:skirting]
        skirting_defn ||= CabinetDC.make_panel(model, 'Skirting', total_w_cm, 0.3, tk_h_cm)
        skirting_thickness_in = (0.3 / 2.54).round(6)
        t = Geom::Transformation.new([0, (d_cm - tk_sb_cm).cm, 0])
        sk_inst = CabinetDC.add_child(defn, skirting_defn, t, 'Skirting')
        CabinetDC.da_attr(sk_inst, 'x',      "IF(#{parent}!toekick_flat_sides, CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness), #{parent}!tk_setback)")
        CabinetDC.da_attr(sk_inst, 'y',      "#{parent}!cab_depth - #{parent}!tk_setback")
        CabinetDC.da_attr(sk_inst, 'z',      "#{parent}!tk_height")
        CabinetDC.da_attr(sk_inst, 'lenx',   "#{parent}!cab_width - IF(#{parent}!toekick_flat_sides, 0, 2 * #{parent}!tk_setback) - 2 * CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness)")
        CabinetDC.da_attr(sk_inst, 'leny',   "#{skirting_thickness_in}")
        CabinetDC.da_attr(sk_inst, 'lenz',   "#{parent}!tk_height")
        CabinetDC.da_attr(sk_inst, 'hidden', "IF(#{parent}!Toekick, False, True)")
        MaterialHelper.apply(sk_inst, materials[:handle]) if materials[:handle]
        sk_inst.layer = layers[:carcass] if layers && layers[:carcass]
      end

      # ---- Groups (on accessible side only) ----
      grps_arr = grps.to_a
      prof_ext_max_in = 2.0 / 2.54
      grps_arr.each_with_index do |(id, v), idx|
        above_ext_in = t_in
        if idx > 0
          prev_gt = grps_arr[idx - 1][1][:gt].to_s
          if prev_gt == 'separator' || prev_gt == 'divider'
            above_ext_in = (grps_arr[idx - 1][1][:gh].to_f / 2.54) / 2.0
          elsif prev_gt == 'prof'
            above_ext_in = [(grps_arr[idx - 1][1][:gh].to_f / 2.54) / 2.0, prof_ext_max_in].min
          end
        end
        below_ext_in = t_in
        if idx < grps_arr.size - 1
          next_gt = grps_arr[idx + 1][1][:gt].to_s
          if next_gt == 'separator' || next_gt == 'divider'
            below_ext_in = (grps_arr[idx + 1][1][:gh].to_f / 2.54) / 2.0
          elsif next_gt == 'prof'
            below_ext_in = [(grps_arr[idx + 1][1][:gh].to_f / 2.54) / 2.0, prof_ext_max_in].min
          end
        end

        GroupDC.create_group(model, defn, "#{parent}", id,
          drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn,
          door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn,
          groups_count: grps.size,
          above_ext: above_ext_in, below_ext: below_ext_in,
          x_offset_in: acc_offset_in,
          materials: materials, layers: layers)
      end

      defn
    end

    # ================================================================
    # L-Shaped Corner — two wings meeting at 90 degrees.
    # Total footprint: (width + depth) in X, (width + depth) in Y.
    # One shared group spans the L interior (lazy-susan style).
    # ================================================================

    def self.build_l_shaped(model, parent_name, params, side, base, top, back,
                            toekick_front, toekick_side, toekick_back, leg_defn = nil,
                            drawer_face_defn: nil, door_leaf_defn: nil,
                            door_handle_defn: nil, drawer_handle_defn: nil, panel_face_defn: nil,
                            skirting_defn: nil, materials: {}, layers: nil, display_name: nil)
      defn = model.definitions.add(parent_name)
      defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
      defn.description = 'L-Shaped Corner Cabinet — ML Cabinets'

      # Destructure params
      w_cm     = params[:w_cm]   # wing opening width (symmetric both wings)
      h_cm     = params[:h_cm]
      d_cm     = params[:d_cm]   # depth of each wing
      t_cm     = params[:t_cm]
      bt_cm    = params[:bt_cm]
      bp_sb_cm = params[:bp_sb_cm]
      bk_type  = params[:bk_type]
      bk_st_cnt = params[:bk_st_cnt]
      tk       = params[:tk]
      fs       = params[:fs]
      fb       = params[:fb]
      tk_h_cm  = params[:tk_h_cm]
      tk_sb_cm = params[:tk_sb_cm]
      cl       = params[:cl]
      st_w_cm  = params[:st_w_cm]
      tp_type  = params[:tp_type]
      bp_type  = params[:bp_type]
      sp_type  = params[:sp_type]
      ov_type  = params[:ov_type]
      grps     = params[:grps]
      cab_type = params[:cab_type] || 'base-corner'

      # Total footprint dimensions
      total_x_cm = w_cm + d_cm  # total X extent (left wing width + right wing depth)
      total_y_cm = w_cm + d_cm  # total Y extent (symmetrical)

      # Convert to inches
      d_in      = d_cm.to_f / 2.54
      t_in      = t_cm.to_f / 2.54
      bt_in     = bt_cm.to_f / 2.54
      bp_sb_in  = bp_sb_cm.to_f / 2.54
      tk_h_in   = tk_h_cm.to_f / 2.54
      tk_sb_in  = tk_sb_cm.to_f / 2.54
      cl_in     = cl.to_f / 2.54
      st_w_in   = st_w_cm.to_f / 2.54
      tk_str    = tk ? 'True' : 'False'
      fs_str    = fs ? 'True' : 'False'
      fb_str    = fb ? 'True' : 'False'

      total_x_in = total_x_cm / 2.54
      total_y_in = total_y_cm / 2.54

      interior_h = h_cm - (tk ? tk_h_cm : 0.0) - 2.0 * t_cm
      # The shared L-shaped group uses w_cm as its interior width (one wing)
      interior_w = w_cm - 2.0 * t_cm

      fill_count  = grps.values.count { |v| v[:gh] == 0 }
      fixed_h_sum = grps.values.reject { |v| v[:gh] == 0 }.sum { |v| v[:gh] }
      fill_h      = fill_count > 0 ? (interior_h - fixed_h_sum) / fill_count : 0.0
      z_offset    = interior_h

      # Extract the maximum shelf count from items — L-shaped shelves are placed
      # directly on the cabinet definition, not inside the Group/Item hierarchy.
      l_shlvs_cnt = 0
      grps.each_value { |v| v[:items]&.each { |item| l_shlvs_cnt = [l_shlvs_cnt, item[:shlv].to_i].max } }

      # Extract the first door item — corner doors are placed directly on the cabinet.
      corner_door_data = nil
      grps.each_value do |v|
        v[:items]&.each do |item|
          if item[:it].to_s == 'door' && corner_door_data.nil?
            corner_door_data = item
          end
        end
      end

      entries = grps.map { |k, v|
        gh_cm = v[:gh] == 0 ? fill_h : v[:gh]
        gf    = v[:gh] == 0 ? 1 : 0
        z_offset -= gh_cm
        z_in  = z_offset / 2.54
        gh_in = gh_cm / 2.54
        gw_in = interior_w / 2.54
        hdn_part  = v[:hidden] ? ", :hdn=>1" : ""
        prid_part = (v[:gt].to_s == 'prof' && v[:prid] && !v[:prid].to_s.empty?) ? ", :prid=>#{v[:prid]}" : ""
        # Zero shlv in items so standard ShelfDC won't create rectangular shelves
        items_no_shlv = v[:items]&.map { |item| item.merge(shlv: 0) }
        "#{k}: {:gt=>#{v[:gt]}, :gz=>#{z_in.round(6)}, :gh=>#{gh_in.round(6)}, :gw=>#{gw_in.round(6)}, :gf=>#{gf}#{hdn_part}#{prid_part}, :it=>#{CabinetDC.serialize_items(items_no_shlv)}}"
      }
      groups_str = entries.join('; ')

      # ---- DC Attributes ----
      CabinetDC.da_attr(defn, 'thickness',           "#{t_in}",                'Panel Thickness',       'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'toekick',             "#{tk_str}",              'Toe Kick Enabled',      'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'toekick_flat_sides',  "#{fs_str}",              'Toe Kick Flat Sides',   'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'toekick_flat_back',   "#{fb_str}",              'Toe Kick Flat Back',    'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'tk_height',           "#{tk_h_in}",             'Toe Kick Height',       'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'tk_setback',          "#{tk_sb_in}",            'Toe Kick Setback',      'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bp_thickness',        "#{bt_in}",               'Back Panel Thickness',  'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bp_setback',          "#{bp_sb_in}",            'Back Panel Setback',    'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bk_type',             "#{bk_type}",             'Back Panel Type',       'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'bk_st_count',         "#{bk_st_cnt}",           'Back Stretchers Count', 'STRING',      'TEXTBOX')
      CabinetDC.da_attr(defn, 'groups',              "\"#{groups_str}\"",      'Groups',                'STRING',      'TEXTBOX')
      CabinetDC.da_attr(defn, 'clearance',           "#{cl_in}",               'Clearance',             'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'tp_type',             "#{tp_type}",             'Top Panel Type',        'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'st_width',            "#{st_w_in}",             'Stretcher Width',       'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'bp_type',             "#{bp_type}",             'Base Panel Type',       'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'sp_type',             "#{sp_type}",             'Side Panel Type',       'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'ov_type',             "#{ov_type}",             'Overlay Type',          'NUMBER',      'LIST')
      CabinetDC.da_attr(defn, 'wing_width',          "#{(w_cm / 2.54).round(6)}", 'Wing Width',        'CENTIMETERS', 'NONE')
      CabinetDC.da_attr(defn, 'wing_depth',          "#{d_in}",               'Wing Depth',           'CENTIMETERS', 'NONE')
      CabinetDC.da_attr(defn, 'l_shlvs_cnt',         "#{l_shlvs_cnt.to_s}",             'L-Shelf Count',     'STRING',      'TEXTBOX')

      # Cabinet master dimensions — stable custom attributes for child formulas
      CabinetDC.da_attr(defn, 'cab_width',  "#{total_x_in.round(6)}", 'Cabinet Width',  'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'cab_depth',  "#{total_y_in.round(6)}", 'Cabinet Depth',  'CENTIMETERS', 'TEXTBOX')
      l_h_in = (h_cm / 2.54).round(6)
      CabinetDC.da_attr(defn, 'cab_height', "#{l_h_in}",             'Cabinet Height', 'CENTIMETERS', 'TEXTBOX')
      CabinetDC.da_attr(defn, 'shlf_width', "cab_width - 2 * Thickness", 'Shelf Width', 'CENTIMETERS', 'NONE')
      CabinetDC.da_attr(defn, 'shlf_x',     "0",                         'Shelf X Offset', 'CENTIMETERS', 'NONE')

      defn.set_attribute(DA, 'name', parent_name)
      defn.set_attribute(DA, '_toekick_options', 'True = 1 & False = 0')
      defn.set_attribute(DA, '_toekick_flat_sides_options', 'True = 1 & False = 0')
      defn.set_attribute(DA, '_toekick_flat_back_options',  'True = 1 & False = 0')
      defn.set_attribute(DA, '_tp_type_options', 'Closed = 1 & Open = 2 & None = 3')
      defn.set_attribute(DA, '_sp_type_options', 'Inset = 1 & Overlay = 2 & Full Height = 3')
      defn.set_attribute(DA, '_bp_type_options', 'Closed = 1 & Open = 2')
      defn.set_attribute(DA, '_bk_type_options', 'Closed = 1 & Stretchers = 2 & None = 3')
      defn.set_attribute(DA, '_ov_type_options', 'Inset = 1 & Partial = 2 & Full = 3')

      defn.set_attribute('ml_cabinets', 'type',        cab_type)
      defn.set_attribute('ml_cabinets', 'corner_type', 'l-shaped')
      defn.set_attribute('ml_cabinets', 'hff_in',      (params[:hff_cm].to_f / 2.54).round(6))
      defn.set_attribute('ml_cabinets', 'version',     MLCabinets::VERSION)
      defn.set_attribute('ml_cabinets', 'cab_name',    display_name || parent_name)

      parent = defn.get_attribute(DA, 'name')

      # ---- L-Shaped geometry ----
      # Coordinate system:
      #   Origin = back-right corner of the bounding box.
      #   +X runs left, +Y runs forward (front), +Z runs up.
      #   The L-shape has:
      #     - Left wing:  X: 0 → total_x_cm,  Y: 0 → d_cm
      #     - Right wing: X: 0 → w_cm,  Y: 0 → total_y_cm
      #     - Corner junction: X: 0 → d_cm,  Y: 0 → d_cm (the overlapping square)
      #
      # Panel layout from user description:
      #   - 3 outer side panels (left wing front, right wing right, corner back)
      #   - 2 inner panels forming the L-notch
      #   - Back: one side = stretchers/back panel, other = full-width side panel
      #   - Top: L-shaped (2 strips + 2 stretchers per wing)
      #   - 2 separate base panels (one per wing)

      carcass_h = h_cm - (tk ? tk_h_cm : 0.0)
      carcass_z = tk ? tk_h_cm : 0.0

      # == 3 Outer Side Panels ==

      # Left wing — outer side panel
      left_wing_side_defn = CabinetDC.make_panel(model, 'LeftWingSidePanel', t_cm, d_cm, carcass_h)
      t = Geom::Transformation.new([0, 0, h_cm.cm])
      left_wing_side = CabinetDC.add_child(defn, left_wing_side_defn, t, 'Left Wing Side')
      CabinetDC.da_attr(left_wing_side, 'y',    "#{parent}!cab_depth - #{parent}!Thickness")
      CabinetDC.da_attr(left_wing_side, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(left_wing_side, 'lenx', "#{parent}!cab_width - #{parent}!wing_width")
      CabinetDC.da_attr(left_wing_side, 'leny', "#{parent}!Thickness")
      CabinetDC.da_attr(left_wing_side, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")
      CabinetDC.da_attr(left_wing_side, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(left_wing_side, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")

      # Right wing — outer side panel (at X = total_x, runs in Y for depth)
      right_wing_side_defn = CabinetDC.make_panel(model, 'RightWingSidePanel', t_cm, d_cm, carcass_h)
      t = Geom::Transformation.new([0, 0, h_cm.cm])
      right_wing_side = CabinetDC.add_child(defn, right_wing_side_defn, t, 'Right Wing Side')
      CabinetDC.da_attr(right_wing_side, 'x',    "#{parent}!cab_width - #{parent}!Thickness")
      CabinetDC.da_attr(right_wing_side, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(right_wing_side, 'lenx', "#{parent}!Thickness")
      CabinetDC.da_attr(right_wing_side, 'leny', "#{parent}!cab_depth - #{parent}!wing_width")
      CabinetDC.da_attr(right_wing_side, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")
      CabinetDC.da_attr(right_wing_side, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(right_wing_side, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")

      # # Corner back — the L-junction back wall (from back-left corner,
      # # runs diagonally to where inner panels meet — Y=0 to Y=d_cm, X=0)
      # # Actually: this is the left-back panel (X=0, Y: 0→d_cm)
      corner_back_defn = CabinetDC.make_panel(model, 'CornerBackPanel', t_cm, d_cm, carcass_h)
      t = Geom::Transformation.new([0, 0, h_cm.cm])
      corner_back = CabinetDC.add_child(defn, corner_back_defn, t, 'Corner Back Side')
      CabinetDC.da_attr(corner_back, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(corner_back, 'lenx', "#{parent}!Thickness")
      CabinetDC.da_attr(corner_back, 'leny', "#{parent}!cab_depth - #{parent}!Thickness")
      CabinetDC.da_attr(corner_back, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")
      CabinetDC.da_attr(corner_back, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(corner_back, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")

      # # == Back Panel / Stretchers (left wing back, at Y=0) ==
      # # Full-width back for the left wing (X: t_cm → total_x_cm - t_cm)
      left_back_w = total_x_cm - 2 * t_cm
      left_back_defn = CabinetDC.make_panel(model, 'LeftWingBackPanel', left_back_w, bt_cm, carcass_h - 2 * t_cm)
      t = Geom::Transformation.new([t_cm.cm, bp_sb_cm.cm, (h_cm - t_cm).cm])
      left_back = CabinetDC.add_child(defn, left_back_defn, t, 'Left Wing Back Panel')
      CabinetDC.da_attr(left_back, 'x',    "#{parent}!Thickness")
      CabinetDC.da_attr(left_back, 'y',    "#{parent}!bp_setback")
      CabinetDC.da_attr(left_back, 'z',    "#{parent}!cab_height - #{parent}!Thickness")
      CabinetDC.da_attr(left_back, 'lenx', "#{parent}!cab_width - 2 * #{parent}!Thickness")
      CabinetDC.da_attr(left_back, 'leny', "#{parent}!bp_thickness")
      CabinetDC.da_attr(left_back, 'lenz', "#{parent}!cab_height - 2 * #{parent}!Thickness - (#{parent}!Toekick * #{parent}!tk_height)")
      CabinetDC.da_attr(left_back, 'hidden', "CHOOSE(#{parent}!bk_type, False, True, True)")

      # # Back stretchers (left wing)
      left_str_defn = CabinetDC.make_panel(model, 'LeftWingStretcher', left_back_w, t_cm, st_w_cm)
      t = Geom::Transformation.new([t_cm.cm, 0, (h_cm - t_cm).cm])
      left_str = CabinetDC.add_child(defn, left_str_defn, t, 'Left Wing Stretcher')
      left_str_defn.entities.each { |e| e.layer = layers[:carcass] if layers && layers[:carcass] }
      CabinetDC.da_attr(left_str, 'x',          "#{parent}!Thickness")
      CabinetDC.da_attr(left_str, 'y',          '0')
      CabinetDC.da_attr(left_str, 'z',          "#{parent}!tk_height * #{parent}!Toekick + #{parent}!st_width + bp_present * #{parent}!Thickness + copy * spacing")
      CabinetDC.da_attr(left_str, 'lenx',       "#{parent}!cab_width - 2 * #{parent}!Thickness")
      CabinetDC.da_attr(left_str, 'leny',       "#{parent}!Thickness")
      CabinetDC.da_attr(left_str, 'lenz',       "#{parent}!st_width")
      CabinetDC.da_attr(left_str, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")
      CabinetDC.da_attr(left_str, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")
      CabinetDC.da_attr(left_str, 'spacing',    "IF(copies > 0, (#{parent}!cab_height - (tp_present + bp_present) * #{parent}!Thickness - (#{parent}!Toekick * #{parent}!tk_height) - #{parent}!st_width) / copies, 0)")
      CabinetDC.da_attr(left_str, 'copies',     "#{parent}!bk_st_count - 1")
      CabinetDC.da_attr(left_str, 'hidden',     "CHOOSE(#{parent}!bk_type, True, False, True)")

      # # ---- Toe Kick (L-shaped perimeter) ----
      leg_insts = []
      if tk
        if params[:create_legs]
          leg_defn = CabinetDC.load_leg_definition(model, params[:legs_preset], tk_h_cm) if leg_defn.nil?
          # Place four legs at corners, inset by tk_sb_cm from edges.
          # Leg origin is at the center of the object in X and Y,
          # so we offset by half the leg's width/depth.
          leg_bounds = leg_defn.bounds
          leg_w = leg_bounds.width.to_cm
          leg_d = leg_bounds.height.to_cm
          leg_w_in = (leg_w / 2.54).round(6)
          leg_d_in = (leg_d / 2.54).round(6)
          half_w = leg_w / 2.0
          half_d = leg_d / 2.0
          half_w_in = (half_w / 2.54).round(6)
          half_d_in = (half_d / 2.54).round(6)

          # Right Wing Front-Right Leg
          t = Geom::Transformation.new([(tk_sb_cm + half_w).cm, (d_cm - tk_sb_cm - half_d).cm, 0])
          rw_fr_leg = CabinetDC.add_child(defn, leg_defn, t, 'Right Wing Front Right Leg')
          CabinetDC.da_attr(rw_fr_leg, 'x', "#{parent}!tk_setback + #{half_w_in}")
          CabinetDC.da_attr(rw_fr_leg, 'y', "#{parent}!cab_depth - #{parent}!tk_setback - #{half_d_in}")
          CabinetDC.da_attr(rw_fr_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(rw_fr_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(rw_fr_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(rw_fr_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          # Mirror the leg for the left wing front leg
          mirror = Geom::Transformation.scaling(-1, 1, 1)
          rw_fr_leg.transform!(mirror)
          leg_insts << rw_fr_leg

          # Right Wing Front-Left Leg
          t = Geom::Transformation.new([(w_cm - tk_sb_cm - half_w).cm, (d_cm - tk_sb_cm - half_d).cm, 0])
          rw_fl_leg = CabinetDC.add_child(defn, leg_defn, t, 'Right Wing Front Left Leg')
          CabinetDC.da_attr(rw_fl_leg, 'x', "#{parent}!cab_width - #{parent}!wing_width - #{parent}!tk_setback - #{half_w_in}")
          CabinetDC.da_attr(rw_fl_leg, 'y', "#{parent}!cab_depth - #{parent}!tk_setback - #{half_d_in}")
          CabinetDC.da_attr(rw_fl_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(rw_fl_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(rw_fl_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(rw_fl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          leg_insts << rw_fl_leg

          # Back Corner Leg
          t = Geom::Transformation.new([(tk_sb_cm + half_w).cm, (tk_sb_cm + half_d).cm, 0])
          bc_leg = CabinetDC.add_child(defn, leg_defn, t, 'Back Corner Leg')
          CabinetDC.da_attr(bc_leg, 'x', "#{parent}!tk_setback + #{half_w_in}")
          CabinetDC.da_attr(bc_leg, 'y', "#{parent}!tk_setback + #{half_d_in}")
          CabinetDC.da_attr(bc_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(bc_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(bc_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(bc_leg, 'rotz', "180")
          CabinetDC.da_attr(bc_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          leg_insts << bc_leg

          # Left Wing Back Leg
          t = Geom::Transformation.new([(w_cm - tk_sb_cm - half_w).cm, (tk_sb_cm + half_d).cm, 0])
          lw_bl_leg = CabinetDC.add_child(defn, leg_defn, t, 'Left Wing Back Leg')
          CabinetDC.da_attr(lw_bl_leg, 'x', "#{parent}!cab_width - #{parent}!tk_setback - #{half_w_in}")
          CabinetDC.da_attr(lw_bl_leg, 'y', "#{parent}!tk_setback + #{half_d_in}")
          CabinetDC.da_attr(lw_bl_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(lw_bl_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(lw_bl_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(lw_bl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          # Mirror the leg for the right wing back leg
          mirror = Geom::Transformation.scaling(1, -1, 1)
          lw_bl_leg.transform!(mirror)
          leg_insts << lw_bl_leg

          # Left Wing Front Leg
          t = Geom::Transformation.new([(w_cm - tk_sb_cm - half_w).cm, (w_cm - tk_sb_cm - half_d).cm, 0])
          lw_fl_leg = CabinetDC.add_child(defn, leg_defn, t, 'Left Wing Front Leg')
          CabinetDC.da_attr(lw_fl_leg, 'x', "#{parent}!cab_width - #{parent}!tk_setback - #{half_w_in}")
          CabinetDC.da_attr(lw_fl_leg, 'y', "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!tk_setback - #{half_d_in}")
          CabinetDC.da_attr(lw_fl_leg, 'lenx', "#{leg_w_in}")
          CabinetDC.da_attr(lw_fl_leg, 'leny', "#{leg_d_in}")
          CabinetDC.da_attr(lw_fl_leg, 'lenz', "#{parent}!tk_height")
          CabinetDC.da_attr(lw_fl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          leg_insts << lw_fl_leg
        else
          # Left wing front
          t = Geom::Transformation.new([d_cm.cm, (d_cm - tk_sb_cm - t_cm).cm, tk_h_cm.cm])
          lw_tkf = CabinetDC.add_child(defn, toekick_front, t, 'Toe Kick Left Wing Front')
          CabinetDC.da_attr(lw_tkf, 'x',      "#{parent}!cab_width - #{parent}!wing_width - #{parent}!tk_setback - #{parent}!Thickness")
          CabinetDC.da_attr(lw_tkf, 'y',      "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!tk_setback - #{parent}!Thickness")
          CabinetDC.da_attr(lw_tkf, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(lw_tkf, 'lenx',   "#{parent}!wing_width + #{parent}!tk_setback + CHOOSE(#{parent}!sp_type, #{parent}!Thickness, #{parent}!Thickness, 0) - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tkf, 'leny',   "#{parent}!Thickness")
          CabinetDC.da_attr(lw_tkf, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(lw_tkf, 'hidden', "IF(#{parent}!Toekick, False, True)")

          # Right wing front
          t = Geom::Transformation.new([(d_cm - tk_sb_cm - t_cm).cm, d_cm.cm, tk_h_cm.cm])
          rw_tkf = CabinetDC.add_child(defn, toekick_front, t, 'Toe Kick Right Wing Front')
          CabinetDC.da_attr(rw_tkf, 'x',      "#{parent}!cab_width - #{parent}!wing_width - #{parent}!tk_setback - #{parent}!Thickness")
          CabinetDC.da_attr(rw_tkf, 'y',      "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!tk_setback")
          CabinetDC.da_attr(rw_tkf, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(rw_tkf, 'lenx',   "#{parent}!Thickness")
          CabinetDC.da_attr(rw_tkf, 'leny',   "#{parent}!wing_width + #{parent}!tk_setback - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback) - CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness)")
          CabinetDC.da_attr(rw_tkf, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(rw_tkf, 'hidden', "IF(#{parent}!Toekick, False, True)")

          # Left wing side
          t = Geom::Transformation.new([(total_x_cm - t_cm).cm, tk_sb_cm.cm, tk_h_cm.cm])
          lw_tks = CabinetDC.add_child(defn, toekick_side, t, 'Toe Kick Left Wing Side')
          CabinetDC.da_attr(lw_tks, 'x',      "#{parent}!cab_width - #{parent}!Thickness - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tks, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tks, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(lw_tks, 'lenx',   "#{parent}!Thickness")
          CabinetDC.da_attr(lw_tks, 'leny',   "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, #{parent}!tk_setback, 2 * #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tks, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(lw_tks, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!sp_type, False, False, True), True)")

          # Right wing side
          t = Geom::Transformation.new([tk_sb_cm.cm, (total_y_cm - t_cm).cm, tk_h_cm.cm])
          rw_tks = CabinetDC.add_child(defn, toekick_side, t, 'Toe Kick Right Wing Side')
          CabinetDC.da_attr(rw_tks, 'x',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(rw_tks, 'y',      "#{parent}!cab_depth - #{parent}!Thickness - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(rw_tks, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(rw_tks, 'lenx',   "#{parent}!cab_width - #{parent}!wing_width - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, #{parent}!tk_setback, 2 * #{parent}!tk_setback)}")
          CabinetDC.da_attr(rw_tks, 'leny',   "#{parent}!Thickness")
          CabinetDC.da_attr(rw_tks, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(rw_tks, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!sp_type, False, False, True), True)")

          # Left wing back (along Y=0 wall)
          t = Geom::Transformation.new([t_cm.cm, tk_sb_cm.cm, tk_h_cm.cm])
          lw_tkb = CabinetDC.add_child(defn, toekick_back, t, 'Toe Kick Left Wing Back')
          CabinetDC.da_attr(lw_tkb, 'x',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tkb, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tkb, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(lw_tkb, 'lenx',   "#{parent}!cab_width - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback) - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(lw_tkb, 'leny',   "#{parent}!Thickness")
          CabinetDC.da_attr(lw_tkb, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(lw_tkb, 'hidden', "IF(#{parent}!Toekick, False, True)")

          # Right wing back (along X=0 wall)
          t = Geom::Transformation.new([tk_sb_cm.cm, tk_sb_cm.cm, tk_h_cm.cm])
          rw_tkb = CabinetDC.add_child(defn, toekick_back, t, 'Toe Kick Right Wing Back')
          CabinetDC.da_attr(rw_tkb, 'x',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(rw_tkb, 'y',      "#{parent}!Thickness + IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(rw_tkb, 'z',      "#{parent}!tk_height")
          CabinetDC.da_attr(rw_tkb, 'lenx',   "#{parent}!Thickness")
          CabinetDC.da_attr(rw_tkb, 'leny',   "#{parent}!cab_depth - 2 * #{parent}!Thickness - IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback) - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          CabinetDC.da_attr(rw_tkb, 'lenz',   "#{parent}!tk_height")
          CabinetDC.da_attr(rw_tkb, 'hidden', "IF(#{parent}!Toekick, False, True)")
          if layers && layers[:carcass]
            lw_tkf.layer = layers[:carcass]
            rw_tkf.layer = layers[:carcass]
            lw_tks.layer = layers[:carcass]
            rw_tks.layer = layers[:carcass]
            lw_tkb.layer = layers[:carcass]
            rw_tkb.layer = layers[:carcass]
          end
        end
      end

      # ---- Skirting Strips (one per wing front face) ----
      if tk && params[:skirting]
        skirting_defn ||= CabinetDC.make_panel(model, 'Skirting', w_cm, 0.3, tk_h_cm)
        skirting_thickness_in = (0.3 / 2.54).round(6)

        # Left wing front skirting (faces Y = d_cm, spans the left wing width)
        t = Geom::Transformation.new([d_cm.cm, (d_cm - tk_sb_cm).cm, 0])
        lw_sk = CabinetDC.add_child(defn, skirting_defn, t, 'Skirting Left Wing')
        CabinetDC.da_attr(lw_sk, 'x',      "#{parent}!cab_width - #{parent}!wing_width - #{parent}!tk_setback - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
        CabinetDC.da_attr(lw_sk, 'y',      "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!tk_setback")
        CabinetDC.da_attr(lw_sk, 'z',      "#{parent}!tk_height")
        CabinetDC.da_attr(lw_sk, 'lenx',   "#{parent}!wing_width + #{parent}!tk_setback - CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness) - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
        CabinetDC.da_attr(lw_sk, 'leny',   "#{skirting_thickness_in}")
        CabinetDC.da_attr(lw_sk, 'lenz',   "#{parent}!tk_height")
        CabinetDC.da_attr(lw_sk, 'hidden', "IF(#{parent}!Toekick, False, True)")
        MaterialHelper.apply(lw_sk, materials[:handle]) if materials[:handle]
        lw_sk.layer = layers[:carcass] if layers && layers[:carcass]

        # Right wing front skirting (faces X = d_cm, spans the right wing depth)
        t = Geom::Transformation.new([(d_cm - tk_sb_cm).cm, d_cm.cm, 0])
        rw_sk = CabinetDC.add_child(defn, skirting_defn, t, 'Skirting Right Wing')
        CabinetDC.da_attr(rw_sk, 'x',      "#{parent}!cab_width - #{parent}!wing_width - #{parent}!tk_setback")
        CabinetDC.da_attr(rw_sk, 'y',      "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!tk_setback + #{skirting_thickness_in} - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
        CabinetDC.da_attr(rw_sk, 'z',      "#{parent}!tk_height")
        CabinetDC.da_attr(rw_sk, 'lenx',   "#{skirting_thickness_in}")
        CabinetDC.da_attr(rw_sk, 'leny',   "#{parent}!wing_width + #{parent}!tk_setback - #{skirting_thickness_in} - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback) - CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness)")
        CabinetDC.da_attr(rw_sk, 'lenz',   "#{parent}!tk_height")
        CabinetDC.da_attr(rw_sk, 'hidden', "IF(#{parent}!Toekick, False, True)")
        MaterialHelper.apply(rw_sk, materials[:handle]) if materials[:handle]
        rw_sk.layer = layers[:carcass] if layers && layers[:carcass]
      end

      # == 2 Base Panels (one per wing) ==

      # Left wing base (X: t_cm → total_x_cm - t_cm, Y: 0 → d_cm - t_cm)
      lw_base_w = total_x_cm - 2 * t_cm
      lw_base_d = d_cm
      lw_base_defn = CabinetDC.make_panel(model, 'LeftWingBase', lw_base_w, lw_base_d, t_cm)
      t = Geom::Transformation.new([t_cm.cm, 0, (carcass_z + t_cm).cm])
      lw_base = CabinetDC.add_child(defn, lw_base_defn, t, 'Left Wing Base')
      CabinetDC.da_attr(lw_base, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(lw_base, 'z',      "(#{parent}!Toekick * #{parent}!tk_height) + #{parent}!Thickness")
      CabinetDC.da_attr(lw_base, 'lenx',   "#{parent}!cab_width - CHOOSE(#{parent}!sp_type, 0, 2 * #{parent}!Thickness, 2 * #{parent}!Thickness)")
      CabinetDC.da_attr(lw_base, 'leny',   "#{parent}!cab_depth - #{parent}!wing_width")
      CabinetDC.da_attr(lw_base, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(lw_base, 'hidden', "CHOOSE(#{parent}!bp_type, False, True)")

      # Right wing base (X: 0 → d_cm, Y: d_cm → total_y_cm)
      rw_base_w = d_cm
      rw_base_d = w_cm - t_cm
      rw_base_defn = CabinetDC.make_panel(model, 'RightWingBase', rw_base_w, rw_base_d, t_cm)
      t = Geom::Transformation.new([t_cm.cm, d_cm.cm, (carcass_z + t_cm).cm])
      rw_base = CabinetDC.add_child(defn, rw_base_defn, t, 'Right Wing Base')
      CabinetDC.da_attr(rw_base, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(rw_base, 'y',      "#{parent}!cab_depth - #{parent}!wing_width")
      CabinetDC.da_attr(rw_base, 'z',      "(#{parent}!Toekick * #{parent}!tk_height) + #{parent}!Thickness")
      CabinetDC.da_attr(rw_base, 'lenx',   "#{parent}!cab_depth - #{parent}!wing_width - CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(rw_base, 'leny',   "#{parent}!wing_width - CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(rw_base, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(rw_base, 'hidden', "CHOOSE(#{parent}!bp_type, False, True)")

      # == Top Panels (L-shaped: 2 stretchers per wing side) ==

      # Left wing top (back stretcher at Y=0 side)
      lw_top_defn = CabinetDC.make_panel(model, 'LeftWingTop', total_x_cm - 2 * t_cm, st_w_cm, t_cm)
      t = Geom::Transformation.new([t_cm.cm, 0, (h_cm - t_cm).cm])
      lw_top = CabinetDC.add_child(defn, lw_top_defn, t, 'Left Wing Top Back')
      CabinetDC.da_attr(lw_top, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(lw_top, 'z',      "#{parent}!cab_height")
      CabinetDC.da_attr(lw_top, 'lenx',   "#{parent}!cab_width - CHOOSE(#{parent}!sp_type, 0, 2 * #{parent}!Thickness, 2 * #{parent}!Thickness)")
      CabinetDC.da_attr(lw_top, 'leny',   "CHOOSE(#{parent}!tp_type, #{parent}!cab_depth - #{parent}!wing_width, #{parent}!st_width, #{parent}!st_width)")
      CabinetDC.da_attr(lw_top, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(lw_top, 'hidden', "CHOOSE(#{parent}!tp_type, False, False, True)")

      # Left wing top front stretcher (at Y=d_cm inner edge)
      lw_top_front_defn = CabinetDC.make_panel(model, 'LeftWingTopFront', total_x_cm - 2 * t_cm, st_w_cm, t_cm)
      t = Geom::Transformation.new([t_cm.cm, (d_cm - st_w_cm).cm, (h_cm - t_cm).cm])
      lw_top_front = CabinetDC.add_child(defn, lw_top_front_defn, t, 'Left Wing Top Front')
      CabinetDC.da_attr(lw_top_front, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(lw_top_front, 'y',      "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!st_width")
      CabinetDC.da_attr(lw_top_front, 'z',      "#{parent}!cab_height")
      CabinetDC.da_attr(lw_top_front, 'lenx',   "#{parent}!cab_width - CHOOSE(#{parent}!sp_type, 0, 2 * #{parent}!Thickness, 2 * #{parent}!Thickness)")
      CabinetDC.da_attr(lw_top_front, 'leny',   "#{parent}!st_width")
      CabinetDC.da_attr(lw_top_front, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(lw_top_front, 'hidden', "CHOOSE(#{parent}!tp_type, True, False, True)")

      # Right wing top (at X=0 side, left stretcher)
      rw_top_defn = CabinetDC.make_panel(model, 'RightWingTop', st_w_cm, w_cm - t_cm, t_cm)
      t = Geom::Transformation.new([t_cm.cm, (d_cm + t_cm).cm, (h_cm - t_cm).cm])
      rw_top = CabinetDC.add_child(defn, rw_top_defn, t, 'Right Wing Top Back')
      CabinetDC.da_attr(rw_top, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      CabinetDC.da_attr(rw_top, 'y',      "#{parent}!cab_depth - #{parent}!wing_width")
      CabinetDC.da_attr(rw_top, 'z',      "#{parent}!cab_height")
      CabinetDC.da_attr(rw_top, 'lenx',   "CHOOSE(#{parent}!tp_type, #{parent}!cab_depth - #{parent}!wing_width - #{parent}!Thickness, #{parent}!st_width, #{parent}!st_width)")
      CabinetDC.da_attr(rw_top, 'leny',   "#{parent}!wing_width - #{parent}!Thickness + CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(rw_top, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(rw_top, 'hidden', "CHOOSE(#{parent}!tp_type, False, False, True)")

      # Right wing top front stretcher (at X = d_cm inner edge)
      rw_top_front_defn = CabinetDC.make_panel(model, 'RightWingTopFront', st_w_cm, w_cm - t_cm, t_cm)
      t = Geom::Transformation.new([(d_cm - st_w_cm).cm, (d_cm + t_cm).cm, (h_cm - t_cm).cm])
      rw_top_front = CabinetDC.add_child(defn, rw_top_front_defn, t, 'Right Wing Top Front')
      CabinetDC.da_attr(rw_top_front, 'x',      "#{parent}!cab_depth - #{parent}!wing_width - #{parent}!st_width")
      CabinetDC.da_attr(rw_top_front, 'y',      "#{parent}!cab_depth - #{parent}!wing_width")
      CabinetDC.da_attr(rw_top_front, 'z',      "#{parent}!cab_height")
      CabinetDC.da_attr(rw_top_front, 'lenx',   "#{parent}!st_width")
      CabinetDC.da_attr(rw_top_front, 'leny',   "#{parent}!wing_width - #{parent}!Thickness + CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")
      CabinetDC.da_attr(rw_top_front, 'lenz',   "#{parent}!Thickness")
      CabinetDC.da_attr(rw_top_front, 'hidden', "CHOOSE(#{parent}!tp_type, True, False, True)")

      # Apply panel material to all structural panel instances
      if materials[:carcass]
        defn.entities.grep(Sketchup::ComponentInstance).each do |ci|
          next if ci.name.start_with?('Skirting')
          MaterialHelper.apply(ci, materials[:carcass])
        end
      end
      # Assign carcass layer to all instances built so far, then override legs
      if layers && layers[:carcass]
        defn.entities.grep(Sketchup::ComponentInstance).each do |ci|
          ci.layer = layers[:carcass]
        end
      end
      if layers && layers[:legs]
        leg_insts.each { |li| li.layer = layers[:legs] }
      end

      # ---- L-shaped shelves placed directly on the cabinet definition ----
      if l_shlvs_cnt > 0
        l_shelf_defn = make_l_shelf_defn(model)
        shelf_insts = place_l_shelves(defn, l_shelf_defn, parent)
        if shelf_insts
          shelf_insts.each { |si| MaterialHelper.apply(si, materials[:carcass]) }
          shelf_insts.each { |si| si.layer = layers[:carcass] if layers && layers[:carcass] }
        end
      end

      # ---- Corner doors placed directly on the cabinet definition ----
      if corner_door_data && door_leaf_defn
        abs_z_in_corner = ((params[:hff_cm].to_f / 2.54) + (tk ? tk_h_in : 0.0) + t_in).round(6)
        place_corner_doors(defn, door_leaf_defn, door_handle_defn, parent, corner_door_data, abs_z_in: abs_z_in_corner, materials: materials, layers: layers)
      end

      defn
    end

    # ================================================================
    # Create a simple placeholder component definition for L-shelves.
    # The DC engine resizes the instance via lenx/leny/lenz attributes.
    # ================================================================
    def self.make_l_shelf_defn(model)
      defn = model.definitions.add('LShelf')
      defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
      w    = 1.cm
      face = defn.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, w, 0),
        Geom::Point3d.new(0, w, 0)
      )
      face.pushpull(-w)
      defn.set_attribute(DA, 'name',         'LShelf')
      defn.set_attribute(DA, '_name_access', 'NONE')
      defn
    end

    # ================================================================
    # Place two shelf instances (right wing + left wing) inside the
    # cabinet definition. Both share the same spacing/z/copies formulas
    # so every shelf level has an aligned pair forming the L-shape.
    # ================================================================
    def self.place_l_shelves(cabinet_defn, shelf_defn, parent)
      rw = cabinet_defn.entities.add_instance(shelf_defn, Geom::Transformation.new([0, 0, 0]))
      rw.name = 'L-Shelf Right Wing'
      lw = cabinet_defn.entities.add_instance(shelf_defn, Geom::Transformation.new([0, 0, 0]))
      lw.name = 'L-Shelf Left Wing'

      # Shared vertical distribution formulas (same for both pieces)
      p              = parent
      spacing_f      = "IF(#{p}!l_shlvs_cnt > 0, (#{p}!cab_height - 2 * #{p}!Thickness - #{p}!Toekick * #{p}!tk_height - #{p}!l_shlvs_cnt * #{p}!Thickness) / (#{p}!l_shlvs_cnt + 1), 0)"
      z_f            = "#{p}!Toekick * #{p}!tk_height + #{p}!Thickness + spacing + copy * (spacing + #{p}!Thickness)"
      copies_f       = "IF(#{p}!l_shlvs_cnt > 0, #{p}!l_shlvs_cnt - 1, 0)"
      hidden_f       = "IF(#{p}!l_shlvs_cnt > 0, False, True)"
      back_offset_f  = "CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!Thickness, 0)"

      [rw, lw].each do |inst|
        CabinetDC.da_attr(inst, 'spacing', spacing_f)
        CabinetDC.da_attr(inst, 'z',       z_f)
        CabinetDC.da_attr(inst, 'lenz',    "#{p}!Thickness")
        CabinetDC.da_attr(inst, 'copies',  copies_f)
        CabinetDC.da_attr(inst, 'hidden',  hidden_f)
      end

      # Right wing piece: full cabinet X width, right-wing Y depth
      CabinetDC.da_attr(rw, 'x',    "#{p}!Thickness")
      CabinetDC.da_attr(rw, 'y',    "#{back_offset_f} + #{p}!clearance")
      CabinetDC.da_attr(rw, 'lenx', "#{p}!cab_width - 2 * #{p}!Thickness")
      CabinetDC.da_attr(rw, 'leny', "#{p}!cab_depth - #{p}!wing_width - #{back_offset_f} - #{p}!clearance")

      # Left wing piece: left-wing X depth, left-wing Y extent (starts at inner junction)
      CabinetDC.da_attr(lw, 'x',    "#{p}!Thickness")
      CabinetDC.da_attr(lw, 'y',    "#{p}!cab_depth - #{p}!wing_width")
      CabinetDC.da_attr(lw, 'lenx', "#{p}!cab_width - #{p}!wing_width - #{p}!Thickness")
      CabinetDC.da_attr(lw, 'leny', "#{p}!wing_width - #{p}!Thickness")

      [rw, lw]
    end

    # ================================================================
    # Place two perpendicular corner door leaves directly on the
    # cabinet definition — one on the front of each wing:
    #   Right wing door: faces +Y at Y = LenY - wing_width
    #   Left wing door:  faces +X at X = LenX - wing_width (rotz = -90°)
    # Opens toward the interior / counter area of the kitchen.
    #
    # Each door leaf is wrapped in a unique CornerDoorLeaf* definition
    # so that the loaded panel preset's sub-components can resolve their
    # parent-reference formulas (ParentName!lenx etc.) correctly — the
    # same pattern used by DoorLeafDC.create_door_leaf.
    # ================================================================
    def self.place_corner_doors(cabinet_defn, door_leaf_defn, door_handle_defn, parent, door_data, abs_z_in: 0.0, materials: {}, layers: nil)
      return unless door_leaf_defn
      p = parent
      model = cabinet_defn.model || Sketchup.active_model

      hoff  = (door_data[:hoff]  || 0).to_f.round(6)
      voff  = (door_data[:voff]  || 0).to_f.round(6)
      hrot  = (door_data[:hrot]  || 0).to_f.round(3)

      # Shared vertical formulas (identical for both wing doors)
      z_f    = "#{p}!Toekick * #{p}!tk_height + CHOOSE(#{p}!ov_type, #{p}!Thickness + #{p}!clearance, #{p}!clearance, 0)"
      lenz_f = "#{p}!cab_height - #{p}!Toekick * #{p}!tk_height + CHOOSE(#{p}!ov_type, -2 * (#{p}!Thickness + #{p}!clearance), -2 * #{p}!clearance, 0)"
      # Width formula: one wing opening = wing_width - Thickness (inner junction to side panel)
      lenx_f = "#{p}!wing_width - CHOOSE(#{p}!ov_type, #{p}!Thickness + #{p}!clearance, #{p}!Thickness + #{p}!clearance, #{p}!Thickness)"

      # ---- Left Wing Door wrapper (standard orientation: door face normal = +Y) ----
      lw_wrapper_defn = model.definitions.add('CornerDoorLeafLW')
      lw_wrapper_defn.description = 'Corner Door Leaf DC — ML Cabinets'
      lw_wrapper_defn.set_attribute(DA, 'name',         'CornerDoorLeafLW')
      lw_wrapper_defn.set_attribute(DA, '_name_access', 'NONE')

      lw_panel = lw_wrapper_defn.entities.add_instance(door_leaf_defn, Geom::Transformation.new([0, 0, 0]))
      lw_panel.name = 'CornerDoorLeafPanel'
      CabinetDC.da_attr(lw_panel, 'lenx', 'CornerDoorLeafLW!lenx')
      CabinetDC.da_attr(lw_panel, 'leny', 'CornerDoorLeafLW!leny')
      CabinetDC.da_attr(lw_panel, 'lenz', 'CornerDoorLeafLW!lenz')

      lwd = cabinet_defn.entities.add_instance(lw_wrapper_defn, Geom::Transformation.new([0, 0, 0]))
      lwd.name = 'CornerDoorLeafLW'
      CabinetDC.da_attr(lwd, 'x',    "#{p}!cab_width - #{p}!wing_width + CHOOSE(#{p}!ov_type, 0, #{p}!Thickness, #{p}!Thickness)")
      CabinetDC.da_attr(lwd, 'y',    "#{p}!cab_depth - #{p}!wing_width - CHOOSE(#{p}!ov_type, #{p}!Thickness, 0, 0)")
      CabinetDC.da_attr(lwd, 'z',    z_f)
      CabinetDC.da_attr(lwd, 'lenx', lenx_f)
      CabinetDC.da_attr(lwd, 'leny', "#{p}!Thickness")
      CabinetDC.da_attr(lwd, 'lenz', lenz_f)

      # ---- Right Wing Door wrapper (rotz = -90°: door face normal = +X) ----
      rw_wrapper_defn = model.definitions.add('CornerDoorLeafRW')
      rw_wrapper_defn.description = 'Corner Door Leaf DC — ML Cabinets'
      rw_wrapper_defn.set_attribute(DA, 'name',         'CornerDoorLeafRW')
      rw_wrapper_defn.set_attribute(DA, '_name_access', 'NONE')

      rw_panel = rw_wrapper_defn.entities.add_instance(door_leaf_defn, Geom::Transformation.new([0, 0, 0]))
      rw_panel.name = 'CornerDoorLeafPanel'
      CabinetDC.da_attr(rw_panel, 'lenx', 'CornerDoorLeafRW!lenx')
      CabinetDC.da_attr(rw_panel, 'leny', 'CornerDoorLeafRW!leny')
      CabinetDC.da_attr(rw_panel, 'lenz', 'CornerDoorLeafRW!lenz')

      rot = Geom::Transformation.rotation(ORIGIN, Z_AXIS, -90.degrees)
      rwd = cabinet_defn.entities.add_instance(rw_wrapper_defn, rot)
      rwd.name = 'CornerDoorLeafRW'
      CabinetDC.da_attr(rwd, 'rotz', '-90', 'Rotation Z', 'DEGREES', 'NONE')
      CabinetDC.da_attr(rwd, 'x',    "#{p}!cab_width - #{p}!wing_width - CHOOSE(#{p}!ov_type, #{p}!Thickness, 0, 0)")
      CabinetDC.da_attr(rwd, 'y',    "#{p}!cab_depth - CHOOSE(#{p}!ov_type,#{p}!Thickness + #{p}!clearance, #{p}!clearance, 0)")
      CabinetDC.da_attr(rwd, 'z',    z_f)
      CabinetDC.da_attr(rwd, 'lenx', lenx_f)
      CabinetDC.da_attr(rwd, 'leny', "#{p}!Thickness")
      CabinetDC.da_attr(rwd, 'lenz', lenz_f)

      # ---- Indication lines ----
      if layers
        indication_layer = layers[:indications]
        lw_dsub = door_data[:dsub].to_s
        lw_dsub = 'door-hinge-left' if lw_dsub.empty?
        rw_dsub = case lw_dsub
                  when 'door-hinge-left'  then 'door-hinge-right'
                  when 'door-hinge-right' then 'door-hinge-right'
                  else 'door-hinge-right'
                  end
        DoorLeafDC.add_indication_lines(model, lw_wrapper_defn, 'CornerDoorLeafLW', lw_dsub, indication_layer)
        DoorLeafDC.add_indication_lines(model, rw_wrapper_defn, 'CornerDoorLeafRW', rw_dsub, indication_layer)
      end

      # ---- Handles ----
      # Handles are placed INSIDE the LW wrapper definition only — the LW door
      # is the user-facing leaf that gets grabbed to open both wings together.
      # hoff/voff are exposed as DA attrs on the wrapper instance so child handle
      # formulas (CornerDoorLeafLW!hdl_hoff, etc.) can resolve them.
      ldh = nil
      rdh = nil
      if door_handle_defn
        dsub = door_data[:dsub].to_s
        dsub = 'door-hinge-left' if dsub.empty?

        # Expose hoff/voff (cm, CENTIMETERS units) on the LW wrapper instance
        # for child handle formulas. SketchUp DC converts cm→inches in evaluation.
        CabinetDC.da_attr(lwd, 'hdl_hoff', hoff.to_s, nil, 'CENTIMETERS')
        CabinetDC.da_attr(lwd, 'hdl_voff', voff.to_s, nil, 'CENTIMETERS')
        CabinetDC.da_attr(lwd, 'hdl_rot',  hrot.to_s, nil, 'DEGREES')

        ldh = HandleDC.create_door_handle_in_leaf(
          model, lw_wrapper_defn, 'CornerDoorLeafLW', door_handle_defn,
          door_sub: dsub, abs_z_in: abs_z_in
        )
      end

      # ---- Mark corner door instances so tools can detect them ----
      # Tools (OpenCloseTool, SwapGrainTool, ApplyPresetTool) require either
      # a DoorLeaf* wrapper inside an Item hierarchy, or these marker attributes
      # on direct-child-of-cabinet door instances.
      dsub_str = door_data[:dsub].to_s
      oa_val   = door_data[:oa].to_f.to_s

      if lwd
        lwd.set_attribute('ml_cabinets', 'corner_door', 'lw')
        lwd.set_attribute(DA, 'i_type',   'door')
        lwd.set_attribute(DA, 'door_sub', dsub_str.empty? ? 'door-hinge-left' : dsub_str)
        lwd.set_attribute(DA, 'oa',       oa_val)
      end
      if rwd
        rwd.set_attribute('ml_cabinets', 'corner_door', 'rw')
        rwd.set_attribute(DA, 'i_type',   'door')
        # Right wing is rotated -90° around Z — flip left/right hinge so the
        # visual pivot is on the correct side (inner corner for single hinge).
        rwd_dsub = case dsub_str
                   when 'door-hinge-left'  then 'door-hinge-right'
                   when 'door-hinge-right' then 'door-hinge-left'
                   else dsub_str.empty? ? 'door-hinge-right' : dsub_str
                   end
        rwd.set_attribute(DA, 'door_sub', rwd_dsub)
        rwd.set_attribute(DA, 'oa',       oa_val)
      end

      # ---- Apply materials to the panel instances (not the wrappers) ----
      MaterialHelper.apply(lw_panel, materials[:door], glass_material: materials[:glass], metal_material: materials[:handle]) if lw_panel
      MaterialHelper.apply(rw_panel, materials[:door], glass_material: materials[:glass], metal_material: materials[:handle]) if rw_panel
      MaterialHelper.apply(ldh, materials[:handle]) if ldh
      MaterialHelper.apply(rdh, materials[:handle]) if rdh
      # ---- Assign layers ----
      if layers
        lwd.layer = layers[:doors]   if lwd && layers[:doors]
        rwd.layer = layers[:doors]   if rwd && layers[:doors]
        ldh.layer = layers[:handles] if ldh && layers[:handles]
        rdh.layer = layers[:handles] if rdh && layers[:handles]
      end

      [rwd, lwd]
    end

  end # module CornerCabinetDC
end # module MLCabinets
