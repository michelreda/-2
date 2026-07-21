module MLCabinets
  module LayerManager

    FOLDER_NAME = 'ML Cabinets'.freeze unless defined?(FOLDER_NAME)

    # Layer names and their category keys.
    LAYER_NAMES = {
      carcass:      'Carcass',
      doors:        'Doors',
      drawers:      'Drawers',
      panels:       'Panels',
      legs:         'Legs',
      handles:      'Handles',
      profiles:     'Profiles',
      indications:  'Indications',
    }.freeze unless defined?(LAYER_NAMES)

    # Idempotent — finds or creates the "ML Cabinets" layer folder and all
    # sub-layers the first time it is called per model session. Returns a
    # Hash { carcass: Layer, doors: Layer, ... } ready for .layer = assignment.
    def self.ensure_ml_layers(model)
      lm = model.layers

      # Find or create the parent folder
      folder = lm.folders.find { |f| f.name == FOLDER_NAME }
      folder ||= lm.add_folder(FOLDER_NAME)

      layers = {}
      LAYER_NAMES.each do |key, name|
        # layers[name] returns nil when the layer doesn't exist
        layer = lm[name]
        if layer.nil?
          layer = lm.add(name)
          folder.add_layer(layer)
        elsif layer.folder != folder
          # Repair any orphaned layer that's not inside our folder
          folder.add_layer(layer)
        end
        layers[key] = layer
      end

      # Apply a dashed line style to the Indications layer so that door
      # open-side indicators render as dashed lines in all viewports.
      ind_layer = layers[:indications]
      if ind_layer && model.respond_to?(:line_styles)
        begin
          dash = model.line_styles.find { |s| s.name =~ /dash/i }
          ind_layer.line_style = dash if dash
        rescue => _e
          # line_style assignment is a visual enhancement; ignore silently.
        end
      end

      layers

    rescue => e
      puts "MLCabinets: LayerManager.ensure_ml_layers failed — #{e.message}" if MLCabinets::DEBUG
      {}
    end

  end
end
