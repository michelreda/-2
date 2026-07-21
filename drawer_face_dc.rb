# ML Cabinets - Drawer Face DC
# Loads a drawer face preset from the library and places it as a child
# of the DrawerBox. The face is sized to match the item envelope (the
# full opening, not the box) and sits at the front of the item.
# If no preset is found, returns nil so the caller can skip the face.

require 'sketchup.rb'
require 'json'

module MLCabinets
  module DrawerFaceDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Load drawer face definition from library SKP.
    # Looks in libraries/panels/ first (new unified library), then falls
    # back to libraries/drawer_faces/ for presets saved before the unification.
    # Returns the ComponentDefinition or nil on failure.
    # ----------------------------------------------------------------
    def self.load_definition(model, preset_id)
      return nil unless preset_id

      preset_name = resolve_preset_name(preset_id)
      return nil unless preset_name

      skp_path = find_skp_path(preset_name)
      unless skp_path
        puts "MLCabinets: DrawerFaceDC — SKP not found for preset '#{preset_name}'" if MLCabinets::DEBUG
        return nil
      end

      defn = model.definitions.load(skp_path, allow_newer: true)
      puts "MLCabinets: Loaded drawer face preset '#{preset_name}'" if MLCabinets::DEBUG
      defn
    rescue => e
      puts "MLCabinets: DrawerFaceDC.load_definition error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a drawer face inside the item (NOT the box).
    #
    # A unique wrapper ComponentDefinition is created per drawer item so
    # that the handle can be a child of DrawerFace without mutating the
    # shared loaded panel preset definition.
    #
    # Hierarchy created inside parent_defn:
    #   DrawerFace (wrapper inst — unique per item)
    #     ├── DrawerFacePanel (loaded preset, sized to match wrapper)
    #     └── DrawerHandle    (optional, via handle_defn)
    #
    # Returns [face_inst, panel_inst, handle_inst]
    # Materials must be applied to panel_inst and handle_inst directly,
    # NOT to face_inst — applying to the wrapper makes_unique all children
    # at once, causing the handle_inst reference to become stale.
    # ----------------------------------------------------------------
    def self.create_drawer_face(model, parent_defn, item_name, face_defn,
                                handle_defn: nil, item_data: {}, indication_layer: nil)
      return [nil, nil, nil] unless face_defn

      p = item_name

      # --- Unique wrapper definition for this drawer item ---
      wrapper_defn = model.definitions.add('DrawerFace')
      wrapper_defn.description = 'Drawer Face DC — ML Cabinets'
      wrapper_defn.set_attribute(DA, 'name',         'DrawerFace')
      wrapper_defn.set_attribute(DA, '_name_access', 'NONE')
      # Metadata on definition so DC resolves custom attr units correctly.
      # (DC reads _units from the definition, not the instance, for custom attrs.)
      wrapper_defn.set_attribute(DA, '_hdl_hoff_units', 'CENTIMETERS')
      wrapper_defn.set_attribute(DA, '_hdl_voff_units', 'CENTIMETERS')
      wrapper_defn.set_attribute(DA, '_hdl_rot_units',  'DEGREES')

      # Panel preset instance inside the wrapper, tracks wrapper size
      panel_inst = wrapper_defn.entities.add_instance(face_defn, Geom::Transformation.new([0, 0, 0]))
      panel_inst.name = 'DrawerFacePanel'
      da_attr(panel_inst, 'lenx', 'DrawerFace!lenx')
      da_attr(panel_inst, 'leny', 'DrawerFace!leny')
      da_attr(panel_inst, 'lenz', 'DrawerFace!lenz')

      # --- Wrapper instance placed in parent (Item) ---
      inst = parent_defn.entities.add_instance(wrapper_defn, Geom::Transformation.new([0, 0, 10]))
      inst.name = 'DrawerFace'

      # Position: CHOOSE(ov_type, inset, partial, full)
      da_attr(inst, 'x', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!df_xl + #{p}!clearance, -#{p}!df_xl)")
      da_attr(inst, 'y', "CHOOSE(#{p}!ov_type, #{p}!i_depth - #{p}!thickness, #{p}!i_depth, #{p}!i_depth)")
      da_attr(inst, 'z', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!df_zb + #{p}!clearance, -#{p}!df_zb)")

      # Size: CHOOSE(ov_type, inset, partial, full)
      da_attr(inst, 'lenx', "CHOOSE(#{p}!ov_type, #{p}!i_width - 2 * #{p}!clearance, #{p}!i_width + #{p}!df_xl + #{p}!df_xr - 2 * #{p}!clearance, #{p}!i_width + #{p}!df_xl + #{p}!df_xr)")
      da_attr(inst, 'leny', "#{p}!thickness")
      da_attr(inst, 'lenz', "CHOOSE(#{p}!ov_type, #{p}!i_height - 2 * #{p}!clearance, #{p}!i_height + #{p}!df_zb + #{p}!df_zt - 2 * #{p}!clearance, #{p}!i_height + #{p}!df_zb + #{p}!df_zt)")

      # Pass-through attrs consumed by the handle DC formulas.
      # Store in cm with CENTIMETERS units so SketchUp DC converts to inches
      # correctly in formula evaluation (avoids model-unit ambiguity).
      da_attr(inst, 'hdl_hoff', (item_data[:hoff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(inst, 'hdl_voff', (item_data[:voff].to_f * 2.54).round(6).to_s, units: 'CENTIMETERS')
      da_attr(inst, 'hdl_rot',  item_data[:hrot].to_f.round(3).to_s, units: 'DEGREES')

      # --- Handle inside the face wrapper ---
      handle_inst = if handle_defn
        HandleDC.create_drawer_handle_in_face(model, wrapper_defn, inst.name, handle_defn)
      end

      # --- Drawer open-side indication line ---
      add_indication_lines(model, wrapper_defn, 'DrawerFace', indication_layer)

      [inst, panel_inst, handle_inst]
    rescue => e
      puts "MLCabinets: DrawerFaceDC.create_drawer_face error — #{e.message}" if MLCabinets::DEBUG
      [nil, nil, nil]
    end

    # ----------------------------------------------------------------
    # Resolve preset ID (UUID or folder name) to the folder name.
    # Searches panels/ first, then drawer_faces/ for legacy presets.
    # ----------------------------------------------------------------
    def self.resolve_preset_name(preset_id)
      return nil unless preset_id
      id = preset_id.to_s

      # Check unified panels/ library
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

      # Legacy fallback: drawer_faces/
      legacy_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'drawer_faces')
      return id if Dir.exist?(File.join(legacy_dir, id))

      legacy_presets = File.join(legacy_dir, 'presets.json')
      if File.exist?(legacy_presets)
        data  = JSON.parse(File.read(legacy_presets, encoding: 'UTF-8'))
        entry = (data['presets'] || []).find { |p| p['id'] == id }
        return entry['name'] if entry
      end

      nil
    rescue => e
      puts "MLCabinets: DrawerFaceDC.resolve_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # Returns the full .skp path for a preset name, checking panels/ then drawer_faces/.
    def self.find_skp_path(preset_name)
      candidate = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels',       preset_name, "#{preset_name}.skp")
      return candidate if File.exist?(candidate)

      candidate = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'drawer_faces', preset_name, "#{preset_name}.skp")
      return candidate if File.exist?(candidate)

      nil
    end

    # ================================================================
    # Indication lines helper
    # ================================================================

    # Adds a single diagonal edge inside wrapper_defn running from the
    # top-left corner (0, 0, lenz) to the bottom-right corner (lenx, 0, 0).
    # The edge is placed on indication_layer so it can be styled as dashed.
    #
    # A DrawerIndication sub-component is created at 1"×1" unit scale;
    # its instance gets lenx/lenz formulas driven by the parent wrapper
    # so the line scales proportionally with every cabinet resize.
    def self.add_indication_lines(model, wrapper_defn, parent_name, indication_layer)
      return unless indication_layer

      p = parent_name  # e.g. 'DrawerFace'

      ind_defn = model.definitions.add('DrawerIndication')
      ind_defn.description = 'Drawer Open Indication Line — ML Cabinets'
      ind_defn.set_attribute(DA, 'name',         'DrawerIndication')
      ind_defn.set_attribute(DA, '_name_access', 'NONE')

      # Single diagonal from top-left to bottom-right at unit scale.
      pt_top_left     = Geom::Point3d.new(0, 0, 1)
      pt_bottom_right = Geom::Point3d.new(1, 0, 0)
      edge = ind_defn.entities.add_line(pt_top_left, pt_bottom_right)
      edge.layer = indication_layer

      ind_inst = wrapper_defn.entities.add_instance(ind_defn, Geom::Transformation.new([0, 0, 0]))
      ind_inst.name  = 'DrawerIndication'
      ind_inst.layer = indication_layer

      # Y: front face of the drawer face panel.
      da_attr(ind_inst, 'y',    "#{p}!leny")
      # Scale the 1"×1" geometry to the actual drawer face dimensions.
      da_attr(ind_inst, 'lenx', "#{p}!lenx")
      da_attr(ind_inst, 'lenz', "#{p}!lenz")

      ind_inst
    rescue => e
      puts "MLCabinets: DrawerFaceDC.add_indication_lines error — #{e.message}" if MLCabinets::DEBUG
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
    private_class_method :da_attr, :find_skp_path, :add_indication_lines

  end
end
