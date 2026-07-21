# ML Cabinets - Manufacturing preparation helpers.

require 'sketchup.rb'

module MLCabinets
  module UI
    module ManufacturingPrep

      DA = 'dynamic_attributes'.freeze unless defined?(DA)
      FACE_PANEL_NAMES = %w[
        DoorLeafPanel
        DrawerFacePanel
        PanelFacePanel
        CornerDoorLeafPanel
      ].freeze
      FACE_SOFTEN_ANGLE_DEGREES = 30.0
      FACE_SOFTEN_ANGLE_RADIANS = FACE_SOFTEN_ANGLE_DEGREES.degrees

      def self.prepare_selected_cabinet
        model = Sketchup.active_model
        cabinets = _selected_cabinets(model)
        end_panels = _selected_end_panels(model)

        if cabinets.empty? && end_panels.empty?
          ::UI.messagebox('Select one or more ML cabinets or standalone end panels to prepare for manufacturing.')
          return
        end

        return unless _confirm_prepare(cabinets.length, end_panels.length)

        model.start_operation('Prepare for Manufacturing', true)

        prepared = 0
        prepared_end_panels = 0
        baked_side_total = 0
        baked_face_total = 0
        prepared_at = Time.now.to_i.to_s

        cabinets.each do |cabinet|
          next unless cabinet.valid?

          cabinet.make_unique if cabinet.respond_to?(:make_unique)
          MLCabinets::CabinetDC.redraw_dc(cabinet)

          baked_side_total += _bake_side_panel_assemblies(cabinet)
          baked_face_total += _bake_face_panel_children(cabinet)
          cabinet.definition.set_attribute('ml_cabinets', 'manufacturing_prepared', true)
          cabinet.definition.set_attribute('ml_cabinets', 'manufacturing_prepared_at', prepared_at)

          MLCabinets::CabinetDC.redraw_dc(cabinet)
          prepared += 1
        end

        end_panels.each do |end_panel|
          next unless end_panel.valid?
          next if cabinets.any? { |cabinet| cabinet == end_panel }

          if _replace_standalone_end_panel(end_panel)
            prepared_end_panels += 1
            baked_face_total += 1
          end
        end

        model.commit_operation

        baked_total = baked_side_total + baked_face_total
        if baked_total.positive?
          ::UI.messagebox(
            "Prepared #{prepared} cabinet(s) and #{prepared_end_panels} standalone end panel(s) for manufacturing.\n\n" \
            "Baked side panels: #{baked_side_total}\n" \
            "Baked door/drawer/panel faces: #{baked_face_total}"
          )
        else
          ::UI.messagebox(
            "Prepared #{prepared} cabinet(s) and #{prepared_end_panels} standalone end panel(s) for manufacturing, " \
            "but no supported modular assemblies needed baking."
          )
        end
      rescue => e
        model.abort_operation if model
        puts "MLCabinets::ManufacturingPrep error - #{e.message}"
        puts e.backtrace.first(6).join("\n") if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
        ::UI.messagebox("Could not prepare the selected object(s):\n#{e.message}")
      end

      def self._selected_cabinets(model)
        model.selection.grep(Sketchup::ComponentInstance).select do |entity|
          MLCabinets::CabinetDC.cabinet_instance?(entity)
        end.uniq
      end
      private_class_method :_selected_cabinets

      def self._selected_end_panels(model)
        model.selection.grep(Sketchup::ComponentInstance).select do |entity|
          _standalone_end_panel?(entity)
        end.uniq
      end
      private_class_method :_selected_end_panels

      def self._standalone_end_panel?(entity)
        return false unless entity.is_a?(Sketchup::ComponentInstance)
        return false if MLCabinets::CabinetDC.cabinet_instance?(entity)

        entity.get_attribute('ml_cabinets', 'type').to_s == 'end_panel' ||
          entity.name.to_s == 'End Panel'
      end
      private_class_method :_standalone_end_panel?

      def self._confirm_prepare(cabinet_count, end_panel_count)
        targets = []
        targets << "#{cabinet_count} selected cabinet(s)" if cabinet_count.positive?
        targets << "#{end_panel_count} standalone end panel(s)" if end_panel_count.positive?

        message = "Prepare #{targets.join(' and ')} for manufacturing?\n\n" \
                  "This will make selected cabinets unique and bake supported " \
                  "editable assemblies into manufacturing-ready solid parts.\n\n" \
                  "You won't be able to scale prepared cabinets or panels correctly after this."
        ::UI.messagebox(message, MB_YESNO) == IDYES
      end
      private_class_method :_confirm_prepare

      def self._bake_side_panel_assemblies(cabinet)
        cabinet_defn = cabinet.definition
        side_panels = cabinet_defn.entities.grep(Sketchup::ComponentInstance).select do |inst|
          inst.definition.get_attribute('ml_cabinets', 'manufacturing_role').to_s == 'side_panel_assembly'
        end

        side_panels.count { |side_inst| _replace_side_assembly(cabinet_defn, side_inst) }
      end
      private_class_method :_bake_side_panel_assemblies

      def self._bake_face_panel_children(cabinet)
        visited = {}
        _bake_face_panel_children_in_definition(cabinet.definition, visited)
      end
      private_class_method :_bake_face_panel_children

      def self._bake_face_panel_children_in_definition(defn, visited)
        return 0 if visited[defn.object_id]

        visited[defn.object_id] = true
        count = 0

        defn.entities.grep(Sketchup::ComponentInstance).to_a.each do |inst|
          next unless inst.valid?

          if FACE_PANEL_NAMES.include?(inst.name.to_s)
            count += 1 if _replace_face_panel_child(defn, inst)
            next
          end

          role = inst.definition.get_attribute('ml_cabinets', 'manufacturing_role').to_s
          next if role == 'side_panel_assembly' || role == 'side_panel'

          count += _bake_face_panel_children_in_definition(_editable_definition(inst), visited)
        end

        count
      end
      private_class_method :_bake_face_panel_children_in_definition

      def self._editable_definition(inst)
        inst.make_unique if inst.respond_to?(:make_unique)
        inst.definition
      rescue
        inst.definition
      end
      private_class_method :_editable_definition

      def self._replace_face_panel_child(parent_defn, panel_inst)
        baked_defn = _build_baked_face_definition(
          Sketchup.active_model,
          "#{parent_defn.name}_#{panel_inst.name}_Manufacturing",
          panel_inst
        )

        baked_inst = parent_defn.entities.add_instance(baked_defn, Geom::Transformation.new)
        baked_inst.name = panel_inst.name
        baked_inst.material = panel_inst.material if panel_inst.material
        baked_inst.layer = panel_inst.layer if panel_inst.respond_to?(:layer) && panel_inst.layer
        baked_inst.hidden = panel_inst.hidden?
        baked_inst.set_attribute('ml_cabinets', 'manufacturing_role', 'face_panel')
        baked_inst.set_attribute('ml_cabinets', 'source_panel_name', panel_inst.name.to_s)

        _copy_dimension_attrs(panel_inst, baked_inst)
        _align_bounds_min!(baked_inst, panel_inst)

        panel_inst.erase!
        true
      end
      private_class_method :_replace_face_panel_child

      def self._build_baked_face_definition(model, name, panel_inst)
        defn = model.definitions.add(name)
        defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
        defn.description = 'Manufacturing Face Panel - ML Cabinets'
        defn.set_attribute('ml_cabinets', 'manufacturing_role', 'face_panel')
        defn.set_attribute('ml_cabinets', 'manufacturing_baked', true)

        _copy_geometry(panel_inst.definition.entities, defn.entities, panel_inst.transformation, panel_inst.material)
        softened_edges = _soften_edges_by_angle(defn.entities, FACE_SOFTEN_ANGLE_RADIANS)
        defn.set_attribute('ml_cabinets', 'manufacturing_edges_softened', softened_edges)
        defn.set_attribute('ml_cabinets', 'manufacturing_soften_angle_degrees', FACE_SOFTEN_ANGLE_DEGREES)
        defn
      end
      private_class_method :_build_baked_face_definition

      def self._build_baked_face_definition_from_definition(model, name, source_defn, inherited_material = nil)
        defn = model.definitions.add(name)
        defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
        defn.description = 'Manufacturing Face Panel - ML Cabinets'
        defn.set_attribute('ml_cabinets', 'manufacturing_role', 'face_panel')
        defn.set_attribute('ml_cabinets', 'manufacturing_baked', true)

        _copy_geometry(source_defn.entities, defn.entities, Geom::Transformation.new, inherited_material)
        softened_edges = _soften_edges_by_angle(defn.entities, FACE_SOFTEN_ANGLE_RADIANS)
        defn.set_attribute('ml_cabinets', 'manufacturing_edges_softened', softened_edges)
        defn.set_attribute('ml_cabinets', 'manufacturing_soften_angle_degrees', FACE_SOFTEN_ANGLE_DEGREES)
        defn
      end
      private_class_method :_build_baked_face_definition_from_definition

      def self._replace_standalone_end_panel(panel_inst)
        baked_defn = _build_baked_face_definition_from_definition(
          Sketchup.active_model,
          "#{panel_inst.definition.name}_Manufacturing",
          panel_inst.definition,
          panel_inst.material
        )

        entities = _parent_entities(panel_inst)
        baked_inst = entities.add_instance(baked_defn, panel_inst.transformation)
        baked_inst.name = panel_inst.name
        baked_inst.material = panel_inst.material if panel_inst.material
        baked_inst.layer = panel_inst.layer if panel_inst.respond_to?(:layer) && panel_inst.layer
        baked_inst.hidden = panel_inst.hidden?
        baked_inst.set_attribute('ml_cabinets', 'manufacturing_role', 'face_panel')
        baked_inst.set_attribute('ml_cabinets', 'source_panel_name', panel_inst.name.to_s)
        baked_inst.set_attribute('ml_cabinets', 'type', 'end_panel')

        ep_side = panel_inst.get_attribute('ml_cabinets', 'ep_side')
        baked_inst.set_attribute('ml_cabinets', 'ep_side', ep_side) unless ep_side.to_s.empty?
        _copy_dimension_attrs(panel_inst, baked_inst)

        panel_inst.erase!
        true
      end
      private_class_method :_replace_standalone_end_panel

      def self._parent_entities(entity)
        parent = entity.parent
        return parent if parent.is_a?(Sketchup::Entities)
        return parent.entities if parent.respond_to?(:entities)

        Sketchup.active_model.active_entities
      end
      private_class_method :_parent_entities

      def self._copy_geometry(source_entities, target_entities, transform, inherited_material = nil)
        source_entities.each do |entity|
          case entity
          when Sketchup::Face
            _copy_face(entity, target_entities, transform, inherited_material)
          when Sketchup::ComponentInstance
            material = entity.material || inherited_material
            _copy_geometry(entity.definition.entities, target_entities, transform * entity.transformation, material)
          when Sketchup::Group
            material = entity.material || inherited_material
            _copy_geometry(entity.entities, target_entities, transform * entity.transformation, material)
          end
        end
      end
      private_class_method :_copy_geometry

      def self._copy_face(face, target_entities, transform, inherited_material)
        point_pairs = face.outer_loop.vertices.map do |vertex|
          source_point = vertex.position
          [source_point, source_point.transform(transform)]
        end
        point_pairs = _clean_point_pairs(point_pairs)
        return if point_pairs.length < 3

        points = point_pairs.map { |pair| pair[1] }
        new_face = target_entities.add_face(points)
        return unless new_face

        normal = face.normal.transform(transform)
        new_face.reverse! if new_face.normal.dot(normal) < 0
        new_face.material = face.material || inherited_material
        new_face.back_material = face.back_material || inherited_material
        _copy_face_uvs(face, new_face, point_pairs, true)
        _copy_face_uvs(face, new_face, point_pairs, false)
      rescue
        nil
      end
      private_class_method :_copy_face

      def self._copy_face_uvs(source_face, target_face, point_pairs, front)
        material = front ? target_face.material : target_face.back_material
        return unless material && material.texture

        uv_helper = source_face.get_UVHelper(front, !front)
        mapping = []
        point_pairs.first(3).each do |source_point, target_point|
          uvq = front ? uv_helper.get_front_UVQ(source_point) : uv_helper.get_back_UVQ(source_point)
          q = uvq.z
          q = 1.0 if q.abs < 1e-10
          mapping << target_point
          mapping << Geom::Point3d.new(uvq.x / q, uvq.y / q, 0)
        end

        target_face.position_material(material, mapping, front)
      rescue => e
        puts "MLCabinets::ManufacturingPrep UV copy skipped - #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      end
      private_class_method :_copy_face_uvs

      def self._soften_edges_by_angle(entities, angle_threshold)
        softened = 0
        entities.grep(Sketchup::Edge).to_a.each do |edge|
          next unless edge.valid?

          faces = edge.faces
          next unless faces.length == 2
          next unless _faces_within_angle?(faces[0], faces[1], angle_threshold)
          next unless _same_face_materials?(faces[0], faces[1])

          edge.soft = true
          edge.smooth = true
          softened += 1
        rescue
          next
        end
        softened
      end
      private_class_method :_soften_edges_by_angle

      def self._faces_within_angle?(face_a, face_b, angle_threshold)
        face_a.normal.angle_between(face_b.normal) <= angle_threshold
      end
      private_class_method :_faces_within_angle?

      def self._same_face_materials?(face_a, face_b)
        face_a.material == face_b.material && face_a.back_material == face_b.back_material
      end
      private_class_method :_same_face_materials?

      def self._copy_dimension_attrs(source, target)
        %w[lenx leny lenz].each do |attr|
          value = _number(source, attr)
          next unless value.positive?

          MLCabinets::CabinetDC.da_attr(target, attr, value.to_s, nil, 'CENTIMETERS')
        end
      end
      private_class_method :_copy_dimension_attrs

      def self._replace_side_assembly(cabinet_defn, side_inst)
        side = side_inst.definition.get_attribute('ml_cabinets', 'side').to_s
        side = side_inst.name.to_s.downcase.include?('right') ? 'right' : 'left' if side.empty?

        width = _dimension(side_inst, 'lenx', :width)
        depth = _dimension(side_inst, 'leny', :depth)
        height = _dimension(side_inst, 'lenz', :height)
        return false unless width.positive? && depth.positive? && height.positive?

        groove_depth = [_number(side_inst, 'back_groove_depth'), 0.0].max
        groove_width = [_number(side_inst, 'back_groove_width'), 0.0].max
        groove_y = [_number(side_inst, 'back_groove_y'), 0.0].max
        groove_depth = [groove_depth, width].min
        groove_width = [groove_width, [depth - groove_y, 0.0].max].min

        baked_defn = _build_baked_side_definition(
          Sketchup.active_model,
          "#{cabinet_defn.name}_#{side_inst.name}_Manufacturing",
          side,
          width,
          depth,
          height,
          groove_depth,
          groove_y,
          groove_width
        )

        baked_inst = cabinet_defn.entities.add_instance(baked_defn, _side_placement_transform(side_inst, side))
        _align_bounds_min!(baked_inst, side_inst)
        baked_inst.name = side_inst.name
        baked_inst.material = side_inst.material if side_inst.material
        baked_inst.layer = side_inst.layer if side_inst.respond_to?(:layer) && side_inst.layer
        baked_inst.hidden = side_inst.hidden?
        baked_inst.set_attribute('ml_cabinets', 'manufacturing_role', 'side_panel')
        baked_inst.set_attribute('ml_cabinets', 'side', side)

        MLCabinets::CabinetDC.da_attr(baked_inst, 'lenx', width.to_s, nil, 'CENTIMETERS')
        MLCabinets::CabinetDC.da_attr(baked_inst, 'leny', depth.to_s, nil, 'CENTIMETERS')
        MLCabinets::CabinetDC.da_attr(baked_inst, 'lenz', height.to_s, nil, 'CENTIMETERS')

        side_inst.erase!
        true
      end
      private_class_method :_replace_side_assembly

      def self._align_bounds_min!(target, source)
        source_min = source.bounds.min
        target_min = target.bounds.min
        delta = Geom::Vector3d.new(
          source_min.x - target_min.x,
          source_min.y - target_min.y,
          source_min.z - target_min.z
        )
        return if delta.length < 0.001

        target.transform!(Geom::Transformation.translation(delta))
      end
      private_class_method :_align_bounds_min!

      def self._build_baked_side_definition(model, name, side, width, depth, height, groove_depth, groove_y, groove_width)
        defn = model.definitions.add(name)
        defn.entities.erase_entities(defn.entities.to_a) unless defn.entities.length == 0
        defn.description = 'Manufacturing Side Panel - ML Cabinets'
        defn.set_attribute('ml_cabinets', 'manufacturing_role', 'side_panel')
        defn.set_attribute('ml_cabinets', 'side', side)
        defn.set_attribute('ml_cabinets', 'manufacturing_baked', true)

        points = _clean_points(_side_profile_points(width, depth, groove_depth, groove_y, groove_width))
        face = defn.entities.add_face(points)
        raise 'Could not create manufacturing side panel face.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(height)
        defn
      end
      private_class_method :_build_baked_side_definition

      def self._side_placement_transform(side_inst, side)
        return side_inst.transformation unless side.to_s == 'right'

        bounds = side_inst.bounds
        Geom::Transformation.translation(Geom::Vector3d.new(bounds.max.x, bounds.min.y, bounds.min.z)) *
          Geom::Transformation.scaling(-1, 1, 1)
      end
      private_class_method :_side_placement_transform

      def self._side_profile_points(width, depth, groove_depth, groove_y, groove_width)
        if groove_depth <= 0 || groove_width <= 0
          return [
            Geom::Point3d.new(0, 0, 0),
            Geom::Point3d.new(width, 0, 0),
            Geom::Point3d.new(width, depth, 0),
            Geom::Point3d.new(0, depth, 0)
          ]
        end

        groove_end = groove_y + groove_width
        inner_x = width - groove_depth
        [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(width, 0, 0),
          Geom::Point3d.new(width, groove_y, 0),
          Geom::Point3d.new(inner_x, groove_y, 0),
          Geom::Point3d.new(inner_x, groove_end, 0),
          Geom::Point3d.new(width, groove_end, 0),
          Geom::Point3d.new(width, depth, 0),
          Geom::Point3d.new(0, depth, 0)
        ]
      end
      private_class_method :_side_profile_points

      def self._clean_points(points)
        cleaned = []
        points.each do |point|
          cleaned << point unless cleaned.last && cleaned.last.distance(point) < 0.001
        end
        cleaned.pop if cleaned.length > 1 && cleaned.first.distance(cleaned.last) < 0.001
        cleaned
      end
      private_class_method :_clean_points

      def self._clean_point_pairs(point_pairs)
        cleaned = []
        point_pairs.each do |pair|
          cleaned << pair unless cleaned.last && cleaned.last[1].distance(pair[1]) < 0.001
        end
        cleaned.pop if cleaned.length > 1 && cleaned.first[1].distance(cleaned.last[1]) < 0.001
        cleaned
      end
      private_class_method :_clean_point_pairs

      def self._dimension(inst, attr, bounds_method)
        value = _number(inst, attr)
        return value if value.positive?

        inst.bounds.public_send(bounds_method).to_f
      end
      private_class_method :_dimension

      def self._number(inst, attr)
        value = inst.get_attribute(DA, attr)
        return 0.0 if value.nil?

        value.to_f
      end
      private_class_method :_number

    end
  end
end
