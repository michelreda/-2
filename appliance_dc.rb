# ML Cabinets - Appliance DC
# Loads an appliance preset from the library and places it inside an Item DC.
# The appliance retains its own native dimensions from the library preset.
# If no preset is found, returns nil gracefully.

require 'sketchup.rb'
require 'json'

module MLCabinets
  module ApplianceDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Load an appliance ComponentDefinition from the library (SKP file).
    # Returns nil if the preset is not found — no fallback for appliances.
    # ----------------------------------------------------------------
    def self.load_definition(model, preset_id)
      return nil unless preset_id && !preset_id.to_s.strip.empty?

      preset_name = resolve_preset_name(preset_id)
      if preset_name
        skp_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', preset_name, "#{preset_name}.skp")
        if File.exist?(skp_path)
          defn = model.definitions.load(skp_path, allow_newer: true)
          puts "MLCabinets: Loaded appliance preset '#{preset_name}'" if MLCabinets::DEBUG
          return defn
        end
      end
      puts "MLCabinets: Appliance preset '#{preset_id}' not found" if MLCabinets::DEBUG
      nil
    rescue => e
      puts "MLCabinets: ApplianceDC.load_definition error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Look up the appliance preset name from presets.json by UUID.
    # Falls back to using the ID directly if it matches a folder name.
    # ----------------------------------------------------------------
    def self.resolve_preset_name(preset_id)
      direct_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', preset_id.to_s)
      return preset_id.to_s if Dir.exist?(direct_path)

      presets_file = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', 'presets.json')
      return nil unless File.exist?(presets_file)

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      entry = (data['presets'] || []).find { |p| p['id'] == preset_id.to_s }
      entry ? entry['name'] : nil
    rescue => e
      puts "MLCabinets: ApplianceDC.resolve_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Load the per-preset JSON metadata for an appliance.
    # Returns the parsed Hash or nil if not found.
    # ----------------------------------------------------------------
    def self.load_metadata(preset_id)
      return nil unless preset_id && !preset_id.to_s.strip.empty?

      preset_name = resolve_preset_name(preset_id)
      return nil unless preset_name

      json_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'appliances', preset_name, "#{preset_name}.json")
      return nil unless File.exist?(json_path)

      JSON.parse(File.read(json_path, encoding: 'UTF-8'))
    rescue => e
      puts "MLCabinets: ApplianceDC.load_metadata error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place an appliance instance inside the given Item definition.
    # When the preset has fixed_size: true the lenx/y/z DC attributes
    # are locked to the stored inch dimensions from the JSON file.
    # When the preset has free_standing: true the z is set to
    # -(iz_in + tk_h_in) so the appliance bottom lands at the cabinet
    # interior floor regardless of which item it belongs to.
    # ----------------------------------------------------------------
    def self.create_appliance(model, parent_defn, item_name, appliance_defn, appliance_id: nil, abs_z_in: 0.0)
      return nil unless appliance_defn

      meta          = appliance_id ? load_metadata(appliance_id) : nil
      fixed_size    = meta && meta['fixed_size']    == true
      free_standing = meta && meta['free_standing'] == true
      dims          = fixed_size ? meta['dimensions'] : nil

      add_to_item(parent_defn, appliance_defn, item_name,
        fixed_size: fixed_size, dims: dims,
        free_standing: free_standing, abs_z_in: abs_z_in.to_f)
    end

    private_class_method def self.add_to_item(item_defn, appl_defn, item_name, fixed_size: false, dims: nil, free_standing: false, abs_z_in: 0.0)
      p    = item_name
      inst = item_defn.entities.add_instance(appl_defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = 'Appliance'

      # y: flush with the front face of the item (item depth)
      # z: bottom of the item, or cabinet interior floor when free_standing
      #    (negating the item's z-offset + toekick walks back to floor level)
      da_attr(inst, 'x', "#{p}!i_width / 2")
      da_attr(inst, 'y', "#{p}!i_depth")
      z_val = free_standing ? (-abs_z_in).round(6).to_s : '0'
      da_attr(inst, 'z', z_val)

      if fixed_size && dims
        # Fixed-size: centre the appliance in the opening and lock to
        # catalogue dimensions so the DC engine does not stretch it.
        da_attr(inst, 'lenx', dims['width'].to_f.round(6).to_s,  units: 'INCHES')
        da_attr(inst, 'leny', dims['depth'].to_f.round(6).to_s,  units: 'INCHES')
        da_attr(inst, 'lenz', dims['height'].to_f.round(6).to_s, units: 'INCHES')
      else
        # Non-fixed: stretch the appliance to fill the entire item opening.
        da_attr(inst, 'lenx', "#{p}!lenx + 2 * #{p}!Thickness")
        da_attr(inst, 'leny', "#{p}!leny")
        da_attr(inst, 'lenz', "#{p}!lenz + 2 * #{p}!Thickness")
      end

      inst
    end

    # ================================================================
    # Private helpers
    # ================================================================

    def self.da_attr(defn, key, value, label: ' ', units: 'STRING', access: 'NONE')
      defn.set_attribute(DA, key,                 value)
      defn.set_attribute(DA, "_#{key}_formula",   value)
      defn.set_attribute(DA, "_#{key}_formlabel", label)
      defn.set_attribute(DA, "_#{key}_units",     units)
      defn.set_attribute(DA, "_#{key}_access",    access)
    end
    private_class_method :da_attr

  end
end
