module SKBCam
  # Extensible rule-based design/manufacturing checker.
  # Each rule is a small object responding to #check(model) -> Array<Issue>
  module Radar
    Issue = Struct.new(:severity, :message, :entity)

    RULES = []

    class OversizePanelRule
      def check(model)
        s = SKBCam::Settings.all
        max_l = s['sheet_length_mm'].to_f
        max_w = s['sheet_width_mm'].to_f
        issues = []
        model.definitions.each do |defn|
          next unless defn.attribute_dictionary('cutlist')
          cl = defn.attribute_dictionary('cutlist')
          l = cl['length_mm'].to_f
          w = cl['width_mm'].to_f
          fits_normal  = (l <= max_l && w <= max_w)
          fits_rotated = (l <= max_w && w <= max_l)
          unless fits_normal || fits_rotated
            issues << Issue.new(:error,
              "قطعة '#{cl['name']}' بمقاس #{l}x#{w}مم تتجاوز مقاس اللوح المتاح (#{max_l}x#{max_w}مم)",
              defn)
          end
        end
        issues
      end
    end
    RULES << OversizePanelRule.new

    class UngroupedGeometryRule
      def check(model)
        issues = []
        loose = model.active_entities.select { |e| e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge) }
        if loose.any?
          issues << Issue.new(:warning,
            "يوجد #{loose.size} عنصر هندسي (وجه/حافة) خارج أي مجموعة أو مكوّن في المستوى الرئيسي — يُنصح بتجميعه",
            nil)
        end
        issues
      end
    end
    RULES << UngroupedGeometryRule.new

    class MissingMaterialRule
      def check(model)
        issues = []
        model.definitions.each do |defn|
          next unless defn.attribute_dictionary('cutlist')
          has_material = defn.entities.grep(Sketchup::Face).any? { |f| f.material }
          if !has_material
            issues << Issue.new(:warning,
              "القطعة '#{defn.name}' ليس لها خامة (Material) محددة",
              defn)
          end
        end
        issues
      end
    end
    RULES << MissingMaterialRule.new

    class DuplicateOverlapRule
      def check(model)
        issues = []
        cabinets = model.active_entities.grep(Sketchup::Group).select { |g| g.get_attribute('skb_cam_system', 'cabinet_name') }
        cabinets.combination(2).each do |a, b|
          overlap = a.bounds.intersect(b.bounds)
          if overlap.valid?
            issues << Issue.new(:error,
              "تداخل هندسي محتمل بين '#{a.name}' و'#{b.name}'",
              a)
          end
        end
        issues
      end
    end
    RULES << DuplicateOverlapRule.new

    def self.run
      model = Sketchup.active_model
      RULES.flat_map { |rule| rule.check(model) }
    end

    def self.run_as_json
      run.map do |issue|
        { severity: issue.severity.to_s, message: issue.message }
      end
    end
  end
end
