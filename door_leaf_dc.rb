# ML Cabinets - Door Leaf DC
# Loads a door panel preset from the library and places it as a child
# of the Item. The leaf is sized to match the item envelope (the full
# opening) and sits flush at the front, extending beyond the item
# boundaries via per-edge overlay extensions (dl_zt, dl_zb, dl_xl, dl_xr).
# If no preset is found, returns nil so the caller can skip the leaf.

require 'sketchup.rb'
require 'json'

module MLCabinets
  module DoorLeafDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Load door leaf definition from library SKP.
    # Looks in libraries/panels/ (unified panel library).
    # Returns the ComponentDefinition or nil on failure.
    # ----------------------------------------------------------------
    def self.load_definition(model, preset_id)
      return nil unless preset_id

      preset_name = resolve_preset_name(preset_id)
      return nil unless preset_name

      skp_path = find_skp_path(preset_name)
      unless skp_path
        puts "MLCabinets: DoorLeafDC — SKP not found for preset '#{preset_name}'" if MLCabinets::DEBUG
        return nil
      end

      defn = model.definitions.load(skp_path, allow_newer: true)
      puts "MLCabinets: Loaded door leaf preset '#{preset_name}'" if MLCabinets::DEBUG
      defn
    rescue => e
      puts "MLCabinets: DoorLeafDC.load_definition error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a door leaf inside the item.
    #
    # A unique wrapper ComponentDefinition is created per door item so
    # that the handle can be a child of DoorLeaf without mutating the
    # shared loaded panel preset definition.
    #
    # Hierarchy created inside parent_defn:
    #   DoorLeaf (wrapper inst — unique per item)
    #     ├── DoorLeafPanel (loaded preset, sized to match wrapper)
    #     └── DoorHandle   (optional, via handle_defn)
    #
    # Returns [leaf_inst, panel_inst, handle_inst]
    # Materials must be applied to panel_inst and handle_inst directly,
    # NOT to leaf_inst — applying to the wrapper makes_unique all children
    # at once, causing the handle_inst reference to become stale.
    # ----------------------------------------------------------------
    def self.create_door_leaf(model, parent_defn, item_name, leaf_defn,
                              handle_defn: nil, item_data: {}, door_sub: nil, abs_z_in: 0.0,
                              indication_layer: nil)
      return [nil, nil] unless leaf_defn

      p = item_name

      # --- Unique wrapper definition for this door item ---
      wrapper_defn = model.definitions.add('DoorLeaf')
      wrapper_defn.description = 'Door Leaf DC — ML Cabinets'
      wrapper_defn.set_attribute(DA, 'name',         'DoorLeaf')
      wrapper_defn.set_attribute(DA, '_name_access', 'NONE')
      # Metadata on definition so DC resolves custom attr units correctly.
      # (DC reads _units from the definition, not the instance, for custom attrs.)
      wrapper_defn.set_attribute(DA, '_hdl_hoff_units', 'CENTIMETERS')
      wrapper_defn.set_attribute(DA, '_hdl_voff_units', 'CENTIMETERS')
      wrapper_defn.set_attribute(DA, '_hdl_rot_units',  'DEGREES')

      # Panel preset instance inside the wrapper, tracks wrapper size
      panel_inst = wrapper_defn.entities.add_instance(leaf_defn, Geom::Transformation.new([0, 0, 0]))
      panel_inst.name = 'DoorLeafPanel'
      da_attr(panel_inst, 'lenx', 'DoorLeaf!lenx')
      da_attr(panel_inst, 'leny', 'DoorLeaf!leny')
      da_attr(panel_inst, 'lenz', 'DoorLeaf!lenz')

      # --- Wrapper instance placed in parent (Item) ---
      inst = parent_defn.entities.add_instance(wrapper_defn, Geom::Transformation.new([0, 0, 10]))
      inst.name = 'DoorLeaf'

      # Position: CHOOSE(ov_type, inset, partial, full)
      da_attr(inst, 'x', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!dl_xl + #{p}!clearance, -#{p}!dl_xl)")
      da_attr(inst, 'y', "CHOOSE(#{p}!ov_type, #{p}!i_depth - #{p}!thickness, #{p}!i_depth, #{p}!i_depth)")
      da_attr(inst, 'z', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!dl_zb + #{p}!clearance, -#{p}!dl_zb)")

      # Size: CHOOSE(ov_type, inset, partial, full)
      da_attr(inst, 'lenx', "CHOOSE(#{p}!ov_type, #{p}!i_width - 2 * #{p}!clearance, #{p}!i_width + #{p}!dl_xl + #{p}!dl_xr - 2 * #{p}!clearance, #{p}!i_width + #{p}!dl_xl + #{p}!dl_xr)")
      da_attr(inst, 'leny', "#{p}!thickness")
      da_attr(inst, 'lenz', "CHOOSE(#{p}!ov_type, #{p}!i_height - 2 * #{p}!clearance, #{p}!i_height + #{p}!dl_zb + #{p}!dl_zt - 2 * #{p}!clearance, #{p}!i_height + #{p}!dl_zb + #{p}!dl_zt)")

      # Pass-through attrs consumed by the handle DC formulas.
      # Store in cm with CENTIMETERS units so SketchUp DC converts to inches
      # correctly in formula evaluation (avoids model-unit ambiguity).
      da_attr(inst, 'hdl_hoff', (item_data[:hoff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(inst, 'hdl_voff', (item_data[:voff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(inst, 'hdl_rot',  item_data[:hrot].to_f.round(3).to_s, units: 'DEGREES')
      da_attr(inst, 'clearance', "#{p}!clearance")

      # Rest-state open/close rotation — preserves visual angle after DC re-evaluation.
      # During animation the transformation is manipulated directly; this formula
      # snaps to the correct final angle once door_open is committed.
      case door_sub.to_s
      when 'door-hinge-right'
        da_attr(inst, 'rotz', "IF(#{p}!door_open, -(#{p}!oa / 100 * 90), 0)", units: 'DEGREES')
      when 'door-hinge-top'
        da_attr(inst, 'rotx', "IF(#{p}!door_open, -(#{p}!oa / 100 * 90), 0)", units: 'DEGREES')
      when 'door-hinge-bottom'
        da_attr(inst, 'rotx', "IF(#{p}!door_open, #{p}!oa / 100 * 90, 0)", units: 'DEGREES')
      else
        # default: hinge-left
        da_attr(inst, 'rotz', "IF(#{p}!door_open, #{p}!oa / 100 * 90, 0)", units: 'DEGREES')
      end

      # --- Handle inside the leaf wrapper ---
      handle_inst = if handle_defn
        HandleDC.create_door_handle_in_leaf(model, wrapper_defn, inst.name, handle_defn,
                                            door_sub: door_sub, abs_z_in: abs_z_in)
      end

      # --- Door open-side indication lines ---
      add_indication_lines(model, wrapper_defn, 'DoorLeaf', door_sub, indication_layer)

      [inst, panel_inst, handle_inst]
    rescue => e
      puts "MLCabinets: DoorLeafDC.create_door_leaf error — #{e.message}" if MLCabinets::DEBUG
      [nil, nil, nil]
    end

    # ----------------------------------------------------------------
    # Place two door leaf instances side by side inside the item.
    # Each leaf covers half the width with a clearance gap between them.
    # Left leaf extends by dl_xl on the left; right leaf extends by
    # dl_xr on the right. The centre gap is 2 × clearance.
    #
    # Each leaf uses a unique wrapper definition so their handles can
    # live as children of DoorLeafL / DoorLeafR respectively.
    #
    # Returns [[left_inst, right_inst], [left_panel, right_panel], [left_hdl, right_hdl]]
    # Materials must be applied to the panel instances and handle instances
    # directly — NOT to the wrapper instances (see create_door_leaf comment).
    # ----------------------------------------------------------------
    def self.create_double_door_leaf(model, parent_defn, item_name, leaf_defn,
                                     handle_defn: nil, item_data: {}, abs_z_in: 0.0,
                                     indication_layer: nil)
      return [[], []] unless leaf_defn

      p = item_name

      # --- Left leaf wrapper ---
      left_wrapper_defn = model.definitions.add('DoorLeafL')
      left_wrapper_defn.description = 'Door Leaf DC — ML Cabinets'
      left_wrapper_defn.set_attribute(DA, 'name',         'DoorLeafL')
      left_wrapper_defn.set_attribute(DA, '_name_access', 'NONE')
      left_wrapper_defn.set_attribute(DA, '_hdl_hoff_units', 'CENTIMETERS')
      left_wrapper_defn.set_attribute(DA, '_hdl_voff_units', 'CENTIMETERS')
      left_wrapper_defn.set_attribute(DA, '_hdl_rot_units',  'DEGREES')
      left_panel = left_wrapper_defn.entities.add_instance(leaf_defn, Geom::Transformation.new([0, 0, 0]))
      left_panel.name = 'DoorLeafPanel'
      da_attr(left_panel, 'x', 'DoorLeafL!lenx')
      da_attr(left_panel, 'lenx', 'DoorLeafL!lenx')
      da_attr(left_panel, 'leny', 'DoorLeafL!leny')
      da_attr(left_panel, 'lenz', 'DoorLeafL!lenz')

      # mirror the left panel
      scaleing = Geom::Transformation.scaling(-1, 1, 1)
      transform = Geom::Transformation.new([0, 0, 0]) * scaleing
      left_panel.transform!(transform)

      left = parent_defn.entities.add_instance(left_wrapper_defn, Geom::Transformation.new([0, 0, 0]))
      left.name = 'DoorLeafL'

      # Position: CHOOSE(ov_type, inset, partial, full)
      da_attr(left, 'x', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!dl_xl + #{p}!clearance, -#{p}!dl_xl)")
      da_attr(left, 'y', "CHOOSE(#{p}!ov_type, #{p}!i_depth - #{p}!thickness, #{p}!i_depth, #{p}!i_depth)")
      da_attr(left, 'z', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!dl_zb + #{p}!clearance, -#{p}!dl_zb)")

      # Width: half the total span with clearance logic per overlay type
      # Inset: half the opening minus 2×clearance (outer edge + centre gap)
      # Partial: half the overlay span minus 2×clearance (outer + centre)
      # Full: half the overlay span minus clearance for centre gap only
      da_attr(left, 'lenx', "CHOOSE(#{p}!ov_type, #{p}!i_width / 2 - 2 * #{p}!clearance, (#{p}!i_width + #{p}!dl_xl + #{p}!dl_xr) / 2 - 2 * #{p}!clearance, (#{p}!i_width + #{p}!dl_xl + #{p}!dl_xr) / 2 - #{p}!clearance)")
      da_attr(left, 'leny', "#{p}!thickness")
      da_attr(left, 'lenz', "CHOOSE(#{p}!ov_type, #{p}!i_height - 2 * #{p}!clearance, #{p}!i_height + #{p}!dl_zb + #{p}!dl_zt - 2 * #{p}!clearance, #{p}!i_height + #{p}!dl_zb + #{p}!dl_zt)")

      # Pass-through attrs for handle DC formulas (cm, CENTIMETERS units).
      da_attr(left, 'hdl_hoff', (item_data[:hoff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(left, 'hdl_voff', (item_data[:voff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(left, 'hdl_rot',  item_data[:hrot].to_f.round(3).to_s, units: 'DEGREES')
      da_attr(left, 'clearance', "#{p}!clearance")
      # Rest-state rotation: left leaf opens counter-clockwise (positive rotz)
      da_attr(left, 'rotz', "IF(#{p}!door_open, #{p}!oa / 100 * 90, 0)", units: 'DEGREES')

      # --- Right leaf wrapper ---
      right_wrapper_defn = model.definitions.add('DoorLeafR')
      right_wrapper_defn.description = 'Door Leaf DC — ML Cabinets'
      right_wrapper_defn.set_attribute(DA, 'name',         'DoorLeafR')
      right_wrapper_defn.set_attribute(DA, '_name_access', 'NONE')
      right_wrapper_defn.set_attribute(DA, '_hdl_hoff_units', 'CENTIMETERS')
      right_wrapper_defn.set_attribute(DA, '_hdl_voff_units', 'CENTIMETERS')
      right_wrapper_defn.set_attribute(DA, '_hdl_rot_units',  'DEGREES')
      right_panel = right_wrapper_defn.entities.add_instance(leaf_defn, Geom::Transformation.new([0, 0, 0]))
      right_panel.name = 'DoorLeafPanel'
      da_attr(right_panel, 'lenx', 'DoorLeafR!lenx')
      da_attr(right_panel, 'leny', 'DoorLeafR!leny')
      da_attr(right_panel, 'lenz', 'DoorLeafR!lenz')

      right = parent_defn.entities.add_instance(right_wrapper_defn, Geom::Transformation.new([0, 0, 10]))
      right.name = 'DoorLeafR'

      # Position: starts at centre line + clearance gap
      # Inset: half the opening + clearance
      # Partial: half overlay span from left edge + clearance
      # Full: half overlay span from left edge + clearance (centre gap only)
      da_attr(right, 'x', "CHOOSE(#{p}!ov_type, #{p}!i_width / 2 + #{p}!clearance, -#{p}!dl_xl + (#{p}!i_width + #{p}!dl_xl + #{p}!dl_xr) / 2 + #{p}!clearance, -#{p}!dl_xl + (#{p}!i_width + #{p}!dl_xl + #{p}!dl_xr) / 2 + #{p}!clearance)")
      da_attr(right, 'y', "CHOOSE(#{p}!ov_type, #{p}!i_depth - #{p}!thickness, #{p}!i_depth, #{p}!i_depth)")
      da_attr(right, 'z', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!dl_zb + #{p}!clearance, -#{p}!dl_zb)")

      da_attr(right, 'lenx', "CHOOSE(#{p}!ov_type, #{p}!i_width / 2 - 2 * #{p}!clearance, (#{p}!i_width + #{p}!dl_xl + #{p}!dl_xr) / 2 - 2 * #{p}!clearance, (#{p}!i_width + #{p}!dl_xl + #{p}!dl_xr) / 2 - #{p}!clearance)")
      da_attr(right, 'leny', "#{p}!thickness")
      da_attr(right, 'lenz', "CHOOSE(#{p}!ov_type, #{p}!i_height - 2 * #{p}!clearance, #{p}!i_height + #{p}!dl_zb + #{p}!dl_zt - 2 * #{p}!clearance, #{p}!i_height + #{p}!dl_zb + #{p}!dl_zt)")

      # Pass-through attrs for handle DC formulas (cm, CENTIMETERS units).
      da_attr(right, 'hdl_hoff', (item_data[:hoff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(right, 'hdl_voff', (item_data[:voff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(right, 'hdl_rot',  item_data[:hrot].to_f.round(3).to_s, units: 'DEGREES')
      da_attr(right, 'clearance', "#{p}!clearance")
      # Rest-state rotation: right leaf opens clockwise (negative rotz)
      da_attr(right, 'rotz', "IF(#{p}!door_open, -(#{p}!oa / 100 * 90), 0)", units: 'DEGREES')

      # --- Handles inside each leaf wrapper ---
      left_hdl  = nil
      right_hdl = nil
      if handle_defn
        left_hdl  = HandleDC.create_double_door_handle_in_leaf(model, left_wrapper_defn,  'DoorLeafL', :left,  handle_defn, abs_z_in: abs_z_in)
        right_hdl = HandleDC.create_double_door_handle_in_leaf(model, right_wrapper_defn, 'DoorLeafR', :right, handle_defn, abs_z_in: abs_z_in)
      end

      # --- Door open-side indication lines for each leaf ---
      add_indication_lines(model, left_wrapper_defn,  'DoorLeafL', 'door-hinge-right',  indication_layer)
      add_indication_lines(model, right_wrapper_defn, 'DoorLeafR', 'door-hinge-left', indication_layer)

      [[left, right], [left_panel, right_panel], [left_hdl, right_hdl]]
    rescue => e
      puts "MLCabinets: DoorLeafDC.create_double_door_leaf error — #{e.message}" if MLCabinets::DEBUG
      [[], [], []]
    end

    # ----------------------------------------------------------------
    # Resolve preset ID (UUID or folder name) to the folder name.
    # Searches panels/ library.
    # ----------------------------------------------------------------
    def self.resolve_preset_name(preset_id)
      return nil unless preset_id
      id = preset_id.to_s

      panels_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels')
      if Dir.exist?(File.join(panels_dir, id))
        return id
      end
      panels_presets = File.join(panels_dir, 'presets.json')
      if File.exist?(panels_presets)
        data  = JSON.parse(File.read(panels_presets, encoding: 'UTF-8'))
        entry = (data['presets'] || []).find { |p| p['id'] == id }
        return entry['name'] if entry
      end

      nil
    rescue => e
      puts "MLCabinets: DoorLeafDC.resolve_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # Returns the full .skp path for a preset name.
    def self.find_skp_path(preset_name)
      candidate = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', preset_name, "#{preset_name}.skp")
      return candidate if File.exist?(candidate)

      nil
    end

    # ================================================================
    # Indication lines helper
    # ================================================================

    # Adds two diagonal dashed-line edges inside wrapper_defn that indicate
    # which side a door opens from. The edges start at the center of the
    # hinge side and run to both corners of the opposite (free) side.
    #
    # A dedicated DoorIndication sub-component is created so that DC lenx/lenz
    # formulas can scale the lines proportionally with the door wrapper.
    # The edges are placed on indication_layer so they can be styled as dashed.
    #
    # Coordinate convention used inside DoorIndication (at 1"×1" unit scale):
    #   X: 0 (left) → 1 (right)
    #   Y: 0 (front face of door leaf)
    #   Z: 0 (bottom) → 1 (top)
    def self.add_indication_lines(model, wrapper_defn, parent_name, door_sub, indication_layer)
      return unless indication_layer

      p = parent_name  # e.g. 'DoorLeaf', 'DoorLeafL', 'DoorLeafR'

      ind_defn = model.definitions.add('DoorIndication')
      ind_defn.description = 'Door Open Indication Lines — ML Cabinets'
      ind_defn.set_attribute(DA, 'name',         'DoorIndication')
      ind_defn.set_attribute(DA, '_name_access', 'NONE')

      # Choose hinge-side midpoint and the two free-side corners at unit scale.
      case door_sub.to_s
      when 'door-hinge-right'
        # Hinge on right edge (x=1); lines go to left corners.
        pt_mid   = Geom::Point3d.new(0, 0, 0.5)
        pt_top   = Geom::Point3d.new(1, 0, 1)
        pt_bot   = Geom::Point3d.new(1, 0, 0)
      when 'door-hinge-top'
        # Hinge on top edge (z=1); lines go to bottom corners.
        pt_mid   = Geom::Point3d.new(0.5, 0, 1)
        pt_top   = Geom::Point3d.new(0, 0, 0)
        pt_bot   = Geom::Point3d.new(1, 0, 0)
      when 'door-hinge-bottom'
        # Hinge on bottom edge (z=0); lines go to top corners.
        pt_mid   = Geom::Point3d.new(0.5, 0, 0)
        pt_top   = Geom::Point3d.new(0, 0, 1)
        pt_bot   = Geom::Point3d.new(1, 0, 1)
      else
        # Default: hinge-left (x=0); lines go to right corners.
        pt_mid   = Geom::Point3d.new(1, 0, 0.5)
        pt_top   = Geom::Point3d.new(0, 0, 1)
        pt_bot   = Geom::Point3d.new(0, 0, 0)
      end

      e1 = ind_defn.entities.add_line(pt_mid, pt_top)
      e2 = ind_defn.entities.add_line(pt_mid, pt_bot)
      e1.layer = indication_layer
      e2.layer = indication_layer

      # Place the sub-component inside the wrapper and drive its dimensions
      # from the parent wrapper's lenx/lenz so it scales with every resize.
      ind_inst = wrapper_defn.entities.add_instance(ind_defn, Geom::Transformation.new([0, 0, 0]))
      ind_inst.name  = 'DoorIndication'
      ind_inst.layer = indication_layer

      # Y: front face of the door leaf.
      da_attr(ind_inst, 'y',    "#{p}!leny")
      # Scale the 1"×1" geometry to the actual door leaf dimensions.
      da_attr(ind_inst, 'lenx', "#{p}!lenx")
      da_attr(ind_inst, 'lenz', "#{p}!lenz")

      ind_inst
    rescue => e
      puts "MLCabinets: DoorLeafDC.add_indication_lines error — #{e.message}" if MLCabinets::DEBUG
      nil
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
    private_class_method :da_attr, :find_skp_path

  end
end
