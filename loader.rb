# ML Cabinets Extension - Internal Loader
# Loaded when the extension is activated by SketchUp.

require 'fileutils'
require 'json'

module MLCabinets

  # ---------------------------------------------------------------------------
  # Constants (all guarded for hot-reload safety)
  # ---------------------------------------------------------------------------

  DEBUG = false unless defined?(DEBUG)

  EXTENSION_NAME  = 'ML Cabinets'.freeze  unless defined?(EXTENSION_NAME)
  AUTHOR          = 'ML Extensions'.freeze unless defined?(AUTHOR)
  COPYRIGHT       = '© 2026 ML Extensions'.freeze unless defined?(COPYRIGHT)
  DESCRIPTION     = 'Professional cabinet placement tool for SketchUp'.freeze unless defined?(DESCRIPTION)
  PLUGIN_DIR      = File.dirname(__FILE__) unless defined?(PLUGIN_DIR)

  TRIAL_DAYS          = 14     unless defined?(TRIAL_DAYS)
  INSTALLMENTS_TO_OWN = 12     unless defined?(INSTALLMENTS_TO_OWN)
  EDUCATION_MONTHS    = 6      unless defined?(EDUCATION_MONTHS)
  OFFLINE_GRACE_DAYS  = 7      unless defined?(OFFLINE_GRACE_DAYS)
  MAX_MACHINES        = 2      unless defined?(MAX_MACHINES)
  GUMROAD_FULL_PRODUCT_ID      = 'HZPkQJ6M5AO3JMqBxmFuVA=='.freeze unless defined?(GUMROAD_FULL_PRODUCT_ID)
  GUMROAD_EDUCATION_PRODUCT_ID = 'KIe4RZyg4cyf-C7rplItXA=='.freeze unless defined?(GUMROAD_EDUCATION_PRODUCT_ID)
  GUMROAD_PRODUCT_ID           = GUMROAD_FULL_PRODUCT_ID unless defined?(GUMROAD_PRODUCT_ID)

  GUMROAD_TRIAL_PRODUCT_URL     = 'https://mostafalamey1.gumroad.com/l/mlcabinets300-trial'.freeze unless defined?(GUMROAD_TRIAL_PRODUCT_URL)
  GUMROAD_EDUCATION_PRODUCT_URL = 'https://mostafalamey1.gumroad.com/l/mlcabinets300-education'.freeze unless defined?(GUMROAD_EDUCATION_PRODUCT_URL)
  GUMROAD_FULL_PRODUCT_URL      = 'https://mostafalamey1.gumroad.com/l/mlcabinets300-full'.freeze unless defined?(GUMROAD_FULL_PRODUCT_URL)
  GUMROAD_PRODUCT_URL           = GUMROAD_FULL_PRODUCT_URL unless defined?(GUMROAD_PRODUCT_URL)

  def self.read_version_from_file
    f = File.join(File.dirname(__FILE__), 'VERSION')
    File.exist?(f) ? File.read(f).strip : '0.0.0'
  rescue
    '0.0.0'
  end

  VERSION = read_version_from_file.freeze unless defined?(VERSION)

  def self.print_version
    puts "#{EXTENSION_NAME} v#{VERSION}"
    puts COPYRIGHT
    puts "Ruby: #{RUBY_VERSION}, SketchUp: #{Sketchup.version}"
  end

  # ---------------------------------------------------------------------------
  # Load license manager FIRST (before any other requires)
  # ---------------------------------------------------------------------------

  require File.join(PLUGIN_DIR, 'license_manager.rb')

  # ---------------------------------------------------------------------------
  # Load core modules
  # ---------------------------------------------------------------------------

  require File.join(PLUGIN_DIR, 'ui', 'layer_manager.rb')
  require File.join(PLUGIN_DIR, 'blank_dc.rb')
  require File.join(PLUGIN_DIR, 'drawer_dc.rb')
  require File.join(PLUGIN_DIR, 'drawer_face_dc.rb')
  require File.join(PLUGIN_DIR, 'door_leaf_dc.rb')
  require File.join(PLUGIN_DIR, 'panel_dc.rb')
  require File.join(PLUGIN_DIR, 'handle_dc.rb')
  require File.join(PLUGIN_DIR, 'shelf_dc.rb')
  require File.join(PLUGIN_DIR, 'profile_dc.rb')
  require File.join(PLUGIN_DIR, 'appliance_dc.rb')
  require File.join(PLUGIN_DIR, 'item_dc.rb')
  require File.join(PLUGIN_DIR, 'group_dc.rb')
  require File.join(PLUGIN_DIR, 'material_helper.rb')
  require File.join(PLUGIN_DIR, 'cabinet_dc.rb')
  require File.join(PLUGIN_DIR, 'corner_cabinet_dc.rb')

  # ---------------------------------------------------------------------------
  # Load dialogs
  # ---------------------------------------------------------------------------

  require File.join(PLUGIN_DIR, 'dialogs', 'new_cabinet_dialog.rb')
  require File.join(PLUGIN_DIR, 'dialogs', 'cabinet_library_dialog.rb')
  require File.join(PLUGIN_DIR, 'dialogs', 'add_to_library_dialog.rb')
  require File.join(PLUGIN_DIR, 'dialogs', 'style_picker_dialog.rb')
  require File.join(PLUGIN_DIR, 'cabinet_schedule_collector.rb')
  require File.join(PLUGIN_DIR, 'ui', 'cabinet_thumbnail_capture.rb')
  require File.join(PLUGIN_DIR, 'dialogs', 'schedule_manager_dialog.rb')
  require File.join(PLUGIN_DIR, 'dialogs', 'user_manual_dialog.rb')
  require File.join(PLUGIN_DIR, 'dialogs', 'about_dialog.rb')

  # ---------------------------------------------------------------------------
  # Load UI
  # ---------------------------------------------------------------------------

  require File.join(PLUGIN_DIR, 'ui', 'scale_observer.rb')
  require File.join(PLUGIN_DIR, 'ui', 'placement_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'library_handler.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_leg_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_appliance_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_profile_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_panel_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_handle_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_image_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'grain_picker_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'open_close_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'swap_door_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'swap_grain_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'manufacturing_prep.rb')
  require File.join(PLUGIN_DIR, 'ui', 'apply_preset_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'edit_cabinet_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'style_picker_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'end_panel_tool.rb')
  require File.join(PLUGIN_DIR, 'ui', 'add_to_library.rb')
  require File.join(PLUGIN_DIR, 'ui', 'context_menu.rb')
  require File.join(PLUGIN_DIR, 'ui', 'toolbar.rb')

  # ---------------------------------------------------------------------------
  # One-time data migrations
  # ---------------------------------------------------------------------------

  MLCabinets::AddCabinetToLibrary.migrate_presets_units

  # ---------------------------------------------------------------------------
  # Initialize
  # ---------------------------------------------------------------------------

  def self.initialize_extension
    return if defined?(@@extension_initialized) && @@extension_initialized

    MLCabinets::LicenseManager.initialize_license

    MLCabinets::UI::Toolbar.create_toolbar
    MLCabinets::UI::Toolbar.create_menu
    MLCabinets::UI::ContextMenu.create_context_menu
    MLCabinets::UI::ScaleObserverManager.attach
    MLCabinets::DevUtils.setup_dev_shortcuts
    MLCabinets::DevUtils.setup_console_commands

    # Start daily re-verification timer (skipped if permanent license)
    unless defined?(@@reverify_timer_started)
      ::UI.start_timer(86_400, true) { MLCabinets::LicenseManager.reverify }
      @@reverify_timer_started = true
    end

    @@extension_initialized = true
  rescue => e
    puts "MLCabinets: Error initializing — #{e.message}"
    puts e.backtrace.first(3).join("\n") if DEBUG
  end

  # ---------------------------------------------------------------------------
  # Development utilities
  # ---------------------------------------------------------------------------

  module DevUtils

    def self.development_mode?
      return true if ENV['ML_CABINETS_DEV'] == '1'
      return true if File.exist?(File.join(PLUGIN_DIR, '.dev'))
      false
    end

    # Adds "ML Cabinets Dev" submenu to Extensions menu (once per session).
    def self.setup_dev_shortcuts
      return unless development_mode?
      return if defined?(@@dev_menu_added)

      menu = ::UI.menu('Extensions').add_submenu('ML Cabinets Dev')

      menu.add_item("🔄 Reload Extension") {
        MLCabinets::UI::Toolbar.reload_extension
      }
      menu.add_separator
      menu.add_item('Hide Toolbar') {
        MLCabinets::UI::Toolbar.hide_toolbar
      }
      menu.add_item('Show Version') {
        MLCabinets.print_version
      }
      menu.add_item('Debug ON') {
        MLCabinets.debug_on
      }
      menu.add_item('Debug OFF') {
        MLCabinets.debug_off
      }

      @@dev_menu_added = true
    end

    # Defines top-level Ruby Console helpers (once per session).
    def self.setup_console_commands
      return unless development_mode?
      return if defined?(@@console_commands_added)

      Object.class_eval do
        # reload_ml_cabinets — hot-reloads the extension without restarting SketchUp
        def reload_ml_cabinets
          MLCabinets::UI::Toolbar.reload_extension
        end

        # mlc_version — prints version info to the Ruby Console
        def mlc_version
          MLCabinets.print_version
        end

        # mlc_debug — toggles debug output
        def mlc_debug(on = true)
          on ? MLCabinets.debug_on : MLCabinets.debug_off
        end
      end

      puts "MLCabinets: Console helpers ready — reload_ml_cabinets | mlc_version | mlc_debug"
      @@console_commands_added = true
    end
  end

  # ---------------------------------------------------------------------------
  # Debug helpers
  # ---------------------------------------------------------------------------

  def self.debug_on
    remove_const(:DEBUG) if const_defined?(:DEBUG)
    const_set(:DEBUG, true)
    puts "🐛 MLCabinets debug: ON"
  end

  def self.debug_off
    remove_const(:DEBUG) if const_defined?(:DEBUG)
    const_set(:DEBUG, false)
    puts "🔇 MLCabinets debug: OFF"
  end

end # module MLCabinets

# Boot
MLCabinets.initialize_extension
