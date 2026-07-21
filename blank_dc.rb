module MLCabinets
  module BlankDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Build a Blank ComponentDefinition and add it to the parent Item.
    # Blanks are equidistant panels inside an Item, controlled by the
    # DC copies feature. All dimensional values are inherited from
    # the Item, which itself inherits from Group → Cabinet.
    # ----------------------------------------------------------------
    def self.create_blank(model, parent_defn, item_name)
      name = 'Blank'

      defn = model.definitions.add(name)
      defn.description = 'Cabinet Blank DC — ML Cabinets'

      # Placeholder box — the DC engine resizes via lenx/leny/lenz
      w = 1.cm
      face = defn.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, w, 0),
        Geom::Point3d.new(0, w, 0)
      )
      face.pushpull(-w)

      defn.set_attribute(DA, 'name',         name)
      defn.set_attribute(DA, '_name_access', 'NONE')

      add_to_item(parent_defn, defn, item_name)
    end

    private_class_method def self.add_to_item(item_defn, shelf_defn, item_name)
      p    = item_name
      inst = item_defn.entities.add_instance(shelf_defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = 'Blank'

      # Position
      da_attr(inst, 'x', '0')
      da_attr(inst, 'y', "#{p}!i_depth - #{p}!thickness")
      da_attr(inst, 'z', '0')

      # Size
      da_attr(inst, 'lenx', "#{p}!i_width")
      da_attr(inst, 'leny', "#{p}!thickness")
      da_attr(inst, 'lenz', "#{p}!lenZ") # Use lenZ to allow full item height for blanks

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
    private_class_method :da_attr

  end
end
