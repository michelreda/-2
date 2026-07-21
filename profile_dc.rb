module MLCabinets
  module ProfileDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Build a Profile and add it to the parent Item.
    # Loads the profile SKP from the library, re-orients the 2D face
    # onto the YZ plane, and extrudes along +X.  DC formulas drive
    # lenx = item width (extrusion) while leny / lenz stay fixed at
    # the profile's native cross-section dimensions.
    #
    # Returns the profile ComponentInstance on success, or nil on
    # failure (caller falls back to divider behaviour).
    # ----------------------------------------------------------------
    def self.create_profile(model, parent_defn, item_name, profile_id, g_type: 'vert')
      result = load_and_build(model, profile_id, g_type: g_type)
      return nil unless result

      profile_defn, profile_w_in, profile_h_in = result
      add_to_item(parent_defn, profile_defn, item_name, profile_w_in, profile_h_in, g_type: g_type)
    end

    # ----------------------------------------------------------------
    # Load the profile SKP, re-orient the face onto the YZ plane,
    # and pushpull along +X to create a 3D extrusion.
    # Returns [definition, cross_section_width_in, cross_section_height_in]
    # or nil on failure.
    # ----------------------------------------------------------------
    def self.load_and_build(model, profile_id, g_type: 'vert')
      preset_name = resolve_preset_name(profile_id)
      return nil unless preset_name

      skp_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles',
                           preset_name, "#{preset_name}.skp")
      return nil unless File.exist?(skp_path)

      source_defn = model.definitions.load(skp_path, allow_newer: true)
      return nil unless source_defn

      source_face = source_defn.entities.grep(Sketchup::Face).first
      return nil unless source_face

      # Source face lies on the XY plane (z ≈ 0).
      # Remap:  source X → new Y  (cross-section width  → item depth axis)
      #         source Y → new Z  (cross-section height → item height axis)
      # Pushpull along +X             (extrusion        → item width axis)
      bounds     = source_defn.bounds
      x_off      = bounds.min.x
      y_off      = bounds.min.y
      profile_w  = (bounds.max.y - bounds.min.y).to_f   # inches
      profile_h  = (bounds.max.x - bounds.min.x).to_f   # inches

      defn = model.definitions.add('Profile')
      defn.description = 'Cabinet Profile DC — ML Cabinets'

      if g_type == 'hori'
        # Horizontal group: face lands on XY plane, extrudes along +Z (group height).
        # src X → world Y (depth), src Y → world X (cross-section width)
        remap = Geom::Transformation.new([
          0, 1, 0, 0,
          1, 0, 0, 0,
          0, 0, 1, 0,
          -y_off, -x_off, 0, 1
        ])
        defn.entities.add_instance(source_defn, remap).explode
        face = defn.entities.grep(Sketchup::Face).first
        return nil unless face
        face.reverse! if face.normal.z < 0
      else
        # Vertical group (default): face lands on YZ plane, extrudes along +X (group width).
        # src X → world Y (depth), src Y → world Z (cross-section height)
        remap = Geom::Transformation.new([
          0, 1, 0, 0,
          0, 0, 1, 0,
          1, 0, 0, 0,
          0, -x_off, -y_off, 1
        ])
        defn.entities.add_instance(source_defn, remap).explode
        face = defn.entities.grep(Sketchup::Face).first
        return nil unless face
        face.reverse! if face.normal.x < 0
      end

      # Explode preserves all arc/curve entities so chamfers render smoothly.
      face.pushpull(1.cm)

      defn.set_attribute(DA, 'name',         'Profile')
      defn.set_attribute(DA, '_name_access', 'NONE')
      
      [defn, profile_w, profile_h]
    rescue => e
      puts "MLCabinets: Profile load error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place the extruded profile inside the Item with DC formulas.
    # Profile is positioned flush with the front of the item.
    # ----------------------------------------------------------------
    def self.add_to_item(item_defn, profile_defn, item_name, profile_w_in, profile_h_in, g_type: 'vert')
      p    = item_name
      inst = item_defn.entities.add_instance(profile_defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = 'Profile'

      # Position — flush with item front edge (same for both orientations)
      da_attr(inst, 'x', '0')
      da_attr(inst, 'y', "#{p}!i_depth - #{profile_h_in.round(6)}")
      da_attr(inst, 'z', '0')

      if g_type == 'hori'
        # Extrusion along Z (group height); cross-section fixed in XY.
        # i_width is driven by iw from g_items, which was pre-resolved to
        # profile_w_in (the Y extent of the source face) by group_dc.
        da_attr(inst, 'lenx', "#{p}!i_width")
        da_attr(inst, 'leny', "#{profile_h_in.round(6)}")
        da_attr(inst, 'lenz', "#{p}!i_height")
      else
        # Extrusion along X (group width); cross-section fixed in YZ
        # profile_h → world Y (depth), profile_w → world Z (height)
        da_attr(inst, 'lenx', "#{p}!i_width")
        da_attr(inst, 'leny', "#{profile_h_in.round(6)}")
        da_attr(inst, 'lenz', "#{profile_w_in.round(6)}")
      end

      inst
    end

    # Return the cross-section width (inches) a profile occupies along the
    # horizontal axis when placed in a horizontal group.
    # Reads height_in from dimensions_raw in presets.json — that is the Y
    # extent of the saved face, which maps to World X after axis remapping.
    def self.preset_width_in(profile_id)
      pid = profile_id.to_s
      idx_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles', 'presets.json')
      return nil unless File.exist?(idx_path)
      data  = JSON.parse(File.read(idx_path, encoding: 'UTF-8'))
      entry = (data['presets'] || []).find { |p| p['id'] == pid }
      raw   = entry && entry['dimensions_raw']
      raw ? raw['height_in'].to_f : nil
    rescue
      nil
    end

    # ----------------------------------------------------------------
    # Resolve profile preset UUID → folder name.
    # ----------------------------------------------------------------
    def self.resolve_preset_name(profile_id)
      return nil unless profile_id

      pid = profile_id.to_s
      direct = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles', pid)
      return pid if Dir.exist?(direct)

      idx_path = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'profiles', 'presets.json')
      return nil unless File.exist?(idx_path)

      data  = JSON.parse(File.read(idx_path, encoding: 'UTF-8'))
      entry = (data['presets'] || []).find { |p| p['id'] == pid }
      entry ? entry['name'] : nil
    rescue => e
      puts "MLCabinets: resolve_profile_preset_name error — #{e.message}" if MLCabinets::DEBUG
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
    private_class_method :da_attr, :add_to_item, :resolve_preset_name

  end
end
