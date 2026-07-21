# ML Cabinets - Panel Face DC
# Loads a decorative or end panel preset from the shared panels library and
# places it as a child of the Item. The face is sized to the item envelope
# and sits flush at the front face, with per-edge overlay extensions
# (pl_zt, pl_zb, pl_xl, pl_xr) identical to the door leaf pattern.
#
# Unlike DoorLeafDC there is no handle and no open/close rotation —
# this is a fixed, static cladding panel.
#
# Shares libraries/panels/ with DoorLeafDC.
# Applicable sub-types: "End Panel", "Decorative Panel".

require 'sketchup.rb'
require 'json'

module MLCabinets
  module PanelDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Load panel face definition from library SKP.
    # Looks in libraries/panels/ (shared panel library).
    # Returns the ComponentDefinition or nil on failure.
    # ----------------------------------------------------------------
    def self.load_definition(model, preset_id)
      return nil unless preset_id

      preset_name = resolve_preset_name(preset_id)
      return nil unless preset_name

      skp_path = find_skp_path(preset_name)
      unless skp_path
        puts "MLCabinets: PanelDC — SKP not found for preset '#{preset_name}'" if MLCabinets::DEBUG
        return nil
      end

      defn = model.definitions.load(skp_path, allow_newer: true)
      puts "MLCabinets: Loaded panel face preset '#{preset_name}'" if MLCabinets::DEBUG
      defn
    rescue => e
      puts "MLCabinets: PanelDC.load_definition error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a static panel face inside the item.
    #
    # A unique wrapper ComponentDefinition is created per panel item so
    # that the loaded preset definition is not mutated.
    #
    # Hierarchy created inside parent_defn:
    #   PanelFace (wrapper inst — unique per item)
    #     └── PanelFacePanel (loaded preset, sized to match wrapper)
    #
    # Returns [face_inst, panel_inst]
    # Materials must be applied to panel_inst directly, NOT to face_inst.
    # ----------------------------------------------------------------
    def self.create_panel_face(model, parent_defn, item_name, face_defn, item_data: {})
      return [nil, nil] unless face_defn

      p = item_name

      # --- Unique wrapper definition for this panel item ---
      wrapper_defn = model.definitions.add('PanelFace')
      wrapper_defn.description = 'Panel Face DC — ML Cabinets'
      wrapper_defn.set_attribute(DA, 'name',         'PanelFace')
      wrapper_defn.set_attribute(DA, '_name_access', 'NONE')

      # Panel preset instance inside the wrapper, tracks wrapper size
      panel_inst = wrapper_defn.entities.add_instance(face_defn, Geom::Transformation.new([0, 0, 0]))
      panel_inst.name = 'PanelFacePanel'
      da_attr(panel_inst, 'lenx', 'PanelFace!lenx')
      da_attr(panel_inst, 'leny', 'PanelFace!leny')
      da_attr(panel_inst, 'lenz', 'PanelFace!lenz')

      # --- Wrapper instance placed in parent (Item) ---
      inst = parent_defn.entities.add_instance(wrapper_defn, Geom::Transformation.new([0, 0, 10]))
      inst.name = 'PanelFace'

      # Position: CHOOSE(ov_type, inset, partial, full)
      da_attr(inst, 'x', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!pl_xl + #{p}!clearance, -#{p}!pl_xl)")
      da_attr(inst, 'y', "CHOOSE(#{p}!ov_type, #{p}!i_depth - #{p}!thickness, #{p}!i_depth, #{p}!i_depth)")
      da_attr(inst, 'z', "CHOOSE(#{p}!ov_type, #{p}!clearance, -#{p}!pl_zb + #{p}!clearance, -#{p}!pl_zb)")

      # Size: CHOOSE(ov_type, inset, partial, full)
      da_attr(inst, 'lenx', "CHOOSE(#{p}!ov_type, #{p}!i_width - 2 * #{p}!clearance, #{p}!i_width + #{p}!pl_xl + #{p}!pl_xr - 2 * #{p}!clearance, #{p}!i_width + #{p}!pl_xl + #{p}!pl_xr)")
      da_attr(inst, 'leny', "#{p}!thickness")
      da_attr(inst, 'lenz', "CHOOSE(#{p}!ov_type, #{p}!i_height - 2 * #{p}!clearance, #{p}!i_height + #{p}!pl_zb + #{p}!pl_zt - 2 * #{p}!clearance, #{p}!i_height + #{p}!pl_zb + #{p}!pl_zt)")

      [inst, panel_inst]
    rescue => e
      puts "MLCabinets: PanelDC.create_panel_face error — #{e.message}" if MLCabinets::DEBUG
      [nil, nil]
    end

    # ================================================================
    # Private helpers
    # ================================================================

    def self.resolve_preset_name(preset_id)
      panels_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels')
      # Folder name check first (handles name-based IDs directly)
      return preset_id.to_s if Dir.exist?(File.join(panels_dir, preset_id.to_s))

      # Fall back to UUID lookup in presets.json
      presets_file = File.join(panels_dir, 'presets.json')
      return nil unless File.exist?(presets_file)

      data  = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      entry = (data['presets'] || []).find { |p| p['id'] == preset_id.to_s }
      entry ? entry['name'] : nil
    rescue => e
      puts "MLCabinets: PanelDC.resolve_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    def self.find_skp_path(preset_name)
      path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'panels', preset_name, "#{preset_name}.skp")
      File.exist?(path) ? path : nil
    end

    def self.da_attr(defn, key, value, label: ' ', units: 'STRING', access: 'NONE')
      defn.set_attribute(DA, key,                 value)
      defn.set_attribute(DA, "_#{key}_formula",   value)
      defn.set_attribute(DA, "_#{key}_formlabel", label)
      defn.set_attribute(DA, "_#{key}_units",     units)
      defn.set_attribute(DA, "_#{key}_access",    access)
    end
    private_class_method :da_attr, :find_skp_path

  end
end
