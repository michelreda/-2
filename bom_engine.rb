module SKBCam
  module BomEngine
    # Walks every definition in the model carrying a "cutlist" attribute
    # dictionary (as written by CabinetGenerator, or by hand) and builds
    # an aggregated cut list, grouped by identical dimensions+material.
    def self.collect
      model = Sketchup.active_model
      rows = []
      model.active_entities.each do |ent|
        walk(ent, rows)
      end
      rows
    end

    def self.walk(ent, rows, qty = 1)
      if ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
        defn = ent.definition
        cl = defn.attribute_dictionary('cutlist')
        if cl
          rows << {
            'name'        => cl['name'],
            'length_mm'   => cl['length_mm'],
            'width_mm'    => cl['width_mm'],
            'thickness_mm'=> cl['thickness_mm'],
            'material'    => cl['material'],
            'grain'       => cl['grain_direction'],
            'edge_banding'=> cl['edge_banding'],
            'qty'         => cl['quantity'] || 1
          }
        end
        ent.entities.each { |sub| walk(sub, rows) } if ent.entities
      end
    end

    def self.aggregate
      rows = collect
      grouped = {}
      rows.each do |r|
        key = [r['name'], r['length_mm'], r['width_mm'], r['thickness_mm'], r['material']]
        if grouped[key]
          grouped[key]['qty'] += r['qty']
        else
          grouped[key] = r.dup
        end
      end
      grouped.values
    end

    def self.export_csv(path)
      rows = aggregate
      CSV.open(path, 'w') do |csv|
        csv << ['Name', 'Length(mm)', 'Width(mm)', 'Thickness(mm)', 'Material', 'Grain', 'Edge Banding', 'Qty']
        rows.each do |r|
          csv << [r['name'], r['length_mm'], r['width_mm'], r['thickness_mm'], r['material'], r['grain'], r['edge_banding'], r['qty']]
        end
      end
      path
    end

    # Simple price estimate: material area * price/sqm + labor per unit.
    def self.estimate_price
      s = SKBCam::Settings.all
      rows = aggregate
      total_area_sqm = 0.0
      total_qty = 0
      rows.each do |r|
        area = (r['length_mm'].to_f / 1000.0) * (r['width_mm'].to_f / 1000.0) * r['qty'].to_i
        total_area_sqm += area
        total_qty += r['qty'].to_i
      end
      material_cost = total_area_sqm * s['material_price_per_sqm'].to_f
      labor_cost = total_qty * s['labor_price_per_unit'].to_f
      {
        'total_area_sqm' => total_area_sqm.round(2),
        'total_pieces'   => total_qty,
        'material_cost'  => material_cost.round(2),
        'labor_cost'     => labor_cost.round(2),
        'total_cost'     => (material_cost + labor_cost).round(2),
        'currency'       => s['currency']
      }
    end

    def self.labels_text
      aggregate.map do |r|
        "#{r['name']} | #{r['length_mm']}x#{r['width_mm']}x#{r['thickness_mm']}mm | #{r['material']} | Qty:#{r['qty']}"
      end.join("\n")
    end
  end
end

require 'csv'
