module MLCabinets
  module ShelfDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Build a Shelf ComponentDefinition and add it to the parent Item.
    # Shelves are equidistant panels inside an Item, controlled by the
    # DC copies feature. All dimensional values are inherited from
    # the Item, which itself inherits from Group → Cabinet.
    # ----------------------------------------------------------------
    def self.create_shelf(model, parent_defn, item_name)
      name = 'Shelf'

      defn = model.definitions.add(name)
      defn.description = 'Cabinet Shelf DC — ML Cabinets'

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
      inst.name = 'Shelf'

      # Spacing: evenly distribute shelves within the item height.
      # With N shelves there are N+1 gaps; each shelf sits at gap*(copy+1).
      da_attr(inst, 'spacing', "IF(shlvs_cnt > 0, (#{p}!i_height - shlvs_cnt * #{p}!Thickness) / (shlvs_cnt + 1), 0)")

      # Position
      da_attr(inst, 'x', "#{p}!shlf_x")
      da_attr(inst, 'y', "CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) + #{p}!clearance")
      da_attr(inst, 'z', "spacing + (copy) * (spacing + #{p}!Thickness)")

      # Size
      # Depth: subtract back panel area + inset door thickness when ov_type=1 (inset)
      da_attr(inst, 'lenx', "#{p}!shlf_width")
      da_attr(inst, 'leny', "#{p}!i_depth - CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) - #{p}!clearance - CHOOSE(#{p}!ov_type, #{p}!thickness, 0, 0)")
      da_attr(inst, 'lenz', "#{p}!Thickness")

      # Copies & visibility
      da_attr(inst, 'shlvs_cnt', "#{p}!shlvs_cnt", units: "NUMBER")
      da_attr(inst, 'copies',    "IF(shlvs_cnt > 0, shlvs_cnt - 1, 0)")
      da_attr(inst, 'hidden',    "IF(shlvs_cnt > 0, False, True)")

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
