module MLCabinets
  module DrawerDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    # ----------------------------------------------------------------
    # Build a DrawerBox ComponentDefinition and add it to the parent
    # Item. The drawer box has four panels: two sides, a back, and a
    # bottom. Side and back thickness = cabinet panel thickness;
    # bottom thickness = cabinet back panel thickness.
    # Top/bottom clearance params control the vertical offset and
    # height of the box within the item envelope.
    # ----------------------------------------------------------------
    def self.create_drawer_box(model, parent_defn, item_name)
      name = 'DrawerBox'

      defn = model.definitions.add(name)
      defn.description = 'Cabinet Drawer Box DC — ML Cabinets'

      defn.set_attribute(DA, 'name',         name)
      defn.set_attribute(DA, '_name_access', 'NONE')

      add_to_item(parent_defn, defn, item_name, model)
    end

    private_class_method def self.add_to_item(item_defn, box_defn, item_name, model)
      p = item_name
      inst = item_defn.entities.add_instance(box_defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = 'DrawerBox'

      # Inherit params from the parent Item
      da_attr(inst, 'thickness',    "#{p}!thickness")
      da_attr(inst, 'bp_thickness', "#{p}!bp_thickness")
      da_attr(inst, 'bp_setback',   "#{p}!bp_setback")
      da_attr(inst, 'bk_type',      "#{p}!bk_type")
      da_attr(inst, 'clearance',    "#{p}!clearance")
      da_attr(inst, 'ov_type',      "#{p}!ov_type")
      da_attr(inst, 'tclr',         "#{p}!tclr")
      da_attr(inst, 'bclr',         "#{p}!bclr")
      da_attr(inst, 'sclr',         "0.6") # Standard side clearance for drawer boxes, based on 0.25in (6.35mm) clearance on each side

      # Box dimensions (derived from item envelope minus clearances)
      da_attr(inst, 'box_width',  "#{p}!i_width")
      da_attr(inst, 'box_depth',  "#{p}!i_depth - CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) - #{p}!clearance - CHOOSE(#{p}!ov_type, #{p}!thickness, 0, 0)")
      da_attr(inst, 'box_height', "#{p}!i_height - #{p}!tclr - #{p}!bclr")

      # Position: sits at the back of the item, raised by bottom clearance
      da_attr(inst, 'x', '0')
      da_attr(inst, 'y', "CHOOSE(#{p}!bk_type, #{p}!bp_setback + #{p}!bp_thickness, #{p}!thickness, 0) + #{p}!clearance")
      da_attr(inst, 'z', "#{p}!bclr")

      # DC reserved — size the placeholder box to match
      da_attr(inst, 'lenx', 'box_width')
      da_attr(inst, 'leny', 'box_depth')
      da_attr(inst, 'lenz', 'box_height')

      # Create the four panels inside the drawer box
      create_side_panel(model, box_defn, inst.name, :left)
      create_side_panel(model, box_defn, inst.name, :right)
      create_back_panel(model, box_defn, inst.name)
      create_bottom_panel(model, box_defn, inst.name)

      inst
    end

    # ----------------------------------------------------------------
    # Side panel (left or right)
    # Thickness = cabinet panel thickness, height = box_height,
    # depth = box_depth - back panel thickness (sides sit in front of back)
    # ----------------------------------------------------------------
    private_class_method def self.create_side_panel(model, parent_defn, box_name, side)
      label = side == :left ? 'DrawerSideL' : 'DrawerSideR'

      defn = model.definitions.add(label)
      defn.description = "Drawer Box #{side == :left ? 'Left' : 'Right'} Side — ML Cabinets"

      w = 1.cm
      face = defn.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, w, 0),
        Geom::Point3d.new(0, w, 0)
      )
      face.pushpull(-w)

      defn.set_attribute(DA, 'name',         label)
      defn.set_attribute(DA, '_name_access', 'NONE')

      p = box_name
      inst = parent_defn.entities.add_instance(defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = label

      # Position
      if side == :left
        da_attr(inst, 'x', "#{p}!sclr") # Left side sits at the thickness offset from the left wall of the item
      else
        da_attr(inst, 'x', "#{p}!box_width - #{p}!thickness - #{p}!sclr") # Right side sits at box_width minus thickness offset from the left wall
      end
      da_attr(inst, 'y', "#{p}!thickness")
      da_attr(inst, 'z', '0')

      # Size
      da_attr(inst, 'lenx', "#{p}!thickness")
      da_attr(inst, 'leny', "#{p}!box_depth - #{p}!thickness")
      da_attr(inst, 'lenz', "#{p}!box_height")

      inst
    end

    # ----------------------------------------------------------------
    # Back panel
    # Thickness = cabinet panel thickness, sits at y=0 (back of box)
    # Width = box_width minus two side thicknesses
    # ----------------------------------------------------------------
    private_class_method def self.create_back_panel(model, parent_defn, box_name)
      label = 'DrawerBack'

      defn = model.definitions.add(label)
      defn.description = 'Drawer Box Back Panel — ML Cabinets'

      w = 1.cm
      face = defn.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, w, 0),
        Geom::Point3d.new(0, w, 0)
      )
      face.pushpull(-w)

      defn.set_attribute(DA, 'name',         label)
      defn.set_attribute(DA, '_name_access', 'NONE')

      p = box_name
      inst = parent_defn.entities.add_instance(defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = label

      # Position: between the two sides, at the back
      da_attr(inst, 'x', "#{p}!sclr") # Back panel sits at the thickness offset from the left wall of the item, same as the left side panel
      da_attr(inst, 'y', '0')
      da_attr(inst, 'z', '0')

      # Size
      da_attr(inst, 'lenx', "#{p}!box_width - 2 * #{p}!sclr") # Back panel width accounts for the thickness of both side panels
      da_attr(inst, 'leny', "#{p}!thickness")
      da_attr(inst, 'lenz', "#{p}!box_height")

      inst
    end

    # ----------------------------------------------------------------
    # Bottom panel
    # Thickness = cabinet back panel thickness (thinner panel)
    # Sits at z=0, between the sides, spanning the full box depth
    # minus the back panel thickness
    # ----------------------------------------------------------------
    private_class_method def self.create_bottom_panel(model, parent_defn, box_name)
      label = 'DrawerBottom'

      defn = model.definitions.add(label)
      defn.description = 'Drawer Box Bottom Panel — ML Cabinets'

      w = 1.cm
      face = defn.entities.add_face(
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(w, 0, 0),
        Geom::Point3d.new(w, w, 0),
        Geom::Point3d.new(0, w, 0)
      )
      face.pushpull(-w)

      defn.set_attribute(DA, 'name',         label)
      defn.set_attribute(DA, '_name_access', 'NONE')

      p = box_name
      inst = parent_defn.entities.add_instance(defn, Geom::Transformation.new([0, 0, 0]))
      inst.name = label

      # Position: between the sides, spanning from back panel to front
      da_attr(inst, 'x', "#{p}!thickness + #{p}!sclr") # Bottom panel starts at the thickness offset from the left wall of the item, plus the clearance for the left side panel
      da_attr(inst, 'y', "#{p}!thickness")
      da_attr(inst, 'z', '0.3937') # 1cm offset of the bottom panel from the front edge of the box

      # Size: bottom uses back panel thickness (thinner)
      da_attr(inst, 'lenx', "#{p}!box_width - 2 * (#{p}!thickness + #{p}!sclr)")
      da_attr(inst, 'leny', "#{p}!box_depth - #{p}!thickness")
      da_attr(inst, 'lenz', "#{p}!bp_thickness")

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
