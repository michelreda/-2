# ML Cabinets - Scale Observer
# Watches for cabinet instances being scaled and logs a success message.
# Uses EntitiesObserver on model.active_entities for reliability —
# per-instance observers get detached when the DC engine redraws.

module MLCabinets
  module UI
    class ScaleObserver < Sketchup::EntitiesObserver

      DEBOUNCE_SEC = 0.5  # ignore duplicate callbacks within this window

      def initialize
        super
        @last_fire = {}   # entityID => Time
      end

      # Fired whenever any entity in the observed Entities collection
      # is modified (moved, scaled, attribute change, etc.).
      def onElementModified(entities, entity)
        return unless entity.valid?
        return unless entity.is_a?(Sketchup::ComponentInstance)
        return unless MLCabinets::CabinetDC.cabinet_instance?(entity)

        now = Time.now.to_f
        last = @last_fire[entity.entityID] || 0.0
        return if (now - last) < DEBOUNCE_SEC

        @last_fire[entity.entityID] = now
        success = MLCabinets::CabinetDC.recalculate_groups(entity)
        if success
          puts "✅ Cabinet '#{entity.name}' was scaled successfully." if MLCabinets::DEBUG
          # Deferred so redraw_with_undo runs outside the observer callback
          ::UI.start_timer(0) { MLCabinets::CabinetDC.redraw_dc(entity) if entity.valid? }
        end
      end

    end # class ScaleObserver

    module ScaleObserverManager

      @@observer = nil unless defined?(@@observer)

      # Attach the observer to model.active_entities.
      def self.attach
        detach
        model = Sketchup.active_model
        return unless model

        @@observer = ScaleObserver.new
        model.active_entities.add_observer(@@observer)
        puts "[ScaleObserver] Attached to active_entities" if MLCabinets::DEBUG
      end

      # Remove the observer.
      def self.detach
        return unless @@observer
        model = Sketchup.active_model
        return unless model

        begin
          model.active_entities.remove_observer(@@observer)
        rescue
          # ignore
        end
        @@observer = nil
      end

      # No-op kept for API compatibility (called from cabinet_dc.rb).
      # The entities-level observer already covers new instances.
      def self.attach_to(_instance)
        # ensure observer is attached
        attach unless @@observer
      end

    end # module ScaleObserverManager
  end # module UI
end # module MLCabinets
