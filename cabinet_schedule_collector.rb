# ML Cabinets - Cabinet Schedule Collector
# Scans the active SketchUp model for all ML_Cabinets instances,
# groups identical configurations by fingerprint, and returns
# schedule data rows for the Schedule Manager dialog.

require 'json'
require 'digest'

module MLCabinets
  module CabinetScheduleCollector

    DA = 'dynamic_attributes'.freeze unless defined?(DA)

    CATEGORY_LABELS = {
      'base'         => 'Base Cabinet',
      'upper'        => 'Wall Cabinet',
      'wall'         => 'Wall Cabinet',
      'tall'         => 'Tall Cabinet',
      'high'         => 'High Cabinet',
      'corner'       => 'Corner Cabinet',
      'corner_blind' => 'Corner Cabinet',
    }.freeze

    DOOR_TYPES = %w[
      door door-hinge-right door-hinge-left
      door-hinge-top door-hinge-bottom double-door
    ].freeze

    DRAWER_TYPES = %w[drawer false-drawer].freeze

    # ----------------------------------------------------------------
    # Public entry point
    # ----------------------------------------------------------------

    # Scans the active model, groups identical cabinet instances by
    # their component definition name, and returns an array of
    # schedule row hashes ready for the JS ScheduleManager.
    # +unit_system+ is 'metric' (cm) or 'imperial' (in).
    def self.collect_all_cabinets(unit_system = 'metric')
      model     = Sketchup.active_model
      instances = find_cabinet_instances(model)
      return [] if instances.empty?

      groups          = group_by_fingerprint(instances, unit_system)
      price_overrides = load_price_overrides(model)
      name_overrides  = load_name_overrides(model)

      rows = groups.map do |fingerprint, data|
        config = data[:config]
        defn   = data[:definition]
        qty    = data[:instances].size

        w, h, d = display_dimensions(defn, config, unit_system)
        door_count, drawer_count, shelf_count = count_items(config)

        # Price resolution: model schedule override > definition attr > config > 0
        price = (price_overrides[fingerprint] ||
                 defn.get_attribute('ml_cabinets', 'price', nil) ||
                 config[:price]).to_f

        # Name resolution: model schedule override > config name > definition cab_name
        display_name = name_overrides[fingerprint].to_s.strip
        if display_name.empty?
          display_name = config[:name].to_s.strip
        end
        if display_name.empty?
          display_name = defn.get_attribute('ml_cabinets', 'cab_name', '').to_s.strip
        end
        if display_name.empty?
          display_name = defn.name
        end

        cab_type = defn.get_attribute('ml_cabinets', 'type', '').to_s
        category = CATEGORY_LABELS[cab_type] || cab_type.capitalize

        {
          fingerprint:  fingerprint,
          id:           config[:id].to_s,
          name:         display_name,
          category:     category,
          width:        w,
          height:       h,
          depth:        d,
          door_count:   door_count,
          drawer_count: drawer_count,
          shelf_count:  shelf_count,
          quantity:     qty,
          price:        price.round(2),
          subtotal:     (price * qty).round(2),
          thumbnail:    resolve_thumbnail(defn, config),
          instance_ids: data[:instances].map(&:persistent_id),
        }
      end

      rows.sort_by { |r| r[:name] }

    rescue => e
      puts "MLCabinets::CabinetScheduleCollector: collect_all_cabinets error — #{e.message}"
      puts e.backtrace.first(5).join("\n") if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      []
    end

    # ----------------------------------------------------------------
    # Price & name override persistence (stored on the model)
    # ----------------------------------------------------------------

    def self.load_price_overrides(model)
      json = model.get_attribute('MLCabinets_SchedulePrices', 'overrides', '{}')
      JSON.parse(json.to_s)
    rescue
      {}
    end

    def self.save_price_override(model, fingerprint, price)
      overrides = load_price_overrides(model)
      overrides[fingerprint] = price.to_f
      model.set_attribute('MLCabinets_SchedulePrices', 'overrides', JSON.generate(overrides))
    end

    def self.load_name_overrides(model)
      json = model.get_attribute('MLCabinets_ScheduleNames', 'overrides', '{}')
      JSON.parse(json.to_s)
    rescue
      {}
    end

    def self.save_name_override(model, fingerprint, name)
      overrides = load_name_overrides(model)
      overrides[fingerprint] = name.to_s
      model.set_attribute('MLCabinets_ScheduleNames', 'overrides', JSON.generate(overrides))
    end

    # ----------------------------------------------------------------
    # Private helpers
    # ----------------------------------------------------------------

    def self.find_cabinet_instances(model)
      results = []
      collect_instances(model.entities, results)
      results
    end

    # Recursively walk entities; stop recursing into any component that is
    # itself identified as an ML_Cabinets cabinet (don't descend into sub-DCs).
    def self.collect_instances(entities, results)
      entities.each do |e|
        next unless e.is_a?(Sketchup::ComponentInstance)
        if CabinetDC.cabinet_instance?(e)
          results << e
        else
          collect_instances(e.definition.entities, results)
        end
      end
    end

    # Group instances by their structural cabinet configuration.
    # Two instances sharing the same type/dimensions/layout/materials/presets
    # are considered identical regardless of their SketchUp definition name
    # (which is always unique: Cabinet, Cabinet#1, Cabinet#2…).
    def self.group_by_fingerprint(instances, _unit_system)
      groups = {}
      instances.each do |inst|
        defn   = inst.definition
        config = parse_config(defn)
        next if config.nil?

        fp = config_fingerprint(config)
        groups[fp] ||= { config: config, definition: defn, instances: [] }
        groups[fp][:instances] << inst
      end
      groups
    end

    # Stable MD5 of the cabinet's structural attributes.
    # Excludes metadata (name, id, price, notes) that don't define geometry.
    FINGERPRINT_EXCLUDE = %i[name id price notes].freeze

    def self.config_fingerprint(config)
      structural = config.reject { |k, _| FINGERPRINT_EXCLUDE.include?(k) }
      Digest::MD5.hexdigest(JSON.generate(deep_sort(structural)))
    end

    # Recursively sort Hash keys so JSON output is stable regardless of
    # insertion order (Ruby 1.9+ hashes preserve insertion order).
    def self.deep_sort(obj)
      case obj
      when Hash
        obj.sort_by { |k, _| k.to_s }.each_with_object({}) do |(k, v), h|
          h[k] = deep_sort(v)
        end
      when Array
        obj.map { |v| deep_sort(v) }
      else
        obj
      end
    end

    def self.parse_config(defn)
      json = defn.get_attribute('ml_cabinets', 'config_json')
      return nil unless json.is_a?(String) && !json.empty?
      JSON.parse(json, symbolize_names: true)
    rescue
      nil
    end

    # Returns [width, height, depth] in display units.
    def self.display_dimensions(defn, config, unit_system)
      # Prefer live DA attributes (updated by ScaleObserver after any scale op)
      w_in = defn.get_attribute(DA, 'cab_width').to_f
      h_in = defn.get_attribute(DA, 'cab_height').to_f
      d_in = defn.get_attribute(DA, 'cab_depth').to_f

      if w_in > 0 && h_in > 0 && d_in > 0
        to_display([w_in, h_in, d_in], unit_system)
      else
        # Fall back to the config values
        unit  = (config[:unit] || 'cm').to_s
        raw   = [config[:width].to_f, config[:height].to_f, config[:depth].to_f]
        in_in = unit == 'in' ? raw : raw.map { |v| v / 2.54 }
        to_display(in_in, unit_system)
      end
    end

    def self.to_display(values_in_inches, unit_system)
      if unit_system == 'imperial'
        values_in_inches.map { |v| v.round(3) }
      else
        values_in_inches.map { |v| (v * 2.54).round(1) }
      end
    end

    # Count doors, drawers, and shelves from the config groups structure.
    def self.count_items(config)
      door_count   = 0
      drawer_count = 0
      shelf_count  = 0

      (config[:groups] || []).each do |group|
        next if %w[separator-group divider-group].include?(group[:type].to_s)
        (group[:items] || []).each do |item|
          t = item[:type].to_s
          if DOOR_TYPES.include?(t)
            door_count += 1
          elsif DRAWER_TYPES.include?(t)
            drawer_count += 1
          end
          shelf_count += item[:shelves].to_i
        end
      end

      [door_count, drawer_count, shelf_count]
    end

    # Resolve a thumbnail for the cabinet definition.
    # Priority: cached base64 on definition → library folder image → placeholder SVG.
    def self.resolve_thumbnail(defn, config)
      # 1. Cached thumbnail (set externally, e.g. by a capture tool)
      cached = defn.get_attribute('ml_cabinets', 'cached_thumbnail', nil)
      return cached if cached.is_a?(String) && cached.start_with?('data:')

      # 2. Library folder image by preset ID or cab_name
      [config[:id].to_s.strip, defn.get_attribute('ml_cabinets', 'cab_name', '').to_s.strip].each do |name|
        next if name.empty?
        img = find_library_image(name)
        return img if img
      end

      # 3. Placeholder SVG
      placeholder_svg
    end

    def self.find_library_image(name)
      lib_dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'cabinets', name)
      return nil unless Dir.exist?(lib_dir)

      ["#{name}.png", "#{name}.jpg", 'thumbnail.png', 'thumbnail.jpg', 'preview.png', 'preview.jpg'].each do |fname|
        path = File.join(lib_dir, fname)
        next unless File.exist?(path)
        data = File.binread(path)
        ext  = File.extname(path).delete('.').downcase
        mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png'
        return "data:#{mime};base64,#{[data].pack('m0')}"
      end
      nil
    rescue
      nil
    end

    def self.placeholder_svg
      svg = '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80" viewBox="0 0 80 80">' \
            '<rect width="80" height="80" fill="#eceef1" rx="4"/>' \
            '<rect x="12" y="10" width="56" height="60" fill="none" stroke="#c4cad4" stroke-width="2" rx="2"/>' \
            '<line x1="40" y1="10" x2="40" y2="70" stroke="#c4cad4" stroke-width="1.5"/>' \
            '<circle cx="37" cy="40" r="2.5" fill="#9da5b0"/>' \
            '<circle cx="43" cy="40" r="2.5" fill="#9da5b0"/>' \
            '</svg>'
      "data:image/svg+xml;base64,#{[svg].pack('m0')}"
    end

    private_class_method :find_cabinet_instances, :collect_instances,
                         :group_by_fingerprint, :parse_config,
                         :display_dimensions, :to_display,
                         :count_items, :resolve_thumbnail,
                         :find_library_image, :placeholder_svg,
                         :config_fingerprint, :deep_sort

  end
end
