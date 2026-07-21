# ML Cabinets - Add Cabinet to Library
# Saves a full ML Cabinet DC as a named preset by persisting its dialog
# config JSON and a front-view thumbnail.  No SKP/DAE export is needed
# because cabinets are entirely regenerated from their config at load time.
#
# Storage per preset:
#   libraries/cabinets/{Name}/{Name}.json  ← the original dialog config JSON
#   libraries/cabinets/{Name}/{Name}.png   ← 128×128 Hidden-Line thumbnail
# Central index:
#   libraries/cabinets/presets.json

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddCabinetToLibrary

    @cabinet      = nil
    @cabinet_name = nil
    @cabinet_original_transform = nil

    # ------------------------------------------------------------------
    # Public API — called by LibraryHandler / AddToLibraryDialog
    # ------------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @cabinet      = entity
      @cabinet_name = name
    end

    # Full workflow.
    def self.process_library_addition
      model = Sketchup.active_model
      model.start_operation('Add Cabinet to Library', true)

      begin
        # 1. Hide every other entity for a clean screenshot
        originally_visible = []
        model.active_entities.each do |ent|
          next unless ent.respond_to?(:visible?)
          if ent.visible? && ent != @cabinet
            originally_visible << ent
          end
          ent.visible = false if ent != @cabinet && ent.respond_to?(:visible=)
        end

        # 2. Move to origin for consistent framing
        move_to_origin

        # 3. Screenshot then save config
        preset_folder = cabinet_preset_folder_path
        ok_png  = take_screenshot(preset_folder)
        ok_json = save_config_json(preset_folder)
        success = ok_png && ok_json

        # 4. Persist metadata to index
        save_metadata if success

        # 5. Restore scene
        originally_visible.each { |ent| ent.visible = true if ent.valid? }
        restore_position

        model.commit_operation

        if success
          ::UI.messagebox("Cabinet '#{@cabinet_name}' has been successfully added to the library.")
        else
          ::UI.messagebox(
            "Some files could not be created for '#{@cabinet_name}'.\n" \
            "Check the Ruby Console for details."
          )
        end

        success
      rescue => e
        puts "MLCabinets: AddCabinetToLibrary error — #{e.message}" if MLCabinets::DEBUG
        model.abort_operation
        ::UI.messagebox("An error occurred while adding the cabinet to the library:\n#{e.message}")
        false
      end
    end

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    def self.is_valid_cabinet(entity)
      unless MLCabinets::CabinetDC.cabinet_instance?(entity)
        ::UI.messagebox(
          "The selected entity is not an ML Cabinet.\n\n" \
          "Only cabinets created with the ML Cabinets plugin can be saved to the cabinet library."
        )
        return false
      end

      config_json = entity.definition.get_attribute('ml_cabinets', 'config_json', nil)
      if config_json.nil? || config_json.strip.empty?
        ::UI.messagebox(
          "This cabinet does not have a saved configuration.\n\n" \
          "Only cabinets created through the New Cabinet dialog (version 1.0+) " \
          "can be saved to the library."
        )
        return false
      end

      # Pre-populate a sensible default name from the component definition
      defn_name = entity.definition.name
      @cabinet_name = defn_name unless defn_name.to_s.strip.empty?

      true
    end

    # ------------------------------------------------------------------
    # Origin repositioning (mirrors AddLegToLibrary)
    # ------------------------------------------------------------------

    def self.move_to_origin
      return unless @cabinet && @cabinet.valid?

      @cabinet_original_transform = @cabinet.transformation
      origin = @cabinet.transformation.origin
      vec = Geom::Vector3d.new(-origin.x, -origin.y, -origin.z)
      @cabinet.transformation = @cabinet_original_transform * Geom::Transformation.translation(vec)
    end

    def self.restore_position
      return unless @cabinet && @cabinet.valid? && @cabinet_original_transform
      @cabinet.transformation = @cabinet_original_transform
    end

    # ------------------------------------------------------------------
    # Screenshot — front-left elevated view, 128×128, Hidden Line
    # ------------------------------------------------------------------

    def self.take_screenshot(folder = cabinet_preset_folder_path)
      screenshot_path = File.join(folder, "#{@cabinet_name}.png")
      result = CabinetThumbnailCapture.capture_to_file(
        Sketchup.active_model,
        @cabinet,
        screenshot_path,
        width: 256,
        height: 256
      )

      puts "MLCabinets: cabinet screenshot — #{result ? 'ok' : 'failed'}" if MLCabinets::DEBUG
      result
    rescue => e
      puts "MLCabinets: cabinet screenshot error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # ------------------------------------------------------------------
    # Save the original dialog config JSON
    # ------------------------------------------------------------------

    def self.save_config_json(folder = cabinet_preset_folder_path)
      raw = @cabinet.definition.get_attribute('ml_cabinets', 'config_json', nil)
      return false if raw.nil? || raw.strip.empty?

      # Re-parse, stamp the library name and ownership, then pretty-print
      config = JSON.parse(raw)
      config['name']         = @cabinet_name.to_s
      config['user_created'] = !DevUtils.development_mode?
      path   = File.join(folder, "#{@cabinet_name}.json")
      File.write(path, JSON.pretty_generate(config), encoding: 'UTF-8')
      true
    rescue => e
      puts "MLCabinets: cabinet config JSON save error — #{e.message}" if MLCabinets::DEBUG
      false
    end

    # ------------------------------------------------------------------
    # Metadata — presets.json entry + per-preset index update
    # ------------------------------------------------------------------

    def self.save_metadata
      meta = generate_metadata
      save_to_presets_index(meta)
    rescue => e
      puts "MLCabinets: cabinet metadata save error — #{e.message}" if MLCabinets::DEBUG
    end

    def self.generate_metadata
      raw    = @cabinet.definition.get_attribute('ml_cabinets', 'config_json', '{}')
      config = JSON.parse(raw) rescue {}

      cab_type = config['type'] || 'base'
      unit     = config['unit'] || 'cm'
      w        = config['width'].to_f
      h        = config['height'].to_f
      d        = config['depth'].to_f

      dims = if unit == 'in'
               "#{w.round(2)}\" x #{h.round(2)}\" x #{d.round(2)}\""
             else
               "#{w.round(1)} x #{h.round(1)} x #{d.round(1)} cm"
             end

      {
        'id'           => SecureRandom.uuid,
        'name'         => @cabinet_name,
        'type'         => 'cabinet',
        'cabinet_type' => cab_type,
        'unit'         => unit,
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => dims,
        'description'  => "Cabinet preset - #{@cabinet_name.to_s.gsub('_', ' ')}",
        'thumbnail'    => "#{@cabinet_name}/#{@cabinet_name}.png",
        'files'        => {
          'json' => "#{@cabinet_name}/#{@cabinet_name}.json",
          'png'  => "#{@cabinet_name}/#{@cabinet_name}.png"
        }
      }
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(cabinet_folder_path, 'presets.json')

      data = if File.exist?(presets_file)
               JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
             else
               { 'presets' => [] }
             end

      data['presets'] ||= []
      # Replace any existing entry with the same name (overwrite)
      data['presets'].reject! { |p| p['name'] == @cabinet_name }
      data['presets'] << meta.compact

      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    rescue => e
      puts "MLCabinets: cabinet presets index save error — #{e.message}" if MLCabinets::DEBUG
    end

    # ------------------------------------------------------------------
    # One-time migration — backfills "unit" in presets.json entries
    # that were saved before this field was introduced.
    # Safe to call on every load (idempotent).
    # ------------------------------------------------------------------

    def self.migrate_presets_units
      presets_file = File.join(cabinet_folder_path, 'presets.json')
      return unless File.exist?(presets_file)

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      changed = false

      (data['presets'] || []).each do |entry|
        next if entry.key?('unit')

        # Derive unit from the individual cabinet JSON when available
        json_rel  = entry.dig('files', 'json')
        unit      = 'cm'
        if json_rel
          json_path = File.join(cabinet_folder_path, json_rel)
          if File.exist?(json_path)
            cabinet_cfg = JSON.parse(File.read(json_path, encoding: 'UTF-8')) rescue {}
            unit = cabinet_cfg['unit'] || 'cm'
          end
        end

        # Insert 'unit' right after 'cabinet_type' so the key order is logical
        entry['unit'] = unit
        changed = true
      end

      if changed
        File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
        puts 'MLCabinets: cabinet presets.json — backfilled "unit" for legacy entries.' if MLCabinets::DEBUG
      end
    rescue => e
      puts "MLCabinets: migrate_presets_units error — #{e.message}" if MLCabinets::DEBUG
    end

    # ------------------------------------------------------------------
    # Path helpers
    # ------------------------------------------------------------------

    # libraries/cabinets/
    def self.cabinet_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', 'cabinets')
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # libraries/cabinets/{name}/
    def self.cabinet_preset_folder_path
      dir = File.join(cabinet_folder_path, @cabinet_name)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

  end # class AddCabinetToLibrary
end # module MLCabinets
