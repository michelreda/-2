# ML Cabinets - Add Image to Library
# Validates a Sketchup::Image entity, extracts its pixel data via image_rep,
# saves it as a PNG material preset, and updates the centralized presets index.

require 'sketchup.rb'
require 'json'
require 'securerandom'
require 'fileutils'

module MLCabinets
  class AddImageToLibrary

    @entity     = nil
    @image_name = nil
    @category   = nil   # e.g. 'wood', 'marble', 'metal', 'color', 'glass'
    @grain      = 'horizontal'  # 'horizontal' | 'vertical'

    # Unified library folder under libraries/
    MATERIAL_LIBRARY_FOLDER = 'materials'.freeze unless defined?(MATERIAL_LIBRARY_FOLDER)

    # Available material categories — displayed in Add to Library dialog
    ALL_CATEGORIES = ['Wood', 'Marble', 'Metal', 'Color', 'Glass'].freeze unless defined?(ALL_CATEGORIES)

    # -----------------------------------------------------------------
    # Public API (called by AddToLibraryDialog)
    # -----------------------------------------------------------------

    def self.set_entity_and_name(entity, name)
      @entity     = entity
      @image_name = name
    end

    def self.set_sub_types(sub_types)
      @category = Array(sub_types).first&.downcase
    end

    def self.set_grain(grain)
      @grain = %w[horizontal vertical].include?(grain) ? grain : 'horizontal'
    end

    # Full workflow — extract image_rep and save as material preset.
    def self.process_library_addition
      return false if @category.nil? || @category.empty?

      begin
        folder = material_preset_folder_path

        # 1. Extract image_rep from the Sketchup::Image entity
        img_rep = @entity.image_rep

        # 2. Save original image as PNG (this IS the material texture)
        png_path = File.join(folder, "#{@image_name}.png")
        img_rep.save_file(png_path)

        unless File.exist?(png_path)
          ::UI.messagebox("Failed to save image data for '#{@image_name}'.")
          return false
        end

        # 3. Compute a representative color from the center pixel
        center_color = sample_center_color(img_rep)

        # 4. Save metadata
        save_metadata(folder, img_rep, center_color)

        ::UI.messagebox(
          "Material '#{@image_name}' has been successfully added to the library.\n" \
          "Category: #{@category.capitalize}"
        )
        true
      rescue => e
        puts "MLCabinets: AddImageToLibrary error — #{e.message}" if MLCabinets::DEBUG
        puts e.backtrace.first(5).join("\n") if MLCabinets::DEBUG
        ::UI.messagebox("An error occurred while adding the image to the library:\n#{e.message}")
        false
      end
    end

    # -----------------------------------------------------------------
    # Validation — entity must be a Sketchup::Image with pixel data
    # -----------------------------------------------------------------

    def self.is_valid_image(entity)
      unless entity.is_a?(Sketchup::Image)
        ::UI.messagebox("The selected entity must be an Image to be added as a material.")
        return false
      end

      begin
        img_rep = entity.image_rep
        unless img_rep && img_rep.width > 0 && img_rep.height > 0
          ::UI.messagebox("The selected image does not contain valid pixel data.")
          return false
        end
      rescue ArgumentError
        ::UI.messagebox("The selected image is corrupt and lacks image data.")
        return false
      end

      true
    rescue => e
      puts "MLCabinets: AddImageToLibrary.is_valid_image error — #{e.message}" if MLCabinets::DEBUG
      ::UI.messagebox("An error occurred while validating the image:\n#{e.message}")
      false
    end

    # -----------------------------------------------------------------
    # Metadata
    # -----------------------------------------------------------------

    def self.save_metadata(folder, img_rep, center_color)
      meta = generate_metadata(img_rep, center_color)
      save_individual_json(meta, folder)
      save_to_presets_index(meta)
    rescue => e
      puts "MLCabinets: AddImageToLibrary metadata save error — #{e.message}" if MLCabinets::DEBUG
    end

    def self.generate_metadata(img_rep, center_color)
      color_hex = center_color ? format('#%02X%02X%02X', center_color.red, center_color.green, center_color.blue) : nil

      {
        'id'           => SecureRandom.uuid,
        'name'         => @image_name,
        'type'         => 'material',
        'grain'        => @grain,
        'category'     => @category,
        'source'       => @category,
        'user_created' => !DevUtils.development_mode?,
        'created_at'   => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tier'         => DevUtils.development_mode? ? 'full' : nil,
        'dimensions'   => {
          'width'  => img_rep.width,
          'height' => img_rep.height,
          'bpp'    => img_rep.bits_per_pixel
        },
        'color'        => color_hex,
        'description'  => "Material - #{@image_name.to_s.gsub('_', ' ')}",
        'thumbnail'    => "#{@image_name}/#{@image_name}.png",
        'files'        => {
          'png'  => "#{@image_name}/#{@image_name}.png",
          'json' => "#{@image_name}/#{@image_name}.json"
        }
      }
    end

    def self.save_individual_json(meta, folder)
      path = File.join(folder, "#{@image_name}.json")
      File.write(path, JSON.pretty_generate(meta), encoding: 'UTF-8')
    end

    def self.save_to_presets_index(meta)
      presets_file = File.join(material_folder_path, 'presets.json')

      unless File.exist?(presets_file)
        File.write(presets_file, JSON.pretty_generate({ 'presets' => [] }), encoding: 'UTF-8')
      end

      data = JSON.parse(File.read(presets_file, encoding: 'UTF-8'))
      data['presets'] ||= []
      data['presets'].reject! { |p| p['name'] == @image_name }
      data['presets'] << meta.compact
      File.write(presets_file, JSON.pretty_generate(data), encoding: 'UTF-8')
    end

    # -----------------------------------------------------------------
    # Paths
    # -----------------------------------------------------------------

    # Top-level folder: libraries/materials/
    def self.material_folder_path
      dir = File.join(MLCabinets::PLUGIN_DIR, 'libraries', MATERIAL_LIBRARY_FOLDER)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # Per-preset subfolder: libraries/materials/{image_name}/
    def self.material_preset_folder_path
      dir = File.join(material_folder_path, @image_name)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      dir
    end

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

    # Sample the center pixel to get a representative color
    def self.sample_center_color(img_rep)
      img_rep.color_at_uv(0.5, 0.5)
    rescue => e
      puts "MLCabinets: sample_center_color error — #{e.message}" if MLCabinets::DEBUG
      nil
    end

  end # class AddImageToLibrary
end # module MLCabinets
