module MLCabinets
  module CabinetDC

    # Default cabinet dimensions (cm). Guarded for hot-reload safety.
    W_CM      = 60.0  unless defined?(W_CM)       # width
    H_CM      = 90.0  unless defined?(H_CM)       # height
    D_CM      = 58.0  unless defined?(D_CM)       # depth
    T_CM      = 1.8   unless defined?(T_CM)       # panel thickness
    BT_CM     = 0.8   unless defined?(BT_CM)      # back panel thickness
    BP_SB_CM  = 2.0   unless defined?(BP_SB_CM)   # back panel setback from bottom edge
    BK_TYPE   = 1     unless defined?(BK_TYPE)    # Type of back panel: '1 = closed' or '2 = stretchers' or '3 = none'
    BK_ST_CNT = 2     unless defined?(BK_ST_CNT)  # Number of stretchers if back panel type is 'stretchers'
    TK        = true  unless defined?(TK)         # whether to include a toe kick panel at all
    FS        = true  unless defined?(FS)         # flat sides toe kick
    FB        = true  unless defined?(FB)         # flat back toe kick
    TK_H_CM   = 10.0  unless defined?(TK_H_CM)    # toe kick height
    TK_SB_CM  = 5.0   unless defined?(TK_SB_CM)   # toe kick setback from front edge
    CL        = 0.1   unless defined?(CL)         # Clearance
    ST_W_CM   = 7.0   unless defined?(ST_W_CM)    # Stretcher width (if top panel type is 'open')
    TP_TYPE   = 1     unless defined?(TP_TYPE)    # Type of top panel: '1 = closed', '2 = open' or '3 = none'
    BP_TYPE   = 1     unless defined?(BP_TYPE)    # Type of base panel: '1 = closed' or '2 = open'
    SP_TYPE   = 2     unless defined?(SP_TYPE)    # Type of side panel: '1 = inset', '2 = overlay' or '3 = full height'
    OV_TYPE   = 3     unless defined?(OV_TYPE)    # Overlay type for doors/drawers: '1 = inset', '2 = partial', '3 = full'
    GRPS = {
      # Group types (gt):  vert=vertical (items stacked Z-axis)  hori=horizontal (items side-by-side X-axis)
      #                    separator=full-depth panel between groups  divider=front-strip panel between groups
      # Vertical group — items stacked top-to-bottom with horizontal dividers
      # it:             item type (4-letter code):  door=door leaf  drwr=drawer front  open=opening  appl=appliance
      #                                              sepa=separator (full depth)  devi=divider (strip at front)
      # ih:             item height in cm (0 = fill remaining group height)
      # iw:             item width  in cm (0 = fill remaining group width, used in hori groups)
      # shlv:           shelves count
      # Shared params:  mat=material  shp=shape  hdl=handle  hoff=handle h-offset(cm)  voff=handle v-offset(cm)
      # door-only:      hngs=hinge count  toff=top hinge offset(%)  boff=bottom hinge offset(%)
      # drwr-only:      dbox=drawer box type  tclr=top clearance(cm)  bclr=bottom clearance(cm)
      # appl-only:      apid=appliance id
      g1: {
        gt:    "hori",
        gh:    0.0,   # 0 = fill remaining interior height
        items: [
          { it: "open", iw: 0.0, shlv: 2 },
          { it: "sepa", iw: 1.8, shlv: 0 },
          { it: "open", iw:  0.0, shlv: 1 }
        ]
      },
      g2: {
        gt:    "separator",  # This group is just a horizontal separator, not an actual group with items
        gh:    1.8,          # Height = panel thickness
      },
      g3: {
        gt:    "vert",
        gh:    0.0,   # 0 = fill remaining interior height
        items: [
          { it: "open", ih: 0.0, shlv: 1 },
          { it: "devi", ih: 1.8, shlv: 0 },
          { it: "open", ih: 0.0, shlv: 0 }
        ]
      }
    } unless defined?(GRPS)

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Identify ML_Cabinets DC instances
    # ----------------------------------------------------------------

    def self.cabinet_instance?(entity)
      entity.is_a?(Sketchup::ComponentInstance) &&
        !entity.definition.get_attribute('ml_cabinets', 'type', '').empty?
    end

    # ----------------------------------------------------------------
    # Entry point
    # ----------------------------------------------------------------

    # Build the cabinet ComponentDefinition without placing an instance.
    # Returns a hash: { defn:, params:, parent_name: }
    def self.build_definition(config = {})
      model = Sketchup.active_model

      model.start_operation('Build Cabinet Definition', true)

      begin
        parent_name = "Cabinet"

        params = config.empty? ? default_params : params_from_config(config)

        w_cm     = params[:w_cm]
        h_cm     = params[:h_cm]
        d_cm     = params[:d_cm]
        t_cm     = params[:t_cm]
        bt_cm    = params[:bt_cm]
        tk_h_cm  = params[:tk_h_cm]
        tk_sb_cm = params[:tk_sb_cm]

        side_defn = if params[:cab_type].to_s.end_with?('-corner')
          make_panel(model, 'SidePanel', t_cm, d_cm, h_cm - tk_h_cm)
        else
          {
            left:  make_side_panel_assembly(model, 'SidePanelLeftAssembly', :left),
            right: make_side_panel_assembly(model, 'SidePanelRightAssembly', :right)
          }
        end
        base_defn          = make_panel(model, 'BasePanel',   w_cm - 2 * t_cm, d_cm, t_cm)
        top_defn           = make_panel(model, 'TopPanel',    w_cm - 2 * t_cm, d_cm, t_cm)
        back_defn          = make_panel(model, 'BackPanel',   w_cm - 2 * t_cm, bt_cm, h_cm - tk_h_cm - 2 * t_cm)

        tk          = params[:tk]
        create_legs = params[:create_legs]
        skirting    = params[:skirting]
        leg_defn = nil
        toekick_front_defn = nil
        toekick_side_defn  = nil
        toekick_back_defn  = nil
        skirting_defn      = nil

        if create_legs
          leg_defn = load_leg_definition(model, params[:legs_preset], tk_h_cm)
        else
          toekick_front_defn = make_panel(model, 'ToeKick',     w_cm, t_cm, tk_h_cm)
          toekick_side_defn  = make_panel(model, 'ToeKickSide', t_cm, d_cm - tk_sb_cm - t_cm, tk_h_cm)
          toekick_back_defn  = make_panel(model, 'ToeKickBack', w_cm - 2 * t_cm, t_cm, tk_h_cm)
        end

        if tk && skirting
          skirting_defn = make_panel(model, 'Skirting', w_cm, 0.3, tk_h_cm)
        end

        # Load drawer face preset (cabinet-level default for all drawer items)
        drawer_face_defn = DrawerFaceDC.load_definition(model, params[:drawer_face_preset])

        # Load door leaf preset (cabinet-level default for all door items)
        door_leaf_defn = DoorLeafDC.load_definition(model, params[:door_leaf_preset])

        # Load panel face preset (cabinet-level default for all panel items)
        panel_face_defn = PanelDC.load_definition(model, params[:panel_face_preset])

        # Load handle presets (cabinet-level defaults for door and drawer items)
        door_handle_defn   = HandleDC.load_definition(model, params[:door_handle_preset])
        drawer_handle_defn = HandleDC.load_definition(model, params[:drawer_handle_preset])

        # Resolve material presets to SketchUp::Material objects
        resolved_materials = MaterialHelper.resolve_all(model, params[:materials])

        cab_display_name = config.empty? ? parent_name : generate_cabinet_name(config)

        cabinet_defn = make_cabinet(model, parent_name, params,
          side_defn, base_defn, top_defn, back_defn, toekick_front_defn, toekick_side_defn, toekick_back_defn, leg_defn,
          drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn,
          door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn,
          panel_face_defn: panel_face_defn,
          skirting_defn: skirting_defn,
          materials: resolved_materials,
          display_name: cab_display_name)

        # Store the original dialog config as JSON on the definition so
        # Edit Cabinet can reload it later. Only store when config came
        # from the dialog (non-empty).
        unless config.empty?
          cabinet_defn.set_attribute('ml_cabinets', 'config_json', JSON.generate(config))
        end

        model.commit_operation

        { defn: cabinet_defn, params: params, parent_name: parent_name }

      rescue => e
        model.abort_operation
        puts "❌ Build definition failed: #{e.message}"
        e.backtrace.first(6).each { |line| puts "    #{line}" }
        nil
      end
    end

    # Place an already-built cabinet definition as an instance, redraw DC,
    # and attach the scale observer. Called by PlacementTool on click.
    def self.place_instance(cabinet_defn, parent_name, params, transformation)
      model = Sketchup.active_model

      model.start_operation('Place Cabinet', true)

      begin
        instance = model.active_entities.add_instance(cabinet_defn, transformation)
        instance.name = parent_name

        model.commit_operation

        # DC evaluation must happen OUTSIDE any open operation
        redraw_dc(instance)

        # Attach scale observer to this cabinet instance
        MLCabinets::UI::ScaleObserverManager.attach_to(instance)

        # Purge orphaned definitions and unused materials (deferred)
        purge_unused(model)

        instance

      rescue => e
        model.abort_operation
        puts "❌ Place failed: #{e.message}"
        e.backtrace.first(6).each { |line| puts "    #{line}" }
        nil
      end
    end

    # Convenience: build + place at origin (used by Test Cabinet button)
    def self.build(config = {})
      result = build_definition(config)
      return nil unless result

      hff_cm = result[:params][:hff_cm] || 0.0
      placement = hff_cm > 0 ? Geom::Transformation.new([0, 0, hff_cm.cm]) : Geom::Transformation.new

      place_instance(result[:defn], result[:parent_name], result[:params], placement)
    end

    # ================================================================
    # Post-operation cleanup
    # ================================================================

    # Purges orphaned component definitions and unused materials from the model.
    # Deferred via UI.start_timer so it always runs after any pending DC
    # redraw_with_undo operation has completed.
    def self.purge_unused(model)
      ::UI.start_timer(0.2) do
        begin
          model.definitions.purge_unused
          model.materials.purge_unused
          puts 'MLCabinets: purged unused definitions and materials' if MLCabinets::DEBUG
        rescue => e
          puts "MLCabinets: purge_unused failed — #{e.message}" if MLCabinets::DEBUG
        end
      end
    end

    # ================================================================
    # Cabinet auto-naming (stored as DA attribute, not on definition/instance)
    # ================================================================

    # Produces a descriptive label for a cabinet configuration.
    # Uses config[:name] when provided; otherwise builds a code like
    # BC_V(1D)_60cm  (type prefix _ group layout _ width).
    def self.generate_cabinet_name(config)
      # ---- 1. User-supplied name takes priority ----
      user_name = config[:name].to_s.strip
      return user_name unless user_name.empty?

      # ---- 2. Auto-generate from config ----
      cab_type = (config[:type] || 'base').to_s
      unit     = (config[:unit] || 'cm').to_s
      width    = config[:width].to_f
      w_cm     = unit == 'in' ? (width * 2.54) : width

      type_prefix = case cab_type
                    when 'base'          then 'BC'
                    when 'upper', 'wall' then 'WC'
                    when 'tall'          then 'TC'
                    when 'high'          then 'HC'
                    when /corner/        then 'CC'
                    else 'CAB'
                    end

      groups = config[:groups] || []
      group_codes = groups.filter_map { |g| cabinet_group_code(g) }
      group_label = group_codes.empty? ? 'V' : group_codes.join('_')

      w_label = "#{w_cm.round.to_i}cm"

      "#{type_prefix}_#{group_label}_#{w_label}".gsub(/_+/, '_').gsub(/^_+|_+$/, '')
    end

    # Returns a layout+item summary string for one group, e.g. "V_1D" or "H_1D_2Dr".
    # Returns nil for structural-only groups (separator, divider) so they are skipped.
    def self.cabinet_group_code(group)
      g_type = (group[:type] || 'vertical-group').to_s
      return nil if %w[separator-group divider-group].include?(g_type)
      return 'P' if g_type == 'profile-group'

      layout = g_type == 'horizontal-group' ? 'H' : 'V'

      items = (group[:items] || []).reject do |i|
        %w[separator divider].include?(i[:type].to_s)
      end
      return layout if items.empty?

      counts = Hash.new(0)
      items.each { |i| counts[cabinet_item_code(i[:type].to_s)] += 1 }
      item_str = counts.map { |code, cnt| cnt == 1 ? code : "#{cnt}#{code}" }.join('_')

      "#{layout}_#{item_str}"
    end

    # Short alphabetic code for an item type — used in the auto-name.
    def self.cabinet_item_code(item_type)
      case item_type
      when 'door', 'door-hinge-right', 'door-hinge-left',
           'door-hinge-top', 'door-hinge-bottom' then 'D'
      when 'double-door'              then '2D'
      when 'drawer', 'false-drawer'  then 'Dr'
      when 'opening'                 then 'O'
      when 'appliance'               then 'App'
      when 'blank'                   then 'Blk'
      when 'profile'                 then 'P'
      else 'X'
      end
    end

    # ================================================================
    # Default params — mirrors the module constants for backward compat.
    # ================================================================

    def self.default_params
      {
        w_cm:     W_CM,
        h_cm:     H_CM,
        d_cm:     D_CM,
        t_cm:     T_CM,
        bt_cm:    BT_CM,
        bp_sb_cm: BP_SB_CM,
        bk_joinery: 1,
        bg_depth_cm: 0.0,
        bg_clearance_cm: 0.0,
        bk_type:  BK_TYPE,
        bk_st_cnt: BK_ST_CNT,
        tk:       TK,
        fs:       FS,
        fb:       FB,
        tk_h_cm:  TK_H_CM,
        tk_sb_cm: TK_SB_CM,
        cl:       CL,
        st_w_cm:  ST_W_CM,
        tp_type:  TP_TYPE,
        bp_type:  BP_TYPE,
        sp_type:  SP_TYPE,
        ov_type:  OV_TYPE,
        grps:     GRPS,
        cab_type: 'base',
        hff_cm:   0.0,
        skirting:    true,
        create_legs: false,
        legs_preset: nil,
        drawer_face_preset: nil,
        door_leaf_preset: nil,
        door_handle_preset: nil,
        drawer_handle_preset: nil,
      }
    end

    # ================================================================
    # Convert the JSON config from the JS dialog into the internal
    # params hash used by make_cabinet. All dimensions are converted
    # to cm. String enum values are mapped to DC numeric codes.
    # ================================================================

    TP_MAP = { 'closed' => 1, 'open' => 2, 'none' => 3 }.freeze unless defined?(TP_MAP)
    BP_MAP = { 'closed' => 1, 'open' => 2 }.freeze unless defined?(BP_MAP)
    SP_MAP = { 'inset' => 1, 'overlay' => 2, 'full' => 3 }.freeze unless defined?(SP_MAP)
    BK_MAP = { 'closed' => 1, 'stretchers' => 2, 'none' => 3 }.freeze unless defined?(BK_MAP)
    BK_JOINERY_MAP = { 'butt' => 1, 'grooved' => 2 }.freeze unless defined?(BK_JOINERY_MAP)
    OV_MAP = { 'inset' => 1, 'partial' => 2, 'full' => 3 }.freeze unless defined?(OV_MAP)

    def self.params_from_config(config)
      unit  = config[:unit] || 'cm'
      to_cm = unit == 'in' ? 2.54 : 1.0

      c  = config[:construction] || {}
      tk = config[:toe_kick] || {}
      tk_enabled = tk[:enabled] != false

      t_cm = (c[:panel_thickness].to_f * to_cm)

      doors_cfg   = config[:doors]   || {}
      drawers_cfg = config[:drawers] || {}

      # Global handle offsets (cm) — used as defaults when per-item offset is 0
      door_hoff_cm   = doors_cfg[:handle_offset_h].to_f * to_cm
      door_voff_cm   = doors_cfg[:handle_offset_v].to_f * to_cm
      door_hrot_deg  = doors_cfg[:handle_rotation].to_f
      drawer_hoff_cm = drawers_cfg[:handle_offset_h].to_f * to_cm
      drawer_voff_cm = drawers_cfg[:handle_offset_v].to_f * to_cm
      drawer_hrot_deg = drawers_cfg[:handle_rotation].to_f

      global_offsets = {
        door_hoff_cm:   door_hoff_cm,
        door_voff_cm:   door_voff_cm,
        door_hrot_deg:  door_hrot_deg,
        drawer_hoff_cm: drawer_hoff_cm,
        drawer_voff_cm: drawer_voff_cm,
        drawer_hrot_deg: drawer_hrot_deg,
      }

      {
        w_cm:      (config[:width].to_f * to_cm),
        h_cm:      (config[:height].to_f * to_cm),
        d_cm:      (config[:depth].to_f * to_cm),
        t_cm:      t_cm,
        bt_cm:     (c[:back_panel_thickness].to_f * to_cm),
        bp_sb_cm:  (c[:back_panel_recess].to_f * to_cm),
        bk_joinery: BK_JOINERY_MAP[c[:back_panel_joinery].to_s] || 1,
        bg_depth_cm: [(c[:back_groove_depth].to_f * to_cm), 0.0].max,
        bg_clearance_cm: [(c[:back_groove_clearance].to_f * to_cm), 0.0].max,
        bk_type:   BK_MAP[c[:back_panel_type].to_s] || 1,
        bk_st_cnt: (c[:stretcher_count] || 2).to_i,
        tk:        tk_enabled,
        fs:        tk[:flat_sides] != false,
        fb:        tk[:flat_back] != false,
        tk_h_cm:   tk_enabled ? (tk[:height].to_f * to_cm) : 0.0,
        tk_sb_cm:  (tk[:depth].to_f * to_cm),
        cl:        (c[:overlay_clearance].to_f * to_cm),
        st_w_cm:   (c[:stretcher_width].to_f * to_cm),
        tp_type:   TP_MAP[c[:top_panel].to_s] || 1,
        bp_type:   BP_MAP[c[:base_panel].to_s] || 1,
        sp_type:   SP_MAP[c[:side_panels].to_s] || 2,
        ov_type:   OV_MAP[c[:overlay_type].to_s] || 3,
        grps:      build_grps_from_config(config[:groups] || [], t_cm, to_cm, global_offsets),
        cab_type:  config[:type] || 'base',
        hff_cm:    (config[:height_from_floor].to_f * to_cm),
        corner_type:     config[:corner_type] || 'l-shaped',
        accessible_side: config[:accessible_side] || 'right',
        unit:            unit,
        skirting:    tk[:skirting] != false,
        create_legs: tk[:create_legs] == true,
        legs_preset: tk[:legs_preset],
        drawer_face_preset: drawers_cfg[:preset_id],
        door_leaf_preset: doors_cfg[:preset_id],
        panel_face_preset: (config[:panels] || {})[:preset_id],
        door_handle_preset:    doors_cfg[:handle_preset_id],
        drawer_handle_preset:  drawers_cfg[:handle_preset_id],
        materials: extract_materials(config[:materials]),
        blind_face_grain: config[:blind_face_grain],
      }
    end

    # ================================================================
    # Extract the materials hash from the JS config.
    # Returns { panel: {id:, grain:}, edge: {...}, door: {...}, ... }
    # ================================================================

    def self.extract_materials(mat_hash)
      return {} unless mat_hash.is_a?(Hash)

      # Backward compat: old configs stored structural material under :panel.
      # Migrate it to :carcass when no explicit :carcass key exists.
      if mat_hash[:panel] && !mat_hash[:carcass]
        mat_hash = mat_hash.dup
        mat_hash[:carcass] = mat_hash.delete(:panel)
      end

      result = {}
      %i[carcass panel edge door drawer handle glass].each do |cat|
        entry = mat_hash[cat] || {}
        id = entry[:id]
        next unless id && !id.to_s.strip.empty?
        result[cat] = { id: id.to_s, grain: (entry[:grain] || 'vertical').to_s }
      end
      result
    end

    # ================================================================
    # Convert the JS groups array into the GRPS hash expected by
    # make_cabinet. JS group/item types are mapped to Ruby codes.
    # All dimensions are expected in cm (already converted).
    # ================================================================

    GT_MAP = {
      'vertical-group'   => 'vert',
      'horizontal-group' => 'hori',
      'separator-group'  => 'separator',
      'divider-group'    => 'divider',
      'profile-group'    => 'prof',
    }.freeze unless defined?(GT_MAP)

    IT_MAP = {
      'door'             => 'door',
      'door-hinge-right' => 'door',
      'door-hinge-left'  => 'door',
      'door-hinge-top'   => 'door',
      'door-hinge-bottom'=> 'door',
      'double-door'      => 'door',
      'drawer'           => 'drwr',
      'false-drawer'     => 'fdrw',
      'opening'          => 'open',
      'appliance'        => 'appl',
      'separator'        => 'sepa',
      'divider'          => 'devi',
      'blank'            => 'blnk',
      'profile'          => 'prof',
      'panel'            => 'panl',
    }.freeze unless defined?(IT_MAP)

    def self.build_grps_from_config(groups, panel_thickness_cm, to_cm = 1.0, global_offsets = {})
      result = {}
      groups.each_with_index do |group, idx|
        key = :"g#{idx + 1}"
        gt  = GT_MAP[group[:type].to_s] || 'vert'

        if gt == 'separator' || gt == 'divider' || gt == 'prof'
          gh = group[:height].to_f * to_cm
          gh = panel_thickness_cm if gh == 0 && gt != 'prof'
          entry = { gt: gt, gh: gh }
          entry[:prid] = group[:profile_id].to_s if gt == 'prof' && group[:profile_id] && !group[:profile_id].to_s.empty?
          entry[:prmid] = group[:profile_material_id].to_s if gt == 'prof' && group[:profile_material_id] && !group[:profile_material_id].to_s.strip.empty?
          entry[:prmg]  = group[:profile_material_grain].to_s if gt == 'prof' && group[:profile_material_grain] && !group[:profile_material_grain].to_s.strip.empty?
          entry[:hidden] = true if group[:hidden] == true
          result[key] = entry
          next
        end

        items = (group[:items] || []).map do |item|
          it = IT_MAP[item[:type].to_s] || 'open'
          entry = { it: it, shlv: (item[:shelves] || 0).to_i }
          if gt == 'hori'
            entry[:iw] = item[:height].to_f * to_cm
          else
            entry[:ih] = item[:height].to_f * to_cm
          end
          # Drawer-specific params
          if it == 'drwr'
            entry[:dbox] = item[:drawer_box] || 'auto'
            entry[:tclr] = item[:drawer_top_clearance].to_f * to_cm
            entry[:bclr] = item[:drawer_bottom_clearance].to_f * to_cm
            entry[:dfid] = item[:shape_id] if item[:shape_id] && !item[:shape_id].to_s.empty?
          end
          # False-drawer face preset
          if it == 'fdrw'
            entry[:dfid] = item[:shape_id] if item[:shape_id] && !item[:shape_id].to_s.empty?
          end
          # Door-specific params
          if it == 'door'
            entry[:dlid] = item[:shape_id] if item[:shape_id] && !item[:shape_id].to_s.empty?
            entry[:dsub] = item[:type].to_s
          end
          # Panel-specific params
          if it == 'panl'
            entry[:plid] = item[:shape_id] if item[:shape_id] && !item[:shape_id].to_s.empty?
          end
          # Profile-specific params
          if it == 'prof'
            entry[:prid] = item[:profile_id]
            entry[:prmid] = item[:profile_material_id].to_s if item[:profile_material_id] && !item[:profile_material_id].to_s.strip.empty?
            entry[:prmg]  = item[:profile_material_grain].to_s if item[:profile_material_grain] && !item[:profile_material_grain].to_s.strip.empty?
          end
          # Appliance-specific params
          if it == 'appl'
            entry[:apid] = item[:appliance_id].to_s if item[:appliance_id] && !item[:appliance_id].to_s.empty?
          end
          # Handle offsets and per-item preset (door and drawer items)
          # Per-item offsets are added on top of global offsets
          if it == 'door' || it == 'drwr' || it == 'fdrw'
            item_hoff = item[:handle_offset_h].to_f * to_cm
            item_voff = item[:handle_offset_v].to_f * to_cm
            if it == 'door'
              entry[:hoff] = global_offsets[:door_hoff_cm].to_f + item_hoff
              entry[:voff] = global_offsets[:door_voff_cm].to_f + item_voff
              entry[:hrot] = global_offsets[:door_hrot_deg].to_f
            else
              entry[:hoff] = global_offsets[:drawer_hoff_cm].to_f + item_hoff
              entry[:voff] = global_offsets[:drawer_voff_cm].to_f + item_voff
              entry[:hrot] = global_offsets[:drawer_hrot_deg].to_f
            end
            entry[:hdl]  = item[:handle_id].to_s if item[:handle_id] && !item[:handle_id].to_s.strip.empty?
            entry[:hmat] = item[:handle_material_id].to_s if item[:handle_material_id] && !item[:handle_material_id].to_s.strip.empty?
            entry[:hmatg] = item[:handle_material_grain].to_s if item[:handle_material_grain] && !item[:handle_material_grain].to_s.strip.empty?
          end
          # Per-item material override (door, drawer and panel items)
          if it == 'door' || it == 'drwr' || it == 'fdrw' || it == 'panl'
            entry[:mat]  = item[:material_id].to_s    if item[:material_id] && !item[:material_id].to_s.strip.empty?
            entry[:matg] = item[:material_grain].to_s if item[:material_grain] && !item[:material_grain].to_s.strip.empty?
          end
          # Opening amount (0–100 %) — design-time default used by OpenCloseTool
          if it == 'door' || it == 'drwr'
            oa_val = item[:opening_amount].to_f
            entry[:oa] = oa_val > 0 ? oa_val.round(2) : 50.0
          end
          entry[:hidden] = true if item[:hidden] == true
          entry
        end

        result[key] = { gt: gt, gh: group[:height].to_f * to_cm, items: items }
      end
      result
    end

    # ================================================================
    # Load a leg ComponentDefinition from the library (SKP file) or
    # create a simple box leg as fallback.
    # ================================================================

    def self.load_leg_definition(model, preset_id, leg_h_cm)
      if preset_id
        # Resolve preset ID (UUID) to the preset name used as folder name
        preset_name = resolve_leg_preset_name(preset_id)
        if preset_name
          skp_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'legs', preset_name, "#{preset_name}.skp")
          if File.exist?(skp_path)
            defn = model.definitions.load(skp_path, allow_newer: true)
            if defn
              puts "MLCabinets: Loaded leg preset '#{preset_name}' from #{skp_path}" if MLCabinets::DEBUG
              return defn
            end
          end
        end
        puts "MLCabinets: Leg preset '#{preset_id}' not found, using box leg" if MLCabinets::DEBUG
      end

      # Fallback: create a simple 4×4 cm box leg
      leg_w_cm = 4.0
      leg_d_cm = 4.0
      make_panel(model, 'BoxLeg', leg_w_cm, leg_d_cm, -leg_h_cm)
    end

    # Look up the preset name from presets.json by ID (UUID).
    # Falls back to using the ID directly if it matches a folder name.
    def self.resolve_leg_preset_name(preset_id)
      # First check if preset_id itself is a folder name (non-UUID IDs)
      direct_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'legs', preset_id.to_s)
      return preset_id.to_s if Dir.exist?(direct_path)

      # Look up in presets.json
      presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'legs', 'presets.json')
      return nil unless File.exist?(presets_file)

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      entry = (data['presets'] || []).find { |p| p['id'] == preset_id.to_s }
      entry ? entry['name'] : nil
    rescue => e
      puts "MLCabinets: resolve_leg_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ================================================================
    # Build a solid box ComponentDefinition.
    # Re-uses an existing definition by name and clears its geometry.
    # FIX: Sketchup::Entities has no .empty? — use .length == 0
    # ================================================================

    def self.make_panel(model, name, w_cm, d_cm, h_cm)
      defn = model.definitions.add(name)

      # Sketchup::Entities does not implement .empty? — use .length
      defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0

      w = w_cm.cm
      d = d_cm.cm
      h = h_cm.cm

      if name.include?('BoxLeg')
        face = defn.entities.add_face(
          Geom::Point3d.new(-w/2, -d/2, 0),
          Geom::Point3d.new(w/2, -d/2, 0),
          Geom::Point3d.new(w/2, d/2, 0),
          Geom::Point3d.new(-w/2, d/2, 0)
        )
      else
        face = defn.entities.add_face(
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(w, 0, 0),
          Geom::Point3d.new(w, d, 0),
          Geom::Point3d.new(0, d, 0)
        )
      end
      raise "Face creation failed for '#{name}'" unless face

      face.pushpull(h)

      defn
    end

    def self.hide_panel_edges_on_y_planes(defn, y_planes_cm)
      y_planes = y_planes_cm.map { |v| v.cm }
      tolerance = 0.001

      defn.entities.grep(Sketchup::Edge).each do |edge|
        points = [edge.start.position, edge.end.position]
        next unless y_planes.any? { |y| points.all? { |pt| (pt.y - y).abs <= tolerance } }

        edge.hidden = true
      end

      defn
    end

    # Creates a side panel as a Dynamic Component assembly made from simple
    # rectangular solids. In grooved mode the back panel enters the channel;
    # in butt/recessed mode only the main slab is visible.
    def self.make_side_panel_assembly(model, name, side)
      defn = model.definitions.add(name)
      defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
      defn.description = 'Side Panel Assembly DC — ML Cabinets'

      defn.set_attribute(DA, 'name', name)
      defn.set_attribute(DA, '_name_access', 'NONE')
      defn.set_attribute('ml_cabinets', 'manufacturing_role', 'side_panel_assembly')
      defn.set_attribute('ml_cabinets', 'side', side.to_s)

      main_defn = make_panel(model, "#{name}Main", 1, 1, 1)
      grooved_main_defn = make_panel(model, "#{name}GroovedMain", 1, 1, 1)
      rear_defn = make_panel(model, "#{name}RearLip", 1, 1, 1)
      web_defn  = make_panel(model, "#{name}GrooveWeb", 1, 1, 1)
      hide_panel_edges_on_y_planes(grooved_main_defn, [0])
      hide_panel_edges_on_y_planes(rear_defn, [1])
      hide_panel_edges_on_y_planes(web_defn, [0, 1])

      main = defn.entities.add_instance(main_defn, Geom::Transformation.new)
      main.name = 'SidePanelButtMain'
      da_attr(main, 'x', '0')
      da_attr(main, 'y', '0')
      da_attr(main, 'z', '0')
      da_attr(main, 'lenx', 'Parent!lenx')
      da_attr(main, 'leny', 'Parent!leny')
      da_attr(main, 'lenz', 'Parent!lenz')
      da_attr(main, 'hidden', 'IF(Parent!back_groove_depth > 0, True, False)')

      grooved_main = defn.entities.add_instance(grooved_main_defn, Geom::Transformation.new)
      grooved_main.name = 'SidePanelGroovedMain'
      da_attr(grooved_main, 'x', '0')
      da_attr(grooved_main, 'y', 'Parent!back_groove_y + Parent!back_groove_width')
      da_attr(grooved_main, 'z', '0')
      da_attr(grooved_main, 'lenx', 'Parent!lenx')
      da_attr(grooved_main, 'leny', 'IF(Parent!leny - Parent!back_groove_y - Parent!back_groove_width > 0, Parent!leny - Parent!back_groove_y - Parent!back_groove_width, 0)')
      da_attr(grooved_main, 'lenz', 'Parent!lenz')
      da_attr(grooved_main, 'hidden', 'IF(Parent!back_groove_depth > 0, False, True)')

      rear = defn.entities.add_instance(rear_defn, Geom::Transformation.new)
      rear.name = 'SidePanelRearLip'
      da_attr(rear, 'x', '0')
      da_attr(rear, 'y', '0')
      da_attr(rear, 'z', '0')
      da_attr(rear, 'lenx', 'Parent!lenx')
      da_attr(rear, 'leny', 'Parent!back_groove_y')
      da_attr(rear, 'lenz', 'Parent!lenz')
      da_attr(rear, 'hidden', 'IF(Parent!back_groove_depth > 0, False, True)')

      web_x = side == :left ? '0' : 'Parent!back_groove_depth'
      web = defn.entities.add_instance(web_defn, Geom::Transformation.new)
      web.name = 'SidePanelGrooveWeb'
      da_attr(web, 'x', web_x)
      da_attr(web, 'y', 'Parent!back_groove_y')
      da_attr(web, 'z', '0')
      da_attr(web, 'lenx', 'Parent!lenx - Parent!back_groove_depth')
      da_attr(web, 'leny', 'Parent!back_groove_width')
      da_attr(web, 'lenz', 'Parent!lenz')
      da_attr(web, 'hidden', 'IF(Parent!back_groove_depth > 0, False, True)')

      defn
    end

    # ================================================================
    # Assemble the parent Cabinet definition (no direct geometry).
    # ================================================================

    def self.make_cabinet(model, parent_name, params, side, base, top, back, toekick_front, toekick_side, toekick_back, leg_defn = nil, drawer_face_defn: nil, door_leaf_defn: nil, door_handle_defn: nil, drawer_handle_defn: nil, panel_face_defn: nil, skirting_defn: nil, materials: {}, display_name: nil)
      defn = model.definitions.add(parent_name)
      defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
      defn.description = 'Cabinet Dynamic Component — ML Cabinets'

      # Ensure "ML Cabinets" layer folder + sub-layers exist in this model.
      layers = LayerManager.ensure_ml_layers(model)

      # Corner cabinets delegate to the dedicated builder
      cab_type_val = params[:cab_type] || 'base'
      if cab_type_val.end_with?('-corner')
        return CornerCabinetDC.build(model, parent_name, params,
          side, base, top, back, toekick_front, toekick_side, toekick_back, leg_defn,
          drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn,
          door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn,
          panel_face_defn: panel_face_defn, skirting_defn: skirting_defn,
          materials: materials, layers: layers, display_name: display_name)
      end

      # Destructure params into local variables
      w_cm     = params[:w_cm]
      h_cm     = params[:h_cm]
      d_cm     = params[:d_cm]
      t_cm     = params[:t_cm]
      bt_cm    = params[:bt_cm]
      bp_sb_cm = params[:bp_sb_cm]
      bk_joinery = params[:bk_joinery] || 1
      bg_depth_cm = params[:bg_depth_cm] || 0.0
      bg_clearance_cm = params[:bg_clearance_cm] || 0.0
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
      cab_type = params[:cab_type] || 'base'
      create_legs = params[:create_legs]

      # Convert dimensions to inches before adding the dynamic attributes that control the child panel instances, since the formulas will be evaluated in inches.
      t_in      = t_cm.to_f / 2.54
      bt_in     = bt_cm.to_f / 2.54
      bp_sb_in  = bp_sb_cm.to_f / 2.54
      bg_depth_in = bg_depth_cm.to_f / 2.54
      bg_clearance_in = bg_clearance_cm.to_f / 2.54
      tk_h_in   = tk_h_cm.to_f / 2.54
      tk_sb_in  = tk_sb_cm.to_f / 2.54
      cl_in     = cl.to_f / 2.54
      tk_str    = tk ? 'True' : 'False'  # DC attributes are stored as strings, even for booleans
      st_w_in   = st_w_cm.to_f / 2.54
      fs_str    = fs ? 'True' : 'False'
      fb_str    = fb ? 'True' : 'False'
      interior_h  = h_cm - (tk ? tk_h_cm : 0.0) - 2.0 * t_cm
      interior_w  = w_cm - 2.0 * t_cm
      fill_count  = grps.values.count { |v| v[:gh] == 0 }
      fixed_h_sum = grps.values.reject { |v| v[:gh] == 0 }.sum { |v| v[:gh] }
      fill_h      = fill_count > 0 ? (interior_h - fixed_h_sum) / fill_count : 0.0
      z_offset    = interior_h
      entries = grps.map { |k, v|
        gh_cm = v[:gh] == 0 ? fill_h : v[:gh]
        gf    = v[:gh] == 0 ? 1 : 0
        z_offset -= gh_cm
        z_in  = z_offset / 2.54
        gh_in = gh_cm / 2.54
        gw_in = interior_w / 2.54
        hdn_part  = v[:hidden] ? ", :hdn=>1" : ""
        prid_part = (v[:gt].to_s == 'prof' && v[:prid] && !v[:prid].to_s.empty?) ? ", :prid=>#{v[:prid]}" : ""
        prmid_part = (v[:gt].to_s == 'prof' && v[:prmid] && !v[:prmid].to_s.empty?) ? ", :prmid=>#{v[:prmid]}" : ""
        prmg_part  = (v[:gt].to_s == 'prof' && v[:prmg] && !v[:prmg].to_s.empty?)  ? ", :prmg=>#{v[:prmg]}"   : ""
        "#{k}: {:gt=>#{v[:gt]}, :gz=>#{z_in.round(6)}, :gh=>#{gh_in.round(6)}, :gw=>#{gw_in.round(6)}, :gf=>#{gf}#{hdn_part}#{prid_part}#{prmid_part}#{prmg_part}, :it=>#{serialize_items(v[:items])}}"
      }
      groups_str = entries.join('; ')

      # User-editable attributes.
      da_attr(defn, 'groups',              "\"#{groups_str}\"",      'Groups',                'STRING',      'NONE')
      da_attr(defn, 'thickness',           "#{t_in}",                'Panel Thickness',       'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'toekick',             "#{tk_str}",              'Toe Kick Enabled',      'NUMBER',      'LIST')
      da_attr(defn, 'toekick_flat_sides',  "#{fs_str}",              'Toe Kick Flat Sides',   'NUMBER',      'LIST')
      da_attr(defn, 'toekick_flat_back',   "#{fb_str}",              'Toe Kick Flat Back',    'NUMBER',      'LIST')
      da_attr(defn, 'tk_height',           "#{tk_h_in}",             'Toe Kick Height',       'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'tk_setback',          "#{tk_sb_in}",            'Toe Kick Setback',      'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'bp_thickness',        "#{bt_in}",               'Back Panel Thickness',  'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'bp_setback',          "#{bp_sb_in}",            'Back Panel Setback',    'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'bk_joinery',          "#{bk_joinery}",          'Back Panel Joinery',    'NUMBER',      'LIST')
      da_attr(defn, 'back_groove_depth',   "#{bg_depth_in}",         'Back Groove Depth',     'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'back_groove_clearance', "#{bg_clearance_in}",   'Back Groove Clearance', 'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'back_groove_effective', "IF(bk_joinery = 2, IF(bk_type = 1, IF(back_groove_depth > Thickness, Thickness, back_groove_depth), 0), 0)", 'Back Groove Effective', 'CENTIMETERS', 'NONE')
      da_attr(defn, 'back_groove_slot_width', "IF(back_groove_effective > 0, bp_thickness + IF(back_groove_clearance > 0, back_groove_clearance, 0), bp_thickness)", 'Back Groove Slot Width', 'CENTIMETERS', 'NONE')
      da_attr(defn, 'back_groove_slot_depth', "IF(back_groove_effective > 0, IF(back_groove_effective + IF(back_groove_clearance > 0, back_groove_clearance, 0) > Thickness, Thickness, back_groove_effective + IF(back_groove_clearance > 0, back_groove_clearance, 0)), 0)", 'Back Groove Slot Depth', 'CENTIMETERS', 'NONE')
      da_attr(defn, 'bk_type',             "#{bk_type}",             'Back Panel Type',       'NUMBER',      'LIST')
      da_attr(defn, 'bk_st_count',         "#{bk_st_cnt}",           'Back Stretchers Count', 'STRING',      'TEXTBOX')
      da_attr(defn, 'clearance',           "#{cl_in}",               'Clearance',             'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'tp_type',             "#{tp_type}",             'Top Panel Type',        'NUMBER',      'LIST')
      da_attr(defn, 'st_width',            "#{st_w_in}",             'Stretcher Width',       'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'bp_type',             "#{bp_type}",             'Base Panel Type',       'NUMBER',      'LIST')
      da_attr(defn, 'sp_type',             "#{sp_type}",             'Side Panel Type',       'NUMBER',      'LIST')
      da_attr(defn, 'ov_type',             "#{ov_type}",             'Overlay Type',          'NUMBER',      'LIST')
      
      
      # Cabinet master dimensions — stable custom attributes that children
      # reference instead of the volatile LenX/LenY/LenZ (which the DC
      # engine auto-computes from the bounding box).  This mirrors the
      # g_width/g_height/g_depth pattern on Groups and i_width/i_height/
      # i_depth on Items.  LenX/LenY/LenZ are intentionally LEFT FREE so
      # the SketchUp Scale tool works; the ScaleObserver updates these
      # custom attrs after a scale, then triggers a DC redraw.
      w_in = (w_cm / 2.54).round(6)
      d_in = (d_cm / 2.54).round(6)
      h_in = (h_cm / 2.54).round(6)
      da_attr(defn, 'cab_width',  "#{w_in}", 'Cabinet Width',  'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'cab_depth',  "#{d_in}", 'Cabinet Depth',  'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'cab_height', "#{h_in}", 'Cabinet Height', 'CENTIMETERS', 'TEXTBOX')
      da_attr(defn, 'shlf_width', "cab_width - 2 * Thickness", 'Shelf Width', 'CENTIMETERS', 'NONE')
      da_attr(defn, 'shlf_x',     "0",                         'Shelf X Offset', 'CENTIMETERS', 'NONE')

      defn.set_attribute(DA, 'name', parent_name)
      defn.set_attribute(DA, '_toekick_options', 'True = 1 & False = 0') # List options for the toekick boolean attribute.
      defn.set_attribute(DA, '_toekick_flat_sides_options', 'True = 1 & False = 0')
      defn.set_attribute(DA, '_toekick_flat_back_options',  'True = 1 & False = 0')
      defn.set_attribute(DA, '_tp_type_options', 'Closed = 1 & Open = 2 & None = 3') # List options for the top panel type attribute.
      defn.set_attribute(DA, '_sp_type_options', 'Inset = 1 & Overlay = 2 & Full Height = 3') # List options for the side panel type attribute.
      defn.set_attribute(DA, '_bp_type_options', 'Closed = 1 & Open = 2') # List options for the base panel type attribute.
      defn.set_attribute(DA, '_bk_type_options', 'Closed = 1 & Stretchers = 2 & None = 3') # List options for the back panel type attribute.
      defn.set_attribute(DA, '_bk_joinery_options', 'Butt / Recessed = 1 & Grooved Sides = 2')
      defn.set_attribute(DA, '_ov_type_options', 'Inset = 1 & Partial = 2 & Full = 3') # List options for the overlay type attribute.

      defn.set_attribute('ml_cabinets', 'type',    cab_type)
      defn.set_attribute('ml_cabinets', 'hff_in',  (params[:hff_cm].to_f / 2.54).round(6))
      defn.set_attribute('ml_cabinets', 'version', MLCabinets::VERSION)
      defn.set_attribute('ml_cabinets', 'cab_name', display_name || parent_name)

      # Add child instances with formulas that reference the parent attributes.

      # Note: the child definitions themselves have fixed dimensions in cm,
      # but the instances are transformed and controlled by DC formulas that 
      # reference the parent cabinet's attributes.
      # This allows the panels to maintain their thickness regardless of how the user scales the cabinet instance.

      parent = defn.get_attribute(DA, 'name')  # Store parent name in a variable for easy reference in formulas below. This is necessary because the formulas are stored as strings and won't have access to the local variable 'parent' at runtime, but they can reference the parent component by name.

      # Toe Kick / Legs
      if tk
        if create_legs && leg_defn
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

          # Front-Left Leg (center at inset from left edge, inset from front edge)
          t = Geom::Transformation.new([(tk_sb_cm + half_w).cm, (d_cm - tk_sb_cm - half_d).cm, 0])
          fl_leg = add_child(defn, leg_defn, t, 'Front Left Leg')
          da_attr(fl_leg, 'x', "#{parent}!tk_setback + #{half_w_in}")
          da_attr(fl_leg, 'y', "#{parent}!cab_depth - #{parent}!tk_setback - #{half_d_in}")
          da_attr(fl_leg, 'lenx', "#{leg_w_in}")
          da_attr(fl_leg, 'leny', "#{leg_d_in}")
          da_attr(fl_leg, 'lenz', "#{parent}!tk_height")  # Control leg height with toe kick height attribute
          da_attr(fl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          fl_leg.layer = layers[:legs] if layers[:legs]
          # Mirror the leg in the X axis so any asymmetry in the leg design is oriented correctly for a right-side placement
          mirroring = Geom::Transformation.scaling(-1, 1, 1)
          fl_leg.transform!(mirroring)

          # Front-Right Leg (center at inset from right edge, inset from front edge)
          t = Geom::Transformation.new([(w_cm - tk_sb_cm - half_w).cm, (d_cm - tk_sb_cm - half_d).cm, 0])
          fr_leg = add_child(defn, leg_defn, t, 'Front Right Leg')
          da_attr(fr_leg, 'x', "#{parent}!cab_width - #{parent}!tk_setback - #{half_w_in}")
          da_attr(fr_leg, 'y', "#{parent}!cab_depth - #{parent}!tk_setback - #{half_d_in}")
          da_attr(fr_leg, 'lenx', "#{leg_w_in}")
          da_attr(fr_leg, 'leny', "#{leg_d_in}")
          da_attr(fr_leg, 'lenz', "#{parent}!tk_height")  # Control leg height with toe kick height attribute
          da_attr(fr_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          fr_leg.layer = layers[:legs] if layers[:legs]

          # Back-Left Leg (center at inset from left edge, inset from back edge)
          t = Geom::Transformation.new([(tk_sb_cm + half_w).cm, (tk_sb_cm + half_d).cm, 0])
          bl_leg = add_child(defn, leg_defn, t, 'Back Left Leg')
          da_attr(bl_leg, 'x', "#{parent}!tk_setback + #{half_w_in}")
          da_attr(bl_leg, 'y', "#{parent}!tk_setback + #{half_d_in}")
          da_attr(bl_leg, 'lenx', "#{leg_w_in}")
          da_attr(bl_leg, 'leny', "#{leg_d_in}")
          da_attr(bl_leg, 'lenz', "#{parent}!tk_height")  # Control leg height with toe kick height attribute
          da_attr(bl_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          bl_leg.layer = layers[:legs] if layers[:legs]
          mirroring = Geom::Transformation.scaling(-1, -1, 1)
          bl_leg.transform!(mirroring)

          # Back-Right Leg (center at inset from right edge, inset from back edge)
          t = Geom::Transformation.new([(w_cm - tk_sb_cm - half_w).cm, (tk_sb_cm + half_d).cm, 0])
          br_leg = add_child(defn, leg_defn, t, 'Back Right Leg')
          da_attr(br_leg, 'x', "#{parent}!cab_width - #{parent}!tk_setback - #{half_w_in}")
          da_attr(br_leg, 'y', "#{parent}!tk_setback + #{half_d_in}")
          da_attr(br_leg, 'lenx', "#{leg_w_in}")
          da_attr(br_leg, 'leny', "#{leg_d_in}")
          da_attr(br_leg, 'lenz', "#{parent}!tk_height")  # Control leg height with toe kick height attribute
          da_attr(br_leg, 'hidden', "IF(#{parent}!Toekick, False, True)")
          br_leg.layer = layers[:legs] if layers[:legs]
          mirroring = Geom::Transformation.scaling(1, -1, 1)
          br_leg.transform!(mirroring)
        else
          # Toe Kick Front Panel
          t = Geom::Transformation.new([0, d_cm.cm - tk_sb_cm.cm - t_cm.cm, tk_h_cm.cm])
          toekick_front_panel = add_child(defn, toekick_front, t, 'Toe Kick Front Panel')
          da_attr(toekick_front_panel, 'x',      "IF(#{parent}!toekick_flat_sides, CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness), #{parent}!tk_setback)")
          da_attr(toekick_front_panel, 'y',      "#{parent}!cab_depth - #{parent}!tk_setback - #{parent}!thickness")
          da_attr(toekick_front_panel, 'z',      "#{parent}!tk_height")
          da_attr(toekick_front_panel, 'lenx',   "#{parent}!cab_width - IF(#{parent}!toekick_flat_sides, 0, 2 * #{parent}!tk_setback) - 2 * CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness)")
          da_attr(toekick_front_panel, 'leny',   "#{parent}!Thickness")
          da_attr(toekick_front_panel, 'lenz',   "#{parent}!tk_height")
          da_attr(toekick_front_panel, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!bp_type, False, True), True)")  # Hide if toekick is disabled

          # Toe Kick Side Left
          t = Geom::Transformation.new([0, 0, tk_h_cm.cm])
          toekick_side_l = add_child(defn, toekick_side, t, 'Toe Kick Side Left')
          da_attr(toekick_side_l, 'x',      "IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          da_attr(toekick_side_l, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          da_attr(toekick_side_l, 'z',      "#{parent}!tk_height")
          da_attr(toekick_side_l, 'lenx',   "#{parent}!Thickness")
          da_attr(toekick_side_l, 'leny',   "#{parent}!cab_depth - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, #{parent}!tk_setback, 2 * #{parent}!tk_setback)")
          da_attr(toekick_side_l, 'lenz',   "#{parent}!tk_height")
          da_attr(toekick_side_l, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!sp_type, False, False, True), True)")  # Hide if toekick is disabled

          # Toe Kick Side Right
          t = Geom::Transformation.new([w_cm.cm - t_cm.cm, 0, tk_h_cm.cm])
          toekick_side_r = add_child(defn, toekick_side, t, 'Toe Kick Side Right')
          da_attr(toekick_side_r, 'x',      "#{parent}!cab_width - #{parent}!Thickness - IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          da_attr(toekick_side_r, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          da_attr(toekick_side_r, 'z',      "#{parent}!tk_height")
          da_attr(toekick_side_r, 'lenx',   "#{parent}!Thickness")
          da_attr(toekick_side_r, 'leny',   "#{parent}!cab_depth - #{parent}!Thickness - IF(#{parent}!toekick_flat_back, #{parent}!tk_setback, 2 * #{parent}!tk_setback)")
          da_attr(toekick_side_r, 'lenz',   "#{parent}!tk_height")
          da_attr(toekick_side_r, 'hidden', "IF(#{parent}!Toekick, CHOOSE(#{parent}!sp_type, False, False, True), True)")  # Hide if toekick is disabled

          # Toe Kick Back Panel
          t = Geom::Transformation.new([t_cm.cm, 0, tk_h_cm.cm])
          toekick_back_panel = add_child(defn, toekick_back, t, 'Toe Kick Back Panel')
          da_attr(toekick_back_panel, 'x',      "#{parent}!Thickness + IF(#{parent}!toekick_flat_sides, 0, #{parent}!tk_setback)")
          da_attr(toekick_back_panel, 'y',      "IF(#{parent}!toekick_flat_back, 0, #{parent}!tk_setback)")
          da_attr(toekick_back_panel, 'z',      "#{parent}!tk_height")
          da_attr(toekick_back_panel, 'lenx',   "#{parent}!cab_width - 2 * #{parent}!Thickness - IF(#{parent}!toekick_flat_sides, 0, 2 * #{parent}!tk_setback)")
          da_attr(toekick_back_panel, 'leny',   "#{parent}!Thickness")
          da_attr(toekick_back_panel, 'lenz',   "#{parent}!tk_height")
          da_attr(toekick_back_panel, 'hidden', "IF(#{parent}!Toekick, False, True)")  # Hide if toekick is disabled

          # Apply panel material to toekick panels
          panel_mat = materials[:carcass]
          MaterialHelper.apply(toekick_front_panel, panel_mat) if panel_mat
          MaterialHelper.apply(toekick_side_l, panel_mat) if panel_mat
          MaterialHelper.apply(toekick_side_r, panel_mat) if panel_mat
          MaterialHelper.apply(toekick_back_panel, panel_mat) if panel_mat

          # Assign carcass layer to toe kick panels
          if layers[:carcass]
            toekick_front_panel.layer = layers[:carcass]
            toekick_side_l.layer      = layers[:carcass]
            toekick_side_r.layer      = layers[:carcass]
            toekick_back_panel.layer  = layers[:carcass]
          end
        end

        # Skirting Strip — 3 mm thin band in front of the toe kick, always visible (legs or not)
        if params[:skirting] && skirting_defn
          skirting_thickness_in = (0.3 / 2.54).round(6)  # 3 mm in inches
          t = Geom::Transformation.new([0, (d_cm - tk_sb_cm).cm, 0])
          skirting_inst = add_child(defn, skirting_defn, t, 'Skirting')
          da_attr(skirting_inst, 'x',      "IF(#{parent}!toekick_flat_sides, CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness), #{parent}!tk_setback)")
          da_attr(skirting_inst, 'y',      "#{parent}!cab_depth - #{parent}!tk_setback")
          da_attr(skirting_inst, 'z',      "#{parent}!tk_height")
          da_attr(skirting_inst, 'lenx',   "#{parent}!cab_width - IF(#{parent}!toekick_flat_sides, 0, 2 * #{parent}!tk_setback) - 2 * CHOOSE(#{parent}!sp_type, 0, 0, #{parent}!Thickness)")
          da_attr(skirting_inst, 'leny',   "#{skirting_thickness_in}")
          da_attr(skirting_inst, 'lenz',   "#{parent}!tk_height")
          da_attr(skirting_inst, 'hidden', "IF(#{parent}!Toekick, False, True)")
          MaterialHelper.apply(skirting_inst, materials[:handle]) if materials[:handle]
          skirting_inst.layer = layers[:carcass] if layers[:carcass]
        end
      end

      side_left_defn = side.is_a?(Hash) ? side[:left] : side
      side_right_defn = side.is_a?(Hash) ? side[:right] : side

      # Side Panel Left
      t = Geom::Transformation.new([0, 0, h_cm.cm])
      side_panel_l = add_child(defn, side_left_defn,  t, 'Left Side Panel')
      da_attr(side_panel_l, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")  # If full height, extend down into toe kick area
      da_attr(side_panel_l, 'lenx', "#{parent}!Thickness")
      da_attr(side_panel_l, 'leny', "#{parent}!cab_depth")
      da_attr(side_panel_l, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")  # If full height, subtract the extra part that extends into the toe kick area from the visible height
      da_attr(side_panel_l, 'back_groove_depth', "#{parent}!back_groove_slot_depth", nil, 'CENTIMETERS')
      da_attr(side_panel_l, 'back_groove_width', "#{parent}!back_groove_slot_width", nil, 'CENTIMETERS')
      da_attr(side_panel_l, 'back_groove_y', "#{parent}!bp_setback", nil, 'CENTIMETERS')
      da_attr(side_panel_l, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")  # Pass top panel type to side panel for use in its own formulas (to adjust for top panel if it's present)
      da_attr(side_panel_l, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")  # Pass base panel type to side panel for use in its own formulas (to adjust for base panel if it's present)
      MaterialHelper.apply(side_panel_l, materials[:carcass])
      side_panel_l.layer = layers[:carcass] if layers[:carcass]

      # Side Panel Right
      t = Geom::Transformation.new([w_cm.cm - t_cm.cm, 0, h_cm.cm])
      side_panel_r = add_child(defn, side_right_defn, t, 'Right Side Panel')
      da_attr(side_panel_r, 'x',    "#{parent}!cab_width - #{parent}!Thickness")
      da_attr(side_panel_r, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!sp_type, #{parent}!Thickness, 0, 0)")  # If full height, extend down into toe kick area
      da_attr(side_panel_r, 'lenx', "#{parent}!Thickness")
      da_attr(side_panel_r, 'leny', "#{parent}!cab_depth")
      da_attr(side_panel_r, 'lenz', "#{parent}!cab_height - (#{parent}!Toekick * #{parent}!tk_height) - (CHOOSE(#{parent}!sp_type, (tp_present + bp_present) * #{parent}!Thickness, 0, -#{parent}!tk_height * #{parent}!Toekick))")  # If full height, subtract the extra part that extends into the toe kick area from the visible height
      da_attr(side_panel_r, 'back_groove_depth', "#{parent}!back_groove_slot_depth", nil, 'CENTIMETERS')
      da_attr(side_panel_r, 'back_groove_width', "#{parent}!back_groove_slot_width", nil, 'CENTIMETERS')
      da_attr(side_panel_r, 'back_groove_y', "#{parent}!bp_setback", nil, 'CENTIMETERS')
      da_attr(side_panel_r, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")  # Pass top panel type to side panel for use in its own formulas (to adjust for top panel if it's present)
      da_attr(side_panel_r, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")  # Pass base panel type to side panel for use in its own formulas (to adjust for base panel if it's present)
      MaterialHelper.apply(side_panel_r, materials[:carcass])
      side_panel_r.layer = layers[:carcass] if layers[:carcass]

      # Base Panel
      t = Geom::Transformation.new([t_cm.cm, 0, tk_h_cm.cm + t_cm.cm])
      base_panel = add_child(defn, base,  t, 'Base Panel')
      da_attr(base_panel, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      da_attr(base_panel, 'z',      "(#{parent}!Toekick * #{parent}!tk_height) + #{parent}!Thickness")
      da_attr(base_panel, 'lenx',   "#{parent}!cab_width - 2 * CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      da_attr(base_panel, 'leny',   "#{parent}!cab_depth")
      da_attr(base_panel, 'lenz',   "#{parent}!Thickness")
      da_attr(base_panel, 'hidden', "CHOOSE(#{parent}!bp_type, False, True)")  # Hide if base panel type is 'open'
      MaterialHelper.apply(base_panel, materials[:carcass])
      base_panel.layer = layers[:carcass] if layers[:carcass]

      # Top Panel Back
      t = Geom::Transformation.new([t_cm.cm, 0, h_cm.cm - t_cm.cm])
      top_panel = add_child(defn, top,   t, 'Top Panel')
      da_attr(top_panel, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      da_attr(top_panel, 'z',      "#{parent}!cab_height")
      da_attr(top_panel, 'lenx',   "#{parent}!cab_width - 2 * CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      da_attr(top_panel, 'leny',   "CHOOSE(#{parent}!tp_type, #{parent}!cab_depth, #{parent}!st_width, #{parent}!st_width)")
      da_attr(top_panel, 'lenz',   "#{parent}!Thickness")
      da_attr(top_panel, 'hidden', "CHOOSE(#{parent}!tp_type, False, False, True)")  # Hide if top panel type is 'none'
      MaterialHelper.apply(top_panel, materials[:carcass])
      top_panel.layer = layers[:carcass] if layers[:carcass]

      # Top Front Panel
      t = Geom::Transformation.new([t_cm.cm, 0, h_cm.cm - t_cm.cm])
      top_front_panel = add_child(defn, top,   t, 'Top Front Panel')
      da_attr(top_front_panel, 'x',      "CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      da_attr(top_front_panel, 'y',      "#{parent}!cab_depth - #{parent}!st_width")
      da_attr(top_front_panel, 'z',      "#{parent}!cab_height")
      da_attr(top_front_panel, 'lenx',   "#{parent}!cab_width - 2 * CHOOSE(#{parent}!sp_type, 0, #{parent}!Thickness, #{parent}!Thickness)")
      da_attr(top_front_panel, 'leny',   "#{parent}!st_width")
      da_attr(top_front_panel, 'lenz',   "#{parent}!Thickness")
      da_attr(top_front_panel, 'hidden', "CHOOSE(#{parent}!tp_type, True, False, True)")  # Hide if top panel type is 'none'
      MaterialHelper.apply(top_front_panel, materials[:carcass])
      top_front_panel.layer = layers[:carcass] if layers[:carcass]

      # Back Panel
      t = Geom::Transformation.new([t_cm.cm, bp_sb_cm.cm, h_cm.cm - t_cm.cm])
      back_panel = add_child(defn, back,  t, 'Back Panel')
      da_attr(back_panel, 'x',    "#{parent}!Thickness - #{parent}!back_groove_effective")
      da_attr(back_panel, 'y',    "#{parent}!bp_setback")
      da_attr(back_panel, 'z',    "#{parent}!cab_height - CHOOSE(#{parent}!tp_type, #{parent}!Thickness, #{parent}!Thickness, 0)")
      da_attr(back_panel, 'lenx', "#{parent}!cab_width - 2 * #{parent}!Thickness + 2 * #{parent}!back_groove_effective")
      da_attr(back_panel, 'leny', "#{parent}!bp_thickness")
      da_attr(back_panel, 'lenz', "#{parent}!cab_height - (tp_present + bp_present) * #{parent}!Thickness - (#{parent}!Toekick * #{parent}!tk_height)")
      da_attr(back_panel, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")  # Pass top panel type to back panel for use in its own formulas
      da_attr(back_panel, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")  # Pass back panel type to back panel for use in its own formulas
      da_attr(back_panel, 'hidden', "CHOOSE(#{parent}!bk_type, False, True, True)")  # Hide if back panel type is 'none' or 'stretchers'
      MaterialHelper.apply(back_panel, materials[:carcass])
      back_panel.layer = layers[:carcass] if layers[:carcass]

      # Back Stretchers
      t = Geom::Transformation.new([t_cm.cm, bp_sb_cm.cm, h_cm.cm - t_cm.cm])
      back_stretcher = add_child(defn, back,  t, 'Back Stretcher')
      da_attr(back_stretcher, 'x',          "#{parent}!Thickness")
      da_attr(back_stretcher, 'y',          '0')
      da_attr(back_stretcher, 'z',          "#{parent}!tk_height * #{parent}!Toekick + #{parent}!st_width + bp_present * #{parent}!Thickness + copy * spacing")  # Position stretchers: first flush at bottom, last flush at top (space-between)
      da_attr(back_stretcher, 'lenx',       "#{parent}!cab_width - 2 * #{parent}!Thickness")
      da_attr(back_stretcher, 'leny',       "#{parent}!Thickness")
      da_attr(back_stretcher, 'lenz',       "#{parent}!st_width")
      da_attr(back_stretcher, 'tp_present', "CHOOSE(#{parent}!tp_type, 1, 1, 0)")  # Pass top panel type to back panel for use in its own formulas
      da_attr(back_stretcher, 'bp_present', "CHOOSE(#{parent}!bp_type, 1, 0)")  # Pass back panel type to back panel for use in its own formulas
      da_attr(back_stretcher, 'spacing',    "IF(copies > 0, (#{parent}!cab_height - (tp_present + bp_present) * #{parent}!Thickness - (#{parent}!Toekick * #{parent}!tk_height) - #{parent}!st_width) / copies, 0)")  # Space-between: distribute gaps between stretchers, first at bottom, last at top
      da_attr(back_stretcher, 'copies',     "#{parent}!bk_st_count - 1")  # Number of stretchers is one less than the number of spaces between them
      da_attr(back_stretcher, 'hidden',     "CHOOSE(#{parent}!bk_type, True, False, True)")  # Hide if back panel type is 'closed' or 'none'
      MaterialHelper.apply(back_stretcher, materials[:carcass])
      # Apply the layer to all elements inside the back stretcher group, since it is copied using the dc engine's copy mechanism which doesn't automatically apply the layer to copies.
      back_stretcher.definition.entities.each { |e| e.layer = layers[:carcass] if layers[:carcass] }
      back_stretcher.layer = layers[:carcass] if layers[:carcass]

      # Cabinet Groups that holds items such as (Doors, Drawers, Appliances, Opening,...etc) and they are either Vertical (stacked with horizontal dividers) or Horizontal (side by side with vertical dividers)
      grps_arr = grps.to_a
      prof_ext_max_in = 2.0 / 2.54  # 2 cm cap for profile group boundary extensions
      grps_arr.each_with_index do |(id, v), idx|
        # Compute drawer-face overlay extensions at group boundaries (in inches)
        above_ext_in = t_in
        if idx > 0
          prev_gt = grps_arr[idx - 1][1][:gt].to_s
          if prev_gt == 'separator' || prev_gt == 'divider'
            prev_gh_cm = grps_arr[idx - 1][1][:gh].to_f
            above_ext_in = (prev_gh_cm / 2.54) / 2.0
          elsif prev_gt == 'prof'
            prev_gh_cm = grps_arr[idx - 1][1][:gh].to_f
            above_ext_in = [(prev_gh_cm / 2.54) / 2.0, prof_ext_max_in].min
          end
        end
        below_ext_in = t_in
        if idx < grps_arr.size - 1
          next_gt = grps_arr[idx + 1][1][:gt].to_s
          if next_gt == 'separator' || next_gt == 'divider'
            next_gh_cm = grps_arr[idx + 1][1][:gh].to_f
            below_ext_in = (next_gh_cm / 2.54) / 2.0
          elsif next_gt == 'prof'
            next_gh_cm = grps_arr[idx + 1][1][:gh].to_f
            below_ext_in = [(next_gh_cm / 2.54) / 2.0, prof_ext_max_in].min
          end
        end

        GroupDC.create_group(model, defn, "#{parent}", id,
          drawer_face_defn: drawer_face_defn, door_leaf_defn: door_leaf_defn,
          door_handle_defn: door_handle_defn, drawer_handle_defn: drawer_handle_defn,
          panel_face_defn: panel_face_defn,
          groups_count: grps.size,
          above_ext: above_ext_in, below_ext: below_ext_in,
          materials: materials, layers: layers)
      end

      defn
    end

    # ================================================================
    # Low-level helpers
    # ================================================================

    # ================================================================
    # Recalculate group heights & z-positions after a cabinet scale.
    # Reads current dimensions from the instance, parses the groups
    # string, recomputes fill-group heights, and writes the updated
    # string back to the definition. The DC engine's own pending
    # redraw will pick up the new value.
    # ================================================================

    def self.recalculate_groups(instance)
      return false unless instance.valid?

      defn = instance.definition

      # Derive scale factors from the instance transformation.
      # The Scale tool modifies the transformation; we read the scale,
      # apply it to the stored carcass dimensions, and then strip the
      # scale from the transformation so the DC engine doesn't
      # double-apply it.
      #
      # IMPORTANT: we must NOT read from defn.bounds — the bounding box
      # includes overlay doors/drawers/handles that protrude beyond the
      # carcass, which would inflate cab_depth on every scale cycle.
      a       = instance.transformation.to_a
      x_scale = Geom::Vector3d.new(a[0], a[1], a[2]).length
      y_scale = Geom::Vector3d.new(a[4], a[5], a[6]).length
      z_scale = Geom::Vector3d.new(a[8], a[9], a[10]).length

      # Skip if no meaningful scale was applied (e.g. a move or attribute
      # change triggered the observer, or a redraw_dc normalised the
      # transformation back to 1.0).
      eps = 0.001
      return false if (x_scale - 1.0).abs < eps &&
                      (y_scale - 1.0).abs < eps &&
                      (z_scale - 1.0).abs < eps

      # Read the current carcass dimensions (immune to bounding-box drift)
      old_cab_w = defn.get_attribute(DA, 'cab_width').to_f
      old_cab_d = defn.get_attribute(DA, 'cab_depth').to_f
      old_cab_h = defn.get_attribute(DA, 'cab_height').to_f
      return false if old_cab_w <= 0 || old_cab_d <= 0 || old_cab_h <= 0

      cab_w = old_cab_w * x_scale
      cab_d = old_cab_d * y_scale
      len_z = old_cab_h * z_scale

      thickness = defn.get_attribute(DA, 'thickness').to_f
      toekick   = defn.get_attribute(DA, 'toekick').to_s == 'True' ? 1.0 : defn.get_attribute(DA, 'toekick').to_f
      tk_height = defn.get_attribute(DA, 'tk_height').to_f

      # Read from _groups_formula — the DC engine overwrites 'groups' during eval
      raw = defn.get_attribute(DA, '_groups_formula').to_s
      # Strip wrapping quotes: stored as "\"...\""
      raw = raw.gsub(/\A"|"\z/, '')

      interior_h = len_z - (toekick * tk_height) - 2.0 * thickness
      group_w    = (cab_w - 2.0 * thickness)  # interior width in inches

      groups = parse_groups_str(raw)
      return false if groups.empty?

      fill_count = groups.count { |g| g[:gf] == 1 }
      fixed_sum  = groups.reject { |g| g[:gf] == 1 }.sum { |g| g[:gh] }
      fill_h     = fill_count > 0 ? [(interior_h - fixed_sum) / fill_count, 0.0].max : 0.0

      z_offset = interior_h
      groups.each do |g|
        g[:gh] = fill_h if g[:gf] == 1
        g[:gw] = group_w
        z_offset -= g[:gh]
        g[:gz] = z_offset
      end

      entries = groups.map { |g|
        hdn_part  = g[:hdn].to_i == 1 ? ", :hdn=>1" : ""
        prid_part = (g[:gt].to_s == 'prof' && g[:prid] && !g[:prid].to_s.empty?) ? ", :prid=>#{g[:prid]}" : ""
        "#{g[:key]}: {:gt=>#{g[:gt]}, :gz=>#{g[:gz].round(6)}, :gh=>#{g[:gh].round(6)}, :gw=>#{g[:gw].round(6)}, :gf=>#{g[:gf]}#{hdn_part}#{prid_part}, :it=>#{g[:it]}}"
      }
      new_str = entries.join('; ')

      model = Sketchup.active_model
      model.start_operation('Update Groups', true, false, true)

      # Update cabinet master dimensions so child formulas see the scaled size
      defn.set_attribute(DA, 'cab_width',           cab_w.round(6).to_s)
      defn.set_attribute(DA, '_cab_width_formula',  cab_w.round(6).to_s)
      defn.set_attribute(DA, 'cab_depth',           cab_d.round(6).to_s)
      defn.set_attribute(DA, '_cab_depth_formula',  cab_d.round(6).to_s)
      defn.set_attribute(DA, 'cab_height',          len_z.round(6).to_s)
      defn.set_attribute(DA, '_cab_height_formula', len_z.round(6).to_s)

      # For L-shaped corner cabinets, wing_width (w_cm/2.54) must be scaled
      # proportionally with cab_width so that extract_config can recover the
      # correct door/wing width when the edit dialog is opened after a scale.
      if defn.get_attribute('ml_cabinets', 'corner_type').to_s == 'l-shaped'
        old_wing_w = defn.get_attribute(DA, 'wing_width').to_f
        if old_wing_w > 0 && old_cab_w > 0
          new_wing_w = old_wing_w * x_scale
          defn.set_attribute(DA, 'wing_width', new_wing_w.round(6).to_s)
        end
      end

      defn.set_attribute(DA, 'groups',          "\"#{new_str}\"")
      defn.set_attribute(DA, '_groups_formula', "\"#{new_str}\"")

      # Recalculate item heights/positions inside each group
      recalculate_items(defn, groups)

      # Reset all door/drawer open states — scaling snaps geometry closed
      # but the stored attributes must match so toggling works correctly.
      reset_open_states(defn)

      # Strip the scale from the instance transformation so the DC
      # engine doesn't double-apply it.  Keep position + rotation intact.
      tr = instance.transformation
      origin = tr.origin
      xaxis = Geom::Vector3d.new(a[0], a[1], a[2]).normalize
      yaxis = Geom::Vector3d.new(a[4], a[5], a[6]).normalize
      zaxis = Geom::Vector3d.new(a[8], a[9], a[10]).normalize
      instance.transformation = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)

      model.commit_operation
      return true
    end

    # ================================================================
    # Reset door_open and is_open attributes on all door/drawer Item
    # instances inside the cabinet definition. Called after a scale so
    # the stored state stays in sync with the (now closed) geometry.
    # ================================================================

    def self.reset_open_states(defn)
      defn.entities.each do |group_ent|
        next unless group_ent.is_a?(Sketchup::ComponentInstance)
        next unless group_ent.definition.get_attribute(DA, 'name') == 'Group'

        group_ent.definition.entities.each do |item_ent|
          next unless item_ent.is_a?(Sketchup::ComponentInstance)
          next unless item_ent.definition.get_attribute(DA, 'name') == 'Item'

          i_type = item_ent.get_attribute(DA, 'i_type').to_s
          next unless i_type == 'door' || i_type == 'drwr'
          next unless item_ent.get_attribute('ml_cabinets', 'is_open') == true

          item_ent.set_attribute('ml_cabinets', 'is_open', false)
          item_ent.set_attribute(DA, 'door_open',          '0')
          item_ent.set_attribute(DA, '_door_open_formula', '0')
        end
      end
    end

    # ================================================================
    # Recalculate item heights & z-positions within each group.
    # Called after recalculate_groups has updated the group heights.
    # Walks the Group instances inside the cabinet definition, reads
    # their g_items string, recomputes fill-item heights using the
    # new group height, and writes the updated g_items back.
    # ================================================================

    def self.recalculate_items(defn, groups)
      defn.entities.each do |ent|
        next unless ent.is_a?(Sketchup::ComponentInstance)
        next unless ent.definition.get_attribute(DA, 'name') == 'Group'

        group_id = ent.definition.get_attribute(DA, 'id').to_s
        group    = groups.find { |g| g[:key] == group_id }
        next unless group

        g_type  = group[:gt].to_s.strip
        # Separator/divider/profile groups have no items — skip recalculation
        next if g_type == 'separator' || g_type == 'divider' || g_type == 'prof'
        group_h = group[:gh]  # in inches (from instance.bounds via recalculate_groups)
        group_w = group[:gw]  # in inches (from instance.bounds via recalculate_groups)

        raw = ent.get_attribute(DA, 'g_items').to_s
        items = parse_items_str(raw)
        next if items.empty?

        if g_type == 'hori'
          # Horizontal layout: recalculate widths along X
          fill_count = items.count { |i| i[:iwf] == 1 }
          fixed_sum  = items.reject { |i| i[:iwf] == 1 }.sum { |i| i[:iw].to_f }
          fill_w     = fill_count > 0 ? [(group_w - fixed_sum) / fill_count, 0.0].max : 0.0

          x_offset = 0.0
          items.each do |i|
            i[:ix] = x_offset
            i[:iw] = fill_w if i[:iwf] == 1
            x_offset += i[:iw].to_f
            # Height spans the full group for horizontal items
            i[:ih] = group_h
            i[:iz] = 0.0
          end
        else
          # Vertical layout: recalculate heights along Z (top-to-bottom, matching JS list order)
          fill_count = items.count { |i| i[:if] == 1 }
          fixed_sum  = items.reject { |i| i[:if] == 1 }.sum { |i| i[:ih] }
          fill_h     = fill_count > 0 ? [(group_h - fixed_sum) / fill_count, 0.0].max : 0.0

          z_offset = group_h
          items.each do |i|
            i[:ih] = fill_h if i[:if] == 1
            z_offset -= i[:ih]
            i[:iz] = z_offset
            # Width spans the full group for vertical items
            i[:ix] = 0.0
            i[:iw] = group_w
          end
        end

        entries = items.map { |i|
          parts = i.reject { |k, _| k == :key }.map { |k, val|
            val_str = val.is_a?(Float) ? val.round(6).to_s : val.to_s
            ":#{k}=>#{val_str}"
          }
          "#{i[:key]}: [#{parts.join(', ')}]"
        }
        new_items_str = entries.join('; ')

        ent.set_attribute(DA, 'g_items', new_items_str)

        # Sync each Item instance's position/size attrs with the recalculated values
        # so the stored values stay consistent with the updated g_items string.
        items_by_key = items.each_with_object({}) { |i, h| h[i[:key]] = i }
        ent.definition.entities.grep(Sketchup::ComponentInstance).each do |item_ent|
          next unless item_ent.definition.get_attribute(DA, 'name') == 'Item'
          item = items_by_key[item_ent.definition.get_attribute(DA, 'id').to_s]
          next unless item
          item_data = { iz: item[:iz].to_f, ix: item[:ix].to_f,
                        ih: item[:ih].to_f, iw: item[:iw].to_f }
          ItemDC.update_item_position(item_ent, item_data, g_type)
        end
      end
    end

    # Parse the groups attribute string into an array of hashes.
    # Each hash: { key:, gt:, gz:, gh:, gf:, it: }
    def self.parse_groups_str(str)
      groups = []
      str.scan(/(g\d+):\s*\{([^}]+)\}/) do |key, body|
        next if key == 'g0'
        g = { key: key }
        g[:gt]  = body[/:gt=>([^,}]+)/, 1].to_s.strip
        g[:gz]  = body[/:gz=>([^,}]+)/, 1].to_f
        g[:gh]  = body[/:gh=>([^,}]+)/, 1].to_f
        g[:gw]  = body[/:gw=>([^,}]+)/, 1].to_f
        g[:gf]  = body[/:gf=>([^,}]+)/, 1].to_i
        g[:hdn] = body[/:hdn=>([^,}]+)/, 1].to_i
        g[:prid] = body[/:prid=>([^,}]+)/, 1].to_s.strip
        g[:it]  = body[/:it=>(.+)/, 1].to_s
        groups << g
      end
      groups
    end

    # Parse the g_items attribute string into an array of hashes.
    # Each hash: { key:, it:, iz:, ih:, if:, ... (extra keys preserved) }
    def self.parse_items_str(str)
      items = []
      str.scan(/(i\d+):\s*\[([^\]]+)\]/) do |key, body|
        i = { key: key }
        body.scan(/:(\w+)=>([^,\]]+)/) do |k, v|
          sym = k.to_sym
          i[sym] = case sym
                   when :iz, :ih, :ix, :iw, :oa, :hrot then v.to_f
                   when :if, :iwf, :shlv, :hdn then v.to_i
                   else v.strip
                   end
        end
        items << i
      end
      items
    end

    def self.add_child(parent_defn, child_defn, transform, instance_name)
      inst = parent_defn.entities.add_instance(child_defn, transform)
      inst.name = instance_name
      inst
    end

    # Trigger DC formula evaluation on a component instance.
    # SketchUp 2024: $dc_observers is a DCObservers object. It may or may not
    # expose get_latest publicly — fall back to the @dc1 internal reference
    # which is always present when the DC extension is loaded.
    def self.redraw_dc(instance)
      return unless instance.is_a?(Sketchup::ComponentInstance)
      unless defined?($dc_observers)
        puts '  ⚠  Dynamic Components extension not active.'
        puts '     Enable it in Window → Extension Manager and rebuild.'
        return
      end
      handler = if $dc_observers.respond_to?(:get_latest)
                  $dc_observers.get_latest
                else
                  $dc_observers.instance_variable_get(:@dc1)
                end
      if handler&.respond_to?(:redraw_with_undo)
        handler.redraw_with_undo(instance)
      else
        puts '  ⚠  Could not trigger DC evaluation automatically.'
        puts '     Right-click → Dynamic Components → Redraw to update panels.'
      end
    rescue => e
      puts "  ⚠  DC redraw error: #{e.message}"
    end

    # Serialize a group's items array into a compact string embedded inside groups_str.
    # Uses []/: as delimiters — avoids { and } so the FIND("}") pattern in group formulas
    # still unambiguously finds the outer group closing brace.
    # Length values are pre-converted to inches to match all other DC length storage.
    # Example output: "i1:[it:drwr,ih:7.874015,dbox:auto,tclr:0.787402,bclr:0.393701];i2:[it:door,ih:0.0,hngs:2,toff:15,boff:15]"
    def self.serialize_items(items)
      return '' if items.nil? || items.empty?
      items.each_with_index.map { |item, idx|
        parts = ["it:#{item[:it]}"]
        parts << "ih:#{(item[:ih].to_f / 2.54).round(6)}"     if item.key?(:ih)
        parts << "iw:#{(item[:iw].to_f / 2.54).round(6)}"     if item.key?(:iw)
        parts << "shlv:#{item[:shlv]}"                        if item[:shlv]
        parts << "hngs:#{item[:hngs]}"                        if item[:hngs]
        parts << "toff:#{item[:toff]}"                        if item[:toff]
        parts << "boff:#{item[:boff]}"                        if item[:boff]
        parts << "dbox:#{item[:dbox]}"                        if item[:dbox]
        parts << "tclr:#{(item[:tclr].to_f / 2.54).round(6)}" if item[:tclr]
        parts << "bclr:#{(item[:bclr].to_f / 2.54).round(6)}" if item[:bclr]
        parts << "shlv:#{item[:shlv]}"                        if item[:shlv]
        parts << "apid:#{item[:apid]}"                        if item[:apid]
        parts << "prid:#{item[:prid]}"                        if item[:prid]
        parts << "prmid:#{item[:prmid]}"                      if item[:prmid] && !item[:prmid].to_s.strip.empty?
        parts << "prmg:#{item[:prmg]}"                        if item[:prmg]  && !item[:prmg].to_s.strip.empty?
        parts << "hoff:#{(item[:hoff].to_f / 2.54).round(6)}" if item.key?(:hoff)
        parts << "voff:#{(item[:voff].to_f / 2.54).round(6)}" if item.key?(:voff)
        parts << "hrot:#{item[:hrot].to_f.round(3)}"           if item.key?(:hrot)
        parts << "hdl:#{item[:hdl]}"                           if item[:hdl] && !item[:hdl].to_s.strip.empty?
        parts << "hmat:#{item[:hmat]}"                         if item[:hmat] && !item[:hmat].to_s.strip.empty?
        parts << "hmatg:#{item[:hmatg]}"                       if item[:hmatg] && !item[:hmatg].to_s.strip.empty?
        parts << "dfid:#{item[:dfid]}"                         if item[:dfid] && !item[:dfid].to_s.empty?
        parts << "dlid:#{item[:dlid]}"                         if item[:dlid] && !item[:dlid].to_s.empty?
        parts << "plid:#{item[:plid]}"                         if item[:plid] && !item[:plid].to_s.empty?
        parts << "dsub:#{item[:dsub]}"                         if item[:dsub] && !item[:dsub].to_s.empty?
        parts << "mat:#{item[:mat]}"                           if item[:mat]  && !item[:mat].to_s.strip.empty?
        parts << "matg:#{item[:matg]}"                         if item[:matg] && !item[:matg].to_s.strip.empty?
        parts << "oa:#{item[:oa].to_f.round(2)}"               if item.key?(:oa)
        parts << "hdn:1"                                       if item[:hidden]
        "i#{idx + 1}:[#{parts.join(',')}]"
      }.join(';')
    end

    def self.da_attr(defn, key, value, label = nil, units = 'STRING', access = "NONE")
      defn.set_attribute(DA, key,                 value)
      defn.set_attribute(DA, "_#{key}_formula",   value)
      defn.set_attribute(DA, "_#{key}_formlabel", label)
      defn.set_attribute(DA, "_#{key}_units",     units)
      defn.set_attribute(DA, "_#{key}_access",    access)
    end

    # ================================================================
    # Extract the stored dialog config JSON from a cabinet instance.
    # Returns a string-keyed Hash ready to send to JS, or nil.
    # ================================================================

    def self.extract_config(instance)
      return nil unless instance.is_a?(Sketchup::ComponentInstance)
      json = instance.definition.get_attribute('ml_cabinets', 'config_json')
      return nil unless json.is_a?(String) && !json.empty?
      config = JSON.parse(json, symbolize_names: true)

      # Snapshot current dimensions from the live DA attributes.
      # After a Scale-tool resize the ScaleObserver updates
      # cab_width/cab_height/cab_depth, so these reflect the actual
      # size — which may differ from the original config.
      defn = instance.definition
      live_w_in = defn.get_attribute(DA, 'cab_width').to_f
      live_h_in = defn.get_attribute(DA, 'cab_height').to_f
      live_d_in = defn.get_attribute(DA, 'cab_depth').to_f

      if live_w_in > 0 && live_h_in > 0 && live_d_in > 0
        unit = (config[:unit] || 'cm').to_s

        # For corner cabinets, cab_width and cab_depth store the total footprint
        # dimensions, not the door/wing width the dialog expects.  Recover the
        # original user-facing dimensions before repopulating the form.
        corner_type = defn.get_attribute('ml_cabinets', 'corner_type').to_s

        effective_w_in = case corner_type
        when 'blind'
          # total_w = door_w + depth + BLIND_MARGIN
          # Recover door_w by subtracting the other components.
          blind_margin_in = unit == 'in' ? 3.0 : (CornerCabinetDC::BLIND_MARGIN_CM / 2.54)
          live_w_in - live_d_in - blind_margin_in
        when 'l-shaped'
          # wing_width stores the original w_cm/2.54 (one wing width).
          # live_d_in is also total footprint (w+d)/2.54 for l-shaped, so
          # we derive it from wing_width as well (see effective_d_in below).
          wing_w = defn.get_attribute(DA, 'wing_width').to_f
          wing_w > 0 ? wing_w : live_w_in
        else
          live_w_in
        end

        # live_d_in for l-shaped is the total footprint depth (w_cm + d_cm)/2.54.
        # The dialog "depth" field expects the wing depth only.
        effective_d_in = case corner_type
        when 'l-shaped'
          wing_w = defn.get_attribute(DA, 'wing_width').to_f
          wing_w > 0 ? (live_d_in - wing_w) : live_d_in
        else
          live_d_in
        end

        live_hff_in = defn.get_attribute('ml_cabinets', 'hff_in').to_f

        if unit == 'in'
          config[:width]            = effective_w_in.round(4)
          config[:height]           = live_h_in.round(4)
          config[:depth]            = effective_d_in.round(4)
          config[:height_from_floor] = live_hff_in.round(4)
        else
          config[:width]            = (effective_w_in * 2.54).round(4)
          config[:height]           = (live_h_in * 2.54).round(4)
          config[:depth]            = (effective_d_in * 2.54).round(4)
          config[:height_from_floor] = (live_hff_in * 2.54).round(4)
        end
      end

      config

    rescue => e
      puts "MLCabinets: extract_config error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ================================================================
    # Update an existing cabinet instance in-place with a new config.
    # Rebuilds the definition geometry while keeping the instance's
    # transformation (position, rotation) unchanged.
    # ================================================================

    def self.update_cabinet(instance, config)
      return nil unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?

      model = Sketchup.active_model
      old_defn = instance.definition

      # Capture old height-from-floor (in inches) before swapping definitions
      old_hff_in = old_defn.get_attribute('ml_cabinets', 'hff_in').to_f

      # Build a brand-new definition from the updated config
      result = build_definition(config)
      return nil unless result

      new_defn   = result[:defn]
      new_hff_in = (result[:params][:hff_cm].to_f / 2.54)

      model.start_operation('Edit Cabinet', true)

      begin
        # Swap the instance to the new definition, preserving transformation
        instance.definition = new_defn

        # Adjust the instance's Z translation when height-from-floor changed.
        # The hff is encoded as a Z offset in the instance transformation; we
        # apply only the delta so X/Y position and any rotation are preserved.
        delta_z = new_hff_in - old_hff_in
        if delta_z.abs > 0.0001
          move = Geom::Transformation.new([0, 0, delta_z])
          instance.transformation = move * instance.transformation
        end

        # Clean up the old orphaned definition (if no other instances reference it)
        if old_defn != new_defn && old_defn.instances.empty?
          model.definitions.remove(old_defn)
        end

        # Update the stored config JSON on the new definition
        new_defn.set_attribute('ml_cabinets', 'config_json', JSON.generate(config))

        model.commit_operation

        # DC evaluation must happen OUTSIDE any open operation
        redraw_dc(instance)

        # Re-attach scale observer
        MLCabinets::UI::ScaleObserverManager.attach_to(instance)

        # Purge orphaned definitions and unused materials (deferred)
        purge_unused(model)

        instance
      rescue => e
        model.abort_operation
        puts "❌ Edit cabinet failed: #{e.message}"
        e.backtrace.first(6).each { |line| puts "    #{line}" }
        nil
      end
    end

    # ================================================================
    # Bulk-edit helpers
    # ================================================================

    # Compare multiple cabinet configs and produce a merged config plus
    # a list of "mixed" field paths where values differ across cabinets.
    #
    # Returns: { merged: Hash, mixed: Array<String> }
    #   merged — a config hash where shared values are kept and differing
    #            values use the first cabinet's value (JS will overlay the
    #            mixed indicator).
    #   mixed  — flat array of dot-path strings, e.g. ["width", "toe_kick.height",
    #            "construction.panel_thickness", "groups"]
    def self.merge_configs(configs)
      return { merged: configs.first, mixed: [] } if configs.size == 1

      mixed = []
      merged = _deep_merge_collect(configs.first, configs, '', mixed)

      # Check if group/item structures are identical across all cabinets
      groups_lists = configs.map { |c| c['groups'] || c[:groups] || [] }
      unless _configs_same_structure?(groups_lists)
        mixed << 'groups' unless mixed.include?('groups')
      end

      { merged: merged, mixed: mixed }
    end

    # Deep-merge a partial config (only user-changed fields) into an
    # original full config. Keys present in partial overwrite original;
    # keys absent in partial are left untouched.
    # Normalises all keys to symbols so string/symbol mismatches are safe.
    def self.deep_merge_partial(original, partial)
      return original unless partial.is_a?(Hash) && original.is_a?(Hash)

      result = original.dup
      partial.each do |key, value|
        sym = key.to_sym
        if value.is_a?(Hash) && result[sym].is_a?(Hash)
          result[sym] = deep_merge_partial(result[sym], value)
        else
          result[sym] = value
        end
      end
      result
    end

    private

    # Recursively walk the first config and compare each leaf against
    # the same path in all other configs. Builds the mixed-paths list.
    def self._deep_merge_collect(base, all_configs, prefix, mixed)
      return base unless base.is_a?(Hash)

      result = {}
      base.each do |key, val|
        path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"

        if key.to_s == 'groups'
          # Groups are handled separately (structure check above)
          result[key] = val
          next
        end

        if val.is_a?(Hash)
          # Recurse into nested hashes
          result[key] = _deep_merge_collect(val, all_configs, path, mixed)
        elsif val.is_a?(Array)
          # For arrays, check equality across all configs
          others_match = all_configs[1..].all? { |c| _dig_value(c, key, prefix) == val }
          result[key] = val
          mixed << path unless others_match
        else
          # Leaf value — compare across all configs
          others_match = all_configs[1..].all? { |c| _dig_value(c, key, prefix) == val }
          result[key] = val
          mixed << path unless others_match
        end
      end
      result
    end

    # Dig a value from a config hash by key and dot-prefix path.
    def self._dig_value(config, key, prefix)
      return nil unless config.is_a?(Hash)
      if prefix.empty?
        config[key] || config[key.to_s] || config[key.to_sym]
      else
        # Walk the dot path to reach the parent, then read the key
        parts = prefix.split('.')
        node = config
        parts.each do |p|
          node = node[p] || node[p.to_s] || node[p.to_sym]
          return nil unless node.is_a?(Hash)
        end
        node[key] || node[key.to_s] || node[key.to_sym]
      end
    end

    # Check if all groups arrays have the same structure: same number of
    # groups, same group types, same number of items per group, same item types.
    def self._configs_same_structure?(groups_lists)
      return true if groups_lists.size <= 1
      ref = _structure_signature(groups_lists.first)
      groups_lists[1..].all? { |gl| _structure_signature(gl) == ref }
    end

    def self._structure_signature(groups)
      return [] unless groups.is_a?(Array)
      groups.map do |g|
        g = _sym_or_str(g)
        gt = g['type'] || g[:type] || ''
        items = (g['items'] || g[:items] || []).map do |i|
          i = _sym_or_str(i)
          i['type'] || i[:type] || ''
        end
        { type: gt, items: items }
      end
    end

    def self._sym_or_str(h)
      h.is_a?(Hash) ? h : {}
    end
  end
end
