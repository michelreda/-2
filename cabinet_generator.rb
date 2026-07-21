module SKBCam
  # Builds a parametric kitchen cabinet as a SketchUp group of components.
  # Each resulting panel carries a "cutlist" attribute dictionary compatible
  # with OpenCutList's schema (length/width/thickness/material/labels/grain)
  # so the model can be opened directly in OpenCutList as a fallback, and so
  # our own BomEngine can read the same source of truth.
  module CabinetGenerator
    MM = 1.mm # SketchUp works in inches internally; helper for millimeter input

    # opts: {
    #   width_mm:, height_mm:, depth_mm:,
    #   facade: 'plain' | 'modern' | 'classic' | 'glass',
    #   led: true/false,
    #   shelves: Integer,
    #   hinge_count: Integer (optional, auto if nil),
    #   name: String
    # }
    def self.build(opts = {})
      s = SKBCam::Settings.all
      width   = (opts[:width_mm]  || 600).to_f.mm
      height  = (opts[:height_mm] || 720).to_f.mm
      depth   = (opts[:depth_mm]  || 560).to_f.mm
      thick   = s['panel_thickness_mm'].to_f.mm
      back_t  = s['back_thickness_mm'].to_f.mm
      gap     = s['door_gap_mm'].to_f.mm
      facade  = opts[:facade] || 'plain'
      led     = opts[:led] ? true : false
      shelves = (opts[:shelves] || 1).to_i
      name    = opts[:name] || "Cabinet_#{Time.now.to_i}"

      model = Sketchup.active_model
      model.start_operation('Create Cabinet', true)

      cabinet = model.active_entities.add_group
      cabinet.name = name
      ents = cabinet.entities

      panels = []

      # Two side panels (left/right)
      [0, width - thick].each_with_index do |x, i|
        side = build_panel(ents, [x, 0, 0], depth, height, thick, :y, :z)
        tag_panel(side, "#{name}_Side_#{i == 0 ? 'L' : 'R'}", depth, height, thick, s, grain: 'length')
        panels << side
      end

      # Bottom and top panels (between the sides)
      inner_w = width - 2 * thick
      [0, height - thick].each_with_index do |z, i|
        hz = build_panel(ents, [thick, 0, z], inner_w, depth, thick, :x, :y)
        tag_panel(hz, "#{name}_#{i == 0 ? 'Bottom' : 'Top'}", inner_w, depth, thick, s, grain: 'width')
        panels << hz
      end

      # Back panel — grooved-in or flat overlay depending on factory settings
      inner_h = height - 2 * thick
      back_depth_pos = (s['back_method'] == 'groove') ? depth - back_t - 5.mm : depth - back_t
      back = build_panel(ents, [thick, back_depth_pos, thick], inner_w, inner_h, back_t, :x, :z)
      tag_panel(back, "#{name}_Back", inner_w, inner_h, back_t, s, grain: 'length', material: 'HDF/Back')
      panels << back

      # Shelves (adjustable, evenly spaced)
      if shelves > 0
        shelf_gap = inner_h / (shelves + 1)
        (1..shelves).each do |n|
          z = thick + shelf_gap * n
          sh = build_panel(ents, [thick, 0, z], inner_w, depth - back_t - 5.mm, thick, :x, :y)
          tag_panel(sh, "#{name}_Shelf_#{n}", inner_w, depth - back_t - 5.mm, thick, s, grain: 'width')
          panels << sh
        end
      end

      # Door(s) — single or double leaf depending on width, styled by facade
      door_qty = width > 500.mm ? 2 : 1
      door_w = (width - gap * (door_qty + 1)) / door_qty
      door_qty.times do |i|
        x = gap + i * (door_w + gap)
        door = build_panel(ents, [x, -thick, gap], door_w, height - gap * 2, thick, :x, :z)
        style_facade(door, facade)
        tag_panel(door, "#{name}_Door_#{i + 1}", door_w, height - gap * 2, thick, s,
                   grain: 'length', material: "Facade_#{facade}", edge_all: true)
        panels << door

        # Hinges: 2 for doors under 1300mm, 3 above (standard rule)
        hinge_count = opts[:hinge_count] || (height > 1300.mm ? 3 : 2)
        add_hardware_marker(ents, [x + door_w - 20.mm, 0, height * 0.15], 'Hinge') if hinge_count >= 1
        add_hardware_marker(ents, [x + door_w - 20.mm, 0, height * 0.85], 'Hinge') if hinge_count >= 2
        add_hardware_marker(ents, [x + door_w - 20.mm, 0, height * 0.5], 'Hinge') if hinge_count >= 3
      end

      # Optional LED strip marker (groove line under the top panel)
      if led
        add_led_marker(ents, [thick, depth - 30.mm, height - thick - 5.mm], inner_w)
      end

      cabinet.set_attribute('skb_cam_system', 'cabinet_name', name)
      cabinet.set_attribute('skb_cam_system', 'width_mm', opts[:width_mm])
      cabinet.set_attribute('skb_cam_system', 'height_mm', opts[:height_mm])
      cabinet.set_attribute('skb_cam_system', 'depth_mm', opts[:depth_mm])
      cabinet.set_attribute('skb_cam_system', 'facade', facade)

      model.commit_operation
      cabinet
    end

    # --- helpers -----------------------------------------------------------

    def self.build_panel(ents, origin, a, b, c, axis_a, axis_b)
      # Builds a rectangular box panel starting at `origin` with extents
      # a (along axis_a), b (along axis_b) and c (the push/pull thickness,
      # along the third axis). Returns a real ComponentInstance (not a
      # Group) because OpenCutList only reads bounding boxes from
      # Components — it ignores Groups entirely.
      ox, oy, oz = origin
      face_pts =
        case [axis_a, axis_b]
        when [:y, :z]
          [[ox, oy, oz], [ox, oy + a, oz], [ox, oy + a, oz + b], [ox, oy, oz + b]]
        when [:x, :y]
          [[ox, oy, oz], [ox + a, oy, oz], [ox + a, oy + b, oz], [ox, oy + b, oz]]
        when [:x, :z]
          [[ox, oy, oz], [ox + a, oy, oz], [ox + a, oy, oz + b], [ox, oy, oz + b]]
        end
      grp = ents.add_group
      face = grp.entities.add_face(face_pts.map { |p| Geom::Point3d.new(*p) })
      face.pushpull(c)
      grp.to_component # converts in place; returns the ComponentInstance
    end

    def self.tag_panel(instance, label, len, wid, thick, settings, grain: 'length', material: nil, edge_all: false)
      # 1) Real SketchUp material — this is what OpenCutList actually reads.
      mat_name = material || "Melamine_#{thick.to_mm.round}mm"
      model = Sketchup.active_model
      mat = model.materials[mat_name] || model.materials.add(mat_name)
      instance.definition.entities.grep(Sketchup::Face).each { |f| f.material = mat }

      # 2) Component + definition naming — OpenCutList lists parts by name.
      instance.definition.name = label
      instance.name = label

      # 3) Our own supplementary dictionary — used by BomEngine/pricing,
      #    and safe to ignore for anyone using OpenCutList instead.
      cl = instance.definition.attribute_dictionary('cutlist', true)
      cl['name']              = label
      cl['length_mm']         = len.to_mm.round(1)
      cl['width_mm']          = wid.to_mm.round(1)
      cl['thickness_mm']      = thick.to_mm.round(1)
      cl['material']          = mat_name
      cl['grain_direction']   = grain
      cl['edge_banding']      = edge_all ? 'all_sides' : 'long_sides'
      cl['edge_thickness_mm'] = settings['edge_band_mm']
      cl['quantity']          = 1
      instance
    end

    def self.style_facade(door_instance, style)
      # Placeholder for facade styling: modern (flat, thin edge), classic
      # (raised panel look via extra frame groove), glass (transparent
      # material). Kept lightweight — assigns a named material so it's
      # visually distinguishable and traceable in the cut list.
      # NOTE: tag_panel() runs after this and will overwrite the material
      # with its own name unless a facade-specific `material:` is passed,
      # so the facade color set here is preserved by passing that name
      # through to tag_panel from build().
      model = Sketchup.active_model
      mat_name = "Facade_#{style}"
      mat = model.materials[mat_name] || model.materials.add(mat_name)
      case style
      when 'glass'
        mat.alpha = 0.3
        mat.color = Sketchup::Color.new(200, 220, 230)
      when 'modern'
        mat.color = Sketchup::Color.new(40, 40, 40)
      when 'classic'
        mat.color = Sketchup::Color.new(120, 80, 50)
      else
        mat.color = Sketchup::Color.new(230, 230, 230)
      end
      door_instance.definition.entities.grep(Sketchup::Face).each { |f| f.material = mat }
    end

    def self.add_hardware_marker(ents, point, kind)
      pt = Geom::Point3d.new(*point)
      marker = ents.add_cpoint(pt)
      marker.set_attribute('skb_cam_system', 'hardware_type', kind)
    end

    def self.add_led_marker(ents, origin, length)
      p1 = Geom::Point3d.new(origin[0], origin[1], origin[2])
      p2 = Geom::Point3d.new(origin[0] + length, origin[1], origin[2])
      edge = ents.add_line(p1, p2)
      edge.set_attribute('skb_cam_system', 'led_strip', true)
    end
  end
end
