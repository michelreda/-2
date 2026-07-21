# ML Cabinets - Handle DC
# Loads a handle preset from the library and places it as a child of
# a door or drawer Item DC.
#
# Library stores handles with the long axis along Z (vertical).
#   Door    → keep vertical; positioned from the top-left corner of the door.
#             hdl_hoff = distance from door's left edge to handle's left edge.
#             hdl_voff = distance from door's top edge down to handle's top edge.
#   Drawer  → rotate 90° around Y so the bar runs left-right; centered + offsets.

require 'sketchup.rb'
require 'json'

module MLCabinets
  module HandleDC

    DA = 'dynamic_attributes'.freeze unless defined?(DA)
    # Doors whose bottom edge is at or above this height (in inches from scene floor)
    # get their handle placed at the bottom — covers wall cabinet and upper tall cabinet doors.
    HANDLE_BOTTOM_THRESHOLD_IN = (90.0 / 2.54).freeze unless defined?(HANDLE_BOTTOM_THRESHOLD_IN)

    # ----------------------------------------------------------------
    # Load handle definition from the library SKP.
    # Returns the ComponentDefinition or nil on failure.
    # ----------------------------------------------------------------
    def self.load_definition(model, preset_id)
      return nil unless preset_id && !preset_id.to_s.strip.empty?

      preset_name = resolve_preset_name(preset_id)
      return nil unless preset_name

      skp_path = find_skp_path(preset_name)
      unless skp_path
        puts "MLCabinets: HandleDC — SKP not found for preset '#{preset_name}'" if MLCabinets::DEBUG
        return nil
      end

      defn = model.definitions.load(skp_path, allow_newer: true)
      puts "MLCabinets: Loaded handle preset '#{preset_name}'" if MLCabinets::DEBUG
      defn
    rescue => e
      puts "MLCabinets: HandleDC.load_definition error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a handle instance inside the item.
    # parent_defn = the Item ComponentDefinition
    # item_name   = the Item instance name (for DC formula references)
    # handle_defn = already-loaded ComponentDefinition from load_definition
    # item_type   = 'door' (vertical bar) or 'drwr' (horizontal bar)
    # ----------------------------------------------------------------
    def self.create_handle(model, parent_defn, item_name, handle_defn, item_type: 'door', door_sub: nil, abs_z_in: 0.0)
      return nil unless handle_defn

      p = item_name

      inst = parent_defn.entities.add_instance(handle_defn, Geom::Transformation.new([5, 0, 5]))
      inst.name = item_type == 'drwr' ? 'DrawerHandle' : 'DoorHandle'

      # Y: on the front face of the door / drawer front panel
      # Matches the face position used by DrawerFaceDC / DoorLeafDC
      da_attr(inst, 'y', "CHOOSE(#{p}!ov_type, #{p}!i_depth, #{p}!i_depth + #{p}!thickness, #{p}!i_depth + #{p}!thickness)")

      if item_type == 'door'
        case door_sub.to_s
        when 'door-hinge-top', 'door-hinge-bottom'
          # Hinge-side handle: position at the inner edge of the door leaf, offset by hdl_hoff and hdl_voff from the hinge corner.
          da_attr(inst, 'x', "#{p}!i_width / 2 + #{p}!hdl_hoff")
          da_attr(inst, 'z', case door_sub.to_s
                            when 'door-hinge-top'
                              "lenx / 2 + #{p}!hdl_voff - CHOOSE(#{p}!ov_type, -#{p}!clearance, #{p}!dl_zb - #{p}!clearance, #{p}!dl_zb)"
                            else
                              "#{p}!i_height - lenx / 2 - #{p}!hdl_voff + CHOOSE(#{p}!ov_type, -#{p}!clearance, #{p}!dl_zt - #{p}!clearance, #{p}!dl_zt)"
                            end)
          da_attr(inst, 'roty', "90 + #{p}!hdl_rot", units: 'DEGREES')
        when 'door-hinge-right'
          # Hinge on left: handle near the right edge of the door leaf.
          # x = i_width - hdl_hoff from the door's right edge (accounting for overlay extension).
          da_attr(inst, 'x', "#{p}!i_width - #{p}!hdl_hoff - lenx / 2 + CHOOSE(#{p}!ov_type, -#{p}!clearance, #{p}!dl_xr - #{p}!clearance, #{p}!dl_xr)")
          if abs_z_in.to_f >= HANDLE_BOTTOM_THRESHOLD_IN
            da_attr(inst, 'z', "#{p}!hdl_voff + lenz / 2 + CHOOSE(#{p}!ov_type, #{p}!clearance, #{p}!clearance - #{p}!dl_zb, -#{p}!dl_zb)")
          else
            da_attr(inst, 'z', "#{p}!i_height - #{p}!hdl_voff - lenz / 2 + CHOOSE(#{p}!ov_type, -#{p}!clearance, (#{p}!dl_zt - #{p}!clearance), #{p}!dl_zt)")
          end
          da_attr(inst, 'roty', "#{p}!hdl_rot", units: 'DEGREES')
        else
          # default door (hinge-left): handle near the left edge of the door leaf.
          # x = hdl_hoff from the door's left edge (accounting for overlay extension).
          da_attr(inst, 'x', "#{p}!hdl_hoff + lenx / 2 + CHOOSE(#{p}!ov_type, #{p}!clearance, #{p}!clearance - #{p}!dl_xl, -#{p}!dl_xl)")
          if abs_z_in.to_f >= HANDLE_BOTTOM_THRESHOLD_IN
            da_attr(inst, 'z', "#{p}!hdl_voff + lenz / 2 + CHOOSE(#{p}!ov_type, #{p}!clearance, #{p}!clearance - #{p}!dl_zb, -#{p}!dl_zb)")
          else
            da_attr(inst, 'z', "#{p}!i_height - #{p}!hdl_voff - lenz / 2 + CHOOSE(#{p}!ov_type, -#{p}!clearance, (#{p}!dl_zt - #{p}!clearance), #{p}!dl_zt)")
          end
          da_attr(inst, 'roty', "#{p}!hdl_rot", units: 'DEGREES')
        end
      else
        # Drawer handle: centered on the drawer face + user offsets from center.
        da_attr(inst, 'x', "#{p}!i_width / 2 + #{p}!hdl_hoff")
        da_attr(inst, 'z', "#{p}!i_height / 2 + #{p}!hdl_voff")
        da_attr(inst, 'roty', "90 + #{p}!hdl_rot", units: 'DEGREES')
      end

      inst
    rescue => e
      puts "MLCabinets: HandleDC.create_handle error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place two handles for a double-door item — one on each leaf at
    # the inner (opening) edge.
    #
    # The SEAM between the two leaves is NOT always at i_width / 2.
    # When overlay extensions are asymmetric (dl_xl ≠ dl_xr) — which
    # happens at the edges of a horizontal group — the seam shifts by
    # (dl_xr − dl_xl) / 2.  For inset overlay there are no extensions
    # so the seam stays centred.
    # ----------------------------------------------------------------
    def self.create_double_door_handles(model, parent_defn, item_name, handle_defn, abs_z_in: 0.0)
      return nil unless handle_defn

      p = item_name

      # Y: same front-face formula as single door
      y_formula = "CHOOSE(#{p}!ov_type, #{p}!i_depth, #{p}!i_depth + #{p}!thickness, #{p}!i_depth + #{p}!thickness)"
      # Z: from bottom for elevated doors, from top for base cabinet doors
      z_formula = if abs_z_in.to_f >= HANDLE_BOTTOM_THRESHOLD_IN
        "#{p}!hdl_voff + lenz / 2 + CHOOSE(#{p}!ov_type, #{p}!clearance, #{p}!clearance - #{p}!dl_zb, -#{p}!dl_zb)"
      else
        "#{p}!i_height - #{p}!hdl_voff - lenz / 2 + CHOOSE(#{p}!ov_type, -#{p}!clearance, (#{p}!dl_zt - #{p}!clearance), #{p}!dl_zt)"
      end

      # Seam correction: for partial/full overlay the door leaf pair is
      # centred on (i_width + dl_xr - dl_xl) / 2, not i_width / 2.
      # The delta from i_width/2 is (dl_xr - dl_xl) / 2.
      # For inset overlay the leaves stay inside the item → no correction.
      seam = "#{p}!i_width / 2 + CHOOSE(#{p}!ov_type, 0, (#{p}!dl_xr - #{p}!dl_xl) / 2, (#{p}!dl_xr - #{p}!dl_xl) / 2)"

      # --- Left leaf handle (at the right/inner edge of the left leaf) ---
      left = parent_defn.entities.add_instance(handle_defn, Geom::Transformation.new([5, 0, 5]))
      left.name = 'DoorHandleL'
      da_attr(left, 'x', "#{seam} + #{p}!hdl_hoff + lenx / 2 + #{p}!clearance")
      da_attr(left, 'y', y_formula)
      da_attr(left, 'z', z_formula)
      da_attr(left, 'roty', "#{p}!hdl_rot", units: 'DEGREES')

      # --- Right leaf handle (at the left/inner edge of the right leaf) ---
      right = parent_defn.entities.add_instance(handle_defn, Geom::Transformation.new([5, 0, 5]))
      right.name = 'DoorHandleR'
      da_attr(right, 'x', "#{seam} - #{p}!hdl_hoff - lenx / 2 - #{p}!clearance")
      da_attr(right, 'y', y_formula)
      da_attr(right, 'z', z_formula)
      da_attr(right, 'roty', "#{p}!hdl_rot", units: 'DEGREES')

      [left, right]
    rescue => e
      puts "MLCabinets: HandleDC.create_double_door_handles error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a drawer handle INSIDE a DrawerFace wrapper definition.
    # All coordinates are in the face's local coordinate space.
    # The face must already have hdl_hoff, hdl_voff, lenx, leny, lenz
    # set as DC attributes on its instance (placed by DrawerFaceDC).
    #
    # The bar is always centred on the face with user offsets from centre:
    #   x = DrawerFace!lenx / 2 + DrawerFace!hdl_hoff
    #   z = DrawerFace!lenz / 2 + DrawerFace!hdl_voff
    #   y = DrawerFace!leny  (front face)
    #   roty = 90° (bar runs left-right)
    # ----------------------------------------------------------------
    def self.create_drawer_handle_in_face(model, face_defn, face_name, handle_defn)
      return nil unless handle_defn

      p = face_name

      inst = face_defn.entities.add_instance(handle_defn, Geom::Transformation.new([5, 0, 5]))
      inst.name = 'DrawerHandle'

      da_attr(inst, 'x',    "#{p}!lenx / 2 + #{p}!hdl_hoff")
      da_attr(inst, 'y',    "#{p}!leny")
      da_attr(inst, 'z',    "#{p}!lenz / 2 + #{p}!hdl_voff")
      da_attr(inst, 'roty', "90 + #{p}!hdl_rot", units: 'DEGREES')

      inst
    rescue => e
      puts "MLCabinets: HandleDC.create_drawer_handle_in_face error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a handle INSIDE a DoorLeaf wrapper definition.
    # All coordinates are in the leaf's local coordinate space.
    # The leaf must already have hdl_hoff, hdl_voff, lenx, leny, lenz
    # set as DC attributes on its instance (placed by DoorLeafDC).
    #
    # Formulae per sub-type:
    #   default (hinge-left) : x = leaf!hdl_hoff + lenx/2
    #   hinge-right          : x = leaf!lenx - leaf!hdl_hoff - lenx/2
    #   hinge-top            : x = leaf!lenx/2 + leaf!hdl_hoff  (rotated 90°)
    #   hinge-bottom         : x = leaf!lenx/2 + leaf!hdl_hoff  (rotated 90°)
    #   z (low door)         : leaf!hdl_voff + lenz/2
    #   z (elevated door)    : leaf!lenz - leaf!hdl_voff - lenz/2
    # ----------------------------------------------------------------
    def self.create_door_handle_in_leaf(model, leaf_defn, leaf_name, handle_defn, door_sub: nil, abs_z_in: 0.0)
      return nil unless handle_defn

      p = leaf_name

      inst = leaf_defn.entities.add_instance(handle_defn, Geom::Transformation.new([5, 0, 5]))
      inst.name = 'DoorHandle'

      # Y: front face of the leaf (leaf thickness)
      da_attr(inst, 'y', "#{p}!leny")

      case door_sub.to_s
      when 'door-hinge-top'
        # Horizontal door hinged at top — handle near the bottom edge
        da_attr(inst, 'x', "#{p}!lenx / 2 + #{p}!hdl_hoff")
        da_attr(inst, 'z', "lenx / 2 + #{p}!hdl_voff")
        da_attr(inst, 'roty', "90 + #{p}!hdl_rot", units: 'DEGREES')
      when 'door-hinge-bottom'
        # Horizontal door hinged at bottom — handle near the top edge
        da_attr(inst, 'x', "#{p}!lenx / 2 + #{p}!hdl_hoff")
        da_attr(inst, 'z', "#{p}!lenz - lenx / 2 - #{p}!hdl_voff")
        da_attr(inst, 'roty', "90 + #{p}!hdl_rot", units: 'DEGREES')
      when 'door-hinge-right'
        # Hinge on right edge — handle near the left edge
        da_attr(inst, 'x', "#{p}!lenx - #{p}!hdl_hoff - lenx / 2")
        if abs_z_in.to_f >= HANDLE_BOTTOM_THRESHOLD_IN
          da_attr(inst, 'z', "#{p}!hdl_voff + lenz / 2")
        else
          da_attr(inst, 'z', "#{p}!lenz - #{p}!hdl_voff - lenz / 2")
        end
        da_attr(inst, 'roty', "#{p}!hdl_rot", units: 'DEGREES')
      else
        # Default (hinge-left / single door) — handle near the left edge
        da_attr(inst, 'x', "#{p}!hdl_hoff + lenx / 2")
        if abs_z_in.to_f >= HANDLE_BOTTOM_THRESHOLD_IN
          da_attr(inst, 'z', "#{p}!hdl_voff + lenz / 2")
        else
          da_attr(inst, 'z', "#{p}!lenz - #{p}!hdl_voff - lenz / 2")
        end
        da_attr(inst, 'roty', "#{p}!hdl_rot", units: 'DEGREES')
      end

      inst
    rescue => e
      puts "MLCabinets: HandleDC.create_door_handle_in_leaf error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Place a handle inside one leaf of a double-door pair.
    # leaf_side: :left  → handle at inner (right) edge of the left leaf
    #            :right → handle at inner (left) edge of the right leaf
    #
    # The inner edge for the left leaf is at x = leaf_lenx in leaf-local
    # space; the handle is placed one clearance + hdl_hoff past it.
    # The inner edge for the right leaf is at x = 0; the handle is
    # placed one clearance + hdl_hoff to the left of it (negative x).
    # ----------------------------------------------------------------
    def self.create_double_door_handle_in_leaf(model, leaf_defn, leaf_name, leaf_side, handle_defn, abs_z_in: 0.0)
      return nil unless handle_defn

      p = leaf_name

      inst = leaf_defn.entities.add_instance(handle_defn, Geom::Transformation.new([5, 0, 5]))
      inst.name = leaf_side == :left ? 'DoorHandleL' : 'DoorHandleR'

      # Y: front face of the leaf
      da_attr(inst, 'y', "#{p}!leny")

      # X: inner-edge side, one gap (clearance) past the leaf boundary
      if leaf_side == :left
        da_attr(inst, 'x', "#{p}!lenx - #{p}!hdl_hoff - lenx / 2")
        da_attr(inst, 'roty', "180 + #{p}!hdl_rot", units: 'DEGREES')
      else
        da_attr(inst, 'x', "#{p}!hdl_hoff + lenx / 2")
        da_attr(inst, 'roty', "#{p}!hdl_rot", units: 'DEGREES')
      end

      # Z: from bottom for elevated doors, from top for base-cabinet doors
      if abs_z_in.to_f >= HANDLE_BOTTOM_THRESHOLD_IN
        da_attr(inst, 'z', "#{p}!hdl_voff + lenz / 2")
      else
        da_attr(inst, 'z', "#{p}!lenz - #{p}!hdl_voff - lenz / 2")
      end

      inst
    rescue => e
      puts "MLCabinets: HandleDC.create_double_door_handle_in_leaf error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # ----------------------------------------------------------------
    # Resolve preset ID (UUID or folder name) to the folder name.
    # ----------------------------------------------------------------
    def self.resolve_preset_name(preset_id)
      return nil unless preset_id
      id = preset_id.to_s.strip

      handles_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'handles')

      # Direct folder name match
      return id if Dir.exist?(File.join(handles_dir, id))

      # UUID lookup in presets.json
      presets_file = File.join(handles_dir, 'presets.json')
      if File.exist?(presets_file)
        data  = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
        entry = (data['presets'] || []).find { |pr| pr['id'] == id }
        return entry['name'] if entry
      end

      nil
    rescue => e
      puts "MLCabinets: HandleDC.resolve_preset_name error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

    # Returns the full .skp path for a given preset folder name.
    def self.find_skp_path(preset_name)
      candidate = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'handles', preset_name, "#{preset_name}.skp")
      return candidate if File.exist?(candidate)
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
