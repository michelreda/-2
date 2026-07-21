# ML Cabinets - Library Handler
# Type detection, name validation, and routing dispatcher for Add to Library.

require 'sketchup.rb'
require 'json'
require 'fileutils'

module MLCabinets
  module UI
    class LibraryHandler

      # Registry of supported library object types.
      # Only types with a non-nil handler are offered in the dropdown.
      # Order matters for auto-detection — more specific validators first.
      LIBRARY_TYPES = {
        'Cabinet' => {
          handler:      'AddCabinetToLibrary',
          validator:    :is_valid_cabinet,
          default_name: 'Cabinet',
          folder:       'cabinets',
          description:  'Full ML Cabinet preset (rebuilt from config)'
        },
        'Profile' => {
          handler: 'AddProfileToLibrary',
          validator: :is_valid_profile,
          default_name: 'Profile',
          folder: 'profiles',
          description: '2D profile shape (e.g. gola profile)'
        },
        'Panel' => {
          handler:      'AddPanelToLibrary',
          validator:    :is_valid_panel,
          default_name: 'Panel',
          folder:       nil,   # multi-folder — routed per sub-type
          description:  '3D flat panel (door, drawer front, decorative, end)'
        },
        'Appliance' => {
          handler:      'AddApplianceToLibrary',
          validator:    :is_valid_appliance,
          default_name: 'Appliance',
          folder:       'appliances',
          description:  '3D appliance component (oven, fridge, dishwasher, etc.)'
        },
        'Handle' => {
          handler:      'AddHandleToLibrary',
          validator:    :is_valid_handle,
          default_name: 'Handle',
          folder:       'handles',
          description:  '3D handle component (door, drawer, or both)'
        },
        'Leg' => {
          handler: 'AddLegToLibrary',
          validator: :is_valid_leg,
          default_name: 'Leg',
          folder: 'legs',
          description: '3D cabinet leg component'
        },
        'Material' => {
          handler:      'AddImageToLibrary',
          validator:    :is_valid_image,
          default_name: 'Material',
          folder:       'materials',
          description:  'Image-based material texture'
        }
      }.freeze

      # -------------------------------------------------------------------
      # Auto-detect the type of the selected entity (silent — no UI alerts)
      # -------------------------------------------------------------------

      def self.detect_entity_type(entity)
        return nil unless entity

        LIBRARY_TYPES.each do |type_name, config|
          next unless config[:handler]

          handler_class = get_handler_class(config[:handler])
          next unless handler_class
          next unless handler_class.respond_to?(config[:validator])

          begin
            # Suppress messagebox during detection
            original_messagebox = ::UI.method(:messagebox)
            ::UI.define_singleton_method(:messagebox) { |*_args| nil }

            result = handler_class.send(config[:validator], entity)

            ::UI.define_singleton_method(:messagebox, original_messagebox)
            return type_name if result
          rescue => e
            ::UI.define_singleton_method(:messagebox, original_messagebox) if defined?(original_messagebox)
            puts "MLCabinets: detect_entity_type(#{type_name}) — #{e.message}" if MLCabinets::DEBUG
          end
        end

        nil
      end

      # -------------------------------------------------------------------
      # Validate entity against a specific type (with UI alerts)
      # -------------------------------------------------------------------

      def self.validate_entity_for_type(entity, type)
        config = LIBRARY_TYPES[type]
        return false unless config && config[:handler]

        handler_class = get_handler_class(config[:handler])
        return false unless handler_class && handler_class.respond_to?(config[:validator])

        begin
          handler_class.send(config[:validator], entity)
        rescue => e
          puts "MLCabinets: validate_entity_for_type(#{type}) — #{e.message}" if MLCabinets::DEBUG
          false
        end
      end

      # -------------------------------------------------------------------
      # Validation without popping a messagebox — for HtmlDialog flows.
      # Intercepts any UI.messagebox call the validator may make and captures
      # the message text. Returns [valid_bool, error_string_or_nil].
      # -------------------------------------------------------------------

      def self.validate_entity_with_message(entity, type)
        config = LIBRARY_TYPES[type]
        return [false, "Unknown type '#{type}'."] unless config && config[:handler]

        handler_class = get_handler_class(config[:handler])
        unless handler_class && handler_class.respond_to?(config[:validator])
          return [false, "No handler available for #{type}."]
        end

        captured = nil
        original = ::UI.method(:messagebox)
        begin
          ::UI.define_singleton_method(:messagebox) { |msg, *_| captured = msg.to_s; nil }
          result = handler_class.send(config[:validator], entity)
          ::UI.define_singleton_method(:messagebox, original)
          [result, captured]
        rescue => e
          begin; ::UI.define_singleton_method(:messagebox, original); rescue; end
          puts "MLCabinets: validate_entity_with_message(#{type}) — #{e.message}" if MLCabinets::DEBUG
          [false, e.message]
        end
      end

      # -------------------------------------------------------------------
      # Name validation — safe for file systems and JS
      # -------------------------------------------------------------------

      def self.validate_name(name)
        if name.nil? || name.strip.empty?
          ::UI.messagebox("Name cannot be empty.")
          return false
        end

        clean = name.strip

        if clean.length > 50
          ::UI.messagebox("Name is too long (maximum 50 characters).")
          return false
        end

        if clean =~ /^\d/
          ::UI.messagebox("Name cannot start with a number.")
          return false
        end

        if clean =~ /[^a-zA-Z0-9_\- ]/
          bad = clean.scan(/[^a-zA-Z0-9_\- ]/).uniq.join(', ')
          ::UI.messagebox(
            "Name contains invalid characters: #{bad}\n\n" \
            "Only letters, numbers, underscores, hyphens, and spaces are allowed.\n" \
            "Spaces will be converted to underscores."
          )
          return false
        end

        # Reserved Windows file names
        if clean =~ /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i
          ::UI.messagebox("'#{clean}' is a reserved system name. Please choose a different name.")
          return false
        end

        true
      end

      # -------------------------------------------------------------------
      # Default name from component definition
      # -------------------------------------------------------------------

      def self.get_default_name(entity, type)
        config = LIBRARY_TYPES[type]
        fallback = config ? config[:default_name] : 'Preset'

        candidate = nil

        # Cabinets store their display name in the ml_cabinets custom dict
        if type == 'Cabinet' && entity.respond_to?(:definition)
          cab_name = entity.definition.get_attribute('ml_cabinets', 'cab_name')
          candidate = cab_name if cab_name.is_a?(String) && !cab_name.strip.empty?
        end

        if candidate.nil?
          if entity.respond_to?(:name) && !entity.name.to_s.strip.empty?
            candidate = entity.name
          elsif entity.respond_to?(:definition) && !entity.definition.name.to_s.strip.empty?
            candidate = entity.definition.name
          end
        end

        if candidate
          clean = candidate.strip
                           .gsub(/[^a-zA-Z0-9_\-\s]/, '')
                           .gsub(/\s+/, '_')
                           .gsub(/_+/, '_')
                           .gsub(/^_+|_+$/, '')
          clean = "#{fallback}_#{clean}" if clean =~ /^\d/
          return clean if !clean.empty? && clean.length <= 50
        end

        fallback
      end

      # -------------------------------------------------------------------
      # Available types (only those with implemented handlers)
      # -------------------------------------------------------------------

      def self.get_available_types
        LIBRARY_TYPES.select { |_, c| c[:handler] }.keys
      end

      # -------------------------------------------------------------------
      # Type description (for error messages)
      # -------------------------------------------------------------------

      def self.get_type_description(type)
        config = LIBRARY_TYPES[type]
        config ? config[:description] : 'Unknown type'
      end

      # -------------------------------------------------------------------
      # Route to the correct handler
      # -------------------------------------------------------------------

      def self.process_entity(entity, type, name)
        config = LIBRARY_TYPES[type]
        return false unless config && config[:handler]

        handler_class = get_handler_class(config[:handler])
        return false unless handler_class

        begin
          handler_class.set_entity_and_name(entity, name)
          handler_class.process_library_addition
        rescue => e
          puts "MLCabinets: process_entity(#{type}) — #{e.message}" if MLCabinets::DEBUG
          ::UI.messagebox("An error occurred while processing the #{type.downcase}:\n#{e.message}")
          false
        end
      end

      # -------------------------------------------------------------------
      private
      # -------------------------------------------------------------------

      def self.get_handler_class(handler_name)
        return nil unless handler_name
        MLCabinets.const_get(handler_name) if MLCabinets.const_defined?(handler_name)
      rescue NameError
        nil
      end

    end # class LibraryHandler
  end # module UI
end # module MLCabinets
