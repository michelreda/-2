module SKBCam
  # Persists "factory system" rules: panel thickness, door gap, back-panel
  # method, hardware defaults, edge banding, sheet size — everything the
  # cabinet generator and the cut-list engine rely on.
  module Settings
    DICT = 'skb_cam_settings'

    DEFAULTS = {
      'panel_thickness_mm'   => 18,
      'back_thickness_mm'    => 5,
      'door_gap_mm'          => 3,       # خلوص بين الضلف
      'back_method'          => 'groove', # 'groove' or 'flat'
      'shelf_setback_mm'     => 0,
      'hinge_type'           => 'standard_35mm',
      'drawer_slide_type'    => 'ball_bearing',
      'edge_band_mm'         => 1,
      'sheet_length_mm'      => 2440,
      'sheet_width_mm'       => 1220,
      'grain_direction'      => 'length', # default grain along length
      'currency'             => 'EGP',
      'material_price_per_sqm' => 0,
      'labor_price_per_unit' => 0
    }.freeze

    def self.model
      Sketchup.active_model
    end

    def self.all
      dict = model.attribute_dictionary(DICT, true)
      settings = DEFAULTS.dup
      DEFAULTS.each_key do |k|
        v = dict[k]
        settings[k] = v unless v.nil?
      end
      settings
    end

    def self.set(hash)
      dict = model.attribute_dictionary(DICT, true)
      hash.each do |k, v|
        next unless DEFAULTS.key?(k)
        dict[k] = v
      end
      all
    end

    def self.get(key)
      all[key.to_s]
    end
  end
end
