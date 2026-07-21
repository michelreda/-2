# ML Cabinets — Cabinet Thumbnail Capture
# For each ML Cabinet definition in the active model that does not already
# have a cached thumbnail (either from the library or a previous capture),
# this module takes a front-left-elevated screenshot the same way
# AddCabinetToLibrary does, encodes the PNG as a base64 data URI, and
# stores it in the `ml_cabinets.cached_thumbnail` attribute on the definition.
#
# Called by ScheduleManagerDialog before collecting schedule data so that
# every cabinet has a preview, not just library presets.

require 'tmpdir'

module MLCabinets
  module CabinetThumbnailCapture

    CACHED_ATTR = 'cached_thumbnail'.freeze
    CACHE_VERSION_ATTR = 'cached_thumbnail_version'.freeze
    remove_const(:CACHE_VERSION) if const_defined?(:CACHE_VERSION)
    CACHE_VERSION = 3

    # ----------------------------------------------------------------
    # Public entry point
    # ----------------------------------------------------------------

    # Iterates all ML Cabinet instances in the model, captures a thumbnail
    # for each unique definition that is still missing one, and stores
    # the result as a base64 data URI on the definition.
    def self.capture_missing(model = Sketchup.active_model)
      instances = find_cabinet_instances(model)
      return if instances.empty?

      # One representative instance per definition — dedup by object_id
      seen = {}
      candidates = instances.select do |inst|
        defn = inst.definition
        next false if seen[defn.object_id]
        seen[defn.object_id] = true
        needs_thumbnail?(defn)
      end

      return if candidates.empty?

      candidates.each { |inst| capture_and_cache(model, inst) }
    rescue => e
      puts "MLCabinets::CabinetThumbnailCapture.capture_missing error — #{e.message}"
      puts e.backtrace.first(3).join("\n") if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
    end

    def self.capture_to_file(model, inst, path, width: 256, height: 256)
      return false unless inst&.valid?

      view = model.active_view

      # ── 1. Save current camera & rendering state ──────────────────
      saved_camera = Sketchup::Camera.new(
        view.camera.eye, view.camera.target, view.camera.up
      )
      saved_camera.perspective = view.camera.perspective?
      saved_camera.fov = view.camera.fov if saved_camera.perspective?

      ro       = model.rendering_options
      saved_ro = save_rendering_options(ro)

      # ── 2. Apply screenshot rendering settings ─────────────────────
      apply_rendering_options(ro)

      # ── 3. Frame the cabinet relative to its own local front ────────
      bounds   = visual_bounds(inst)
      center   = bounds.center
      radius   = visual_radius(bounds, center)
      radius   = visual_radius(inst.bounds, inst.bounds.center) if radius <= 0
      radius   = 1.0 if radius <= 0

      front = transformed_axis(inst.transformation, Y_AXIS)
      left  = transformed_axis(inst.transformation, X_AXIS).reverse
      up    = Z_AXIS

      fov = 28.0
      fov_radians = fov * Math::PI / 180.0
      distance = (radius / Math.tan(fov_radians / 2.0)) * 1.25
      view_dir = Geom::Vector3d.new(
        front.x + left.x * 0.6 + up.x * 0.45,
        front.y + left.y * 0.6 + up.y * 0.45,
        front.z + left.z * 0.6 + up.z * 0.45
      )
      view_dir.length = 1.0 if view_dir.length > 0

      eye = center.offset(view_dir, distance)
      camera = Sketchup::Camera.new(eye, center, up)
      camera.perspective = true
      camera.fov = fov
      view.camera = camera

      view.invalidate
      view.refresh if view.respond_to?(:refresh)
      File.delete(path) if File.exist?(path)
      result = write_image(view, path, width, height)
      result && image_written?(path)
    rescue => e
      puts "MLCabinets::CabinetThumbnailCapture.capture_to_file error — #{e.message}"
      puts e.backtrace.first(3).join("\n") if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      false
    ensure
      begin
        view.camera = saved_camera if defined?(saved_camera) && saved_camera
        saved_ro&.each { |k, v| ro[k] = v }
      rescue => re
        puts "MLCabinets::CabinetThumbnailCapture restore error — #{re.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      end
    end

    def self.write_image(view, path, width, height)
      ok = view.write_image(
        antialias:   true,
        transparent: true,
        compression: 0.9,
        width:       width,
        height:      height,
        filename:    path
      )
      return true if ok && image_written?(path)

      # Some SketchUp/Ruby contexts are more reliable with the legacy
      # positional API. It does not support transparency, but it is better
      # than dropping the schedule thumbnail entirely.
      File.delete(path) if File.exist?(path)
      view.write_image(path, width, height, true, 0.9)
    rescue => e
      puts "MLCabinets::CabinetThumbnailCapture.write_image error — #{e.message}"
      false
    end

    def self.image_written?(path)
      File.exist?(path) && File.size(path).to_i > 0
    end

    # ----------------------------------------------------------------
    # Private helpers
    # ----------------------------------------------------------------

    def self.needs_thumbnail?(defn)
      existing = defn.get_attribute('ml_cabinets', CACHED_ATTR, nil)
      version  = defn.get_attribute('ml_cabinets', CACHE_VERSION_ATTR, nil).to_i
      !existing.is_a?(String) || existing.empty? || version < CACHE_VERSION
    end

    # Recursively walk model entities, stopping at cabinet boundaries.
    def self.find_cabinet_instances(model)
      results = []
      walk_entities(model.entities, results)
      results
    end

    def self.walk_entities(entities, results)
      entities.each do |e|
        next unless e.is_a?(Sketchup::ComponentInstance)
        if CabinetDC.cabinet_instance?(e)
          results << e
        else
          walk_entities(e.definition.entities, results)
        end
      end
    end

    # Capture a single screenshot, encode it, and store on the definition.
    def self.capture_and_cache(model, inst)
      return unless inst.valid?

      defn = inst.definition

      # Isolate the target cabinet.
      hidden_entities = []
      model.active_entities.each do |e|
        next unless e.respond_to?(:visible?) && e.visible? && e != inst
        e.visible = false
        hidden_entities << e
      end

      safe_name = defn.name.gsub(/[^A-Za-z0-9_\-]/, '_')
      tmp_path  = File.join(Dir.tmpdir, "mlcab_thumb_#{safe_name}.png")

      ok = capture_to_file(model, inst, tmp_path)

      if ok && File.exist?(tmp_path)
        data = File.binread(tmp_path)
        b64  = [data].pack('m0')
        # Store via a transparent operation so it merges with whatever
        # SketchUp operation is currently on the undo stack.
        begin
          model.start_operation('Cache Cabinet Thumbnail', true, false, true)
          defn.set_attribute('ml_cabinets', CACHED_ATTR, "data:image/png;base64,#{b64}")
          defn.set_attribute('ml_cabinets', CACHE_VERSION_ATTR, CACHE_VERSION)
          model.commit_operation
        rescue
          model.abort_operation rescue nil
        end
        File.delete(tmp_path) rescue nil
        puts "MLCabinets: cached thumbnail for '#{defn.name}'" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      else
        puts "MLCabinets: thumbnail write_image failed for '#{defn.name}'"
      end

    rescue => e
      puts "MLCabinets::CabinetThumbnailCapture capture error (#{defn&.name}) — #{e.message}"
      puts e.backtrace.first(3).join("\n") if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
    ensure
      # ── Always restore the scene ──────────────────────────────────
      begin
        hidden_entities.each { |e| e.visible = true if e.respond_to?(:valid?) && e.valid? }
      rescue => re
        puts "MLCabinets::CabinetThumbnailCapture restore error — #{re.message}"
      end
    end

    def self.save_rendering_options(ro)
      keys = [
        'DrawGround',
        'DrawHorizon',
        'DrawHidden',
        'BackgroundColor',
        'DisplayWatermarks',
        'DisplaySketchAxes',
        'EdgeDisplayMode',
        'DisplaySectionCuts',
        'RenderMode',
        'SilhouetteWidth',
        'AmbientOcclusion',
        'DisplayDims',
        'DisplayGuides',
      ]
      keys.each_with_object({}) do |key, memo|
        begin
          memo[key] = ro[key]
        rescue
          # Rendering option availability varies between SketchUp versions.
        end
      end
    end

    def self.apply_rendering_options(ro)
      {
        'DrawGround'         => false,
        'DrawHorizon'        => false,
        'DrawHidden'         => false,
        'BackgroundColor'    => Sketchup::Color.new(255, 255, 255, 0),
        'DisplayWatermarks'  => false,
        'DisplaySketchAxes'  => false,
        'RenderMode'         => 2,    # Shaded with Textures
        'EdgeDisplayMode'    => 1,    # Profiles only
        'SilhouetteWidth'    => 2,
        'DisplaySectionCuts' => false,
        'AmbientOcclusion'   => false,
        'DisplayDims'        => false,
        'DisplayGuides'      => false,
      }.each do |key, value|
        begin
          ro[key] = value
        rescue
          # Rendering option availability varies between SketchUp versions.
        end
      end
    end

    def self.capture_helper_entity?(entity)
      klass = entity.class
      while klass
        name = klass.name.to_s
        return true if name.include?('Sketchup::ConstructionLine')
        return true if name.include?('Sketchup::ConstructionPoint')
        return true if name.include?('Sketchup::Dimension')
        klass = klass.superclass
      end
      false
    end

    def self.visual_bounds(inst)
      bb = Geom::BoundingBox.new
      add_visual_bounds(inst.definition.entities, inst.transformation, bb, {})
      bb.valid? ? bb : inst.bounds
    end

    def self.visual_radius(bounds, center)
      bounds_points(bounds).map { |pt| pt.distance(center) }.max.to_f
    end

    def self.add_visual_bounds(entities, transform, bounds, visited)
      entities.each do |entity|
        next if capture_helper_entity?(entity)

        if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
          defn = entity.definition
          key = [defn.object_id, transform.to_a, entity.transformation.to_a]
          next if visited[key]

          visited[key] = true
          add_visual_bounds(defn.entities, transform * entity.transformation, bounds, visited)
        elsif entity.respond_to?(:bounds)
          add_bounds_points(bounds, entity.bounds, transform)
        end
      end
    end

    def self.add_bounds_points(target_bounds, source_bounds, transform)
      return unless source_bounds&.valid?

      bounds_points(source_bounds).each { |pt| target_bounds.add(pt.transform(transform)) }
    end

    def self.bounds_points(bounds)
      min = bounds.min
      max = bounds.max
      [
        Geom::Point3d.new(min.x, min.y, min.z),
        Geom::Point3d.new(max.x, min.y, min.z),
        Geom::Point3d.new(max.x, max.y, min.z),
        Geom::Point3d.new(min.x, max.y, min.z),
        Geom::Point3d.new(min.x, min.y, max.z),
        Geom::Point3d.new(max.x, min.y, max.z),
        Geom::Point3d.new(max.x, max.y, max.z),
        Geom::Point3d.new(min.x, max.y, max.z),
      ]
    end

    def self.transformed_axis(transform, axis)
      vector = axis.clone.transform(transform)
      vector.length = 1.0 if vector.length > 0
      vector
    rescue
      axis.clone
    end

    private_class_method :needs_thumbnail?, :find_cabinet_instances,
                         :walk_entities, :capture_and_cache,
                         :write_image, :image_written?,
                         :save_rendering_options, :apply_rendering_options,
                         :capture_helper_entity?, :visual_bounds,
                         :visual_radius, :add_visual_bounds,
                         :add_bounds_points, :bounds_points,
                         :transformed_axis

  end # module CabinetThumbnailCapture
end # module MLCabinets
