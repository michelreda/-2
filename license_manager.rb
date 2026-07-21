# frozen_string_literal: true
# ML_Cabinets — License Manager
# Core security component. Handles trial, activation, education, subscription,
# permanent ownership, Gumroad API verification, and offline grace logic.
#
# Usage:
#   MLCabinets::LicenseManager.initialize_license   # call on startup
#   MLCabinets::LicenseManager.licensed?            # gating check
#   MLCabinets::LicenseManager.activate(key)        # returns result hash
#   MLCabinets::LicenseManager.state                # current state symbol

# ---------------------------------------------------------------------------
# Guarded stdlib requires (SketchUp Ruby may restrict stdlib in some builds)
# ---------------------------------------------------------------------------
begin; require 'digest';    rescue LoadError; end
begin; require 'base64';    rescue LoadError; end
begin; require 'fileutils'; rescue LoadError; end
begin; require 'json';      rescue LoadError; end
begin; require 'net/http';  rescue LoadError; end
begin; require 'net/https'; rescue LoadError; end
begin; require 'uri';       rescue LoadError; end
begin; require 'time';      rescue LoadError; end
begin; require 'socket';    rescue LoadError; end

module MLCabinets
  module LicenseManager
    extend self

    # -------------------------------------------------------------------------
    # Constants — all guarded for hot-reload safety
    # -------------------------------------------------------------------------
    PRODUCT_ID          = 'HZPkQJ6M5AO3JMqBxmFuVA=='.freeze      unless defined?(PRODUCT_ID)
    FULL_PRODUCT_ID     = (defined?(MLCabinets::GUMROAD_FULL_PRODUCT_ID) ? MLCabinets::GUMROAD_FULL_PRODUCT_ID : PRODUCT_ID).freeze unless defined?(FULL_PRODUCT_ID)
    EDUCATION_PRODUCT_ID = (defined?(MLCabinets::GUMROAD_EDUCATION_PRODUCT_ID) ? MLCabinets::GUMROAD_EDUCATION_PRODUCT_ID : '').freeze unless defined?(EDUCATION_PRODUCT_ID)
    PRODUCT_URL         = (defined?(MLCabinets::GUMROAD_PRODUCT_URL) ? MLCabinets::GUMROAD_PRODUCT_URL : 'https://mostafalamey1.gumroad.com/l/mlcabinets300').freeze unless defined?(PRODUCT_URL)
    TRIAL_DAYS          = 14   unless defined?(TRIAL_DAYS)
    EDU_MONTHS          = 6    unless defined?(EDU_MONTHS)
    INSTALLMENTS_TO_OWN = 12   unless defined?(INSTALLMENTS_TO_OWN)
    OFFLINE_GRACE_DAYS          = 7    unless defined?(OFFLINE_GRACE_DAYS)
    # Hard cap on how long we will keep a user licensed while fully offline
    # (no successful Gumroad verification). Beyond this the license demotes
    # to :subscription_lapsed. Must be >= OFFLINE_GRACE_DAYS.
    EXTENDED_OFFLINE_GRACE_DAYS = 30   unless defined?(EXTENDED_OFFLINE_GRACE_DAYS)
    MAX_MACHINES        = 2    unless defined?(MAX_MACHINES)
    VERIFY_URL          = 'https://api.gumroad.com/v2/licenses/verify'.freeze unless defined?(VERIFY_URL)
    LICENSE_SERVER_URL  = 'https://ml-cabinets-license.mlextensions.workers.dev'.freeze unless defined?(LICENSE_SERVER_URL)

    # -------------------------------------------------------------------------
    # Module-level state — guarded for hot-reload safety
    # -------------------------------------------------------------------------
    @@state      = :unlicensed unless defined?(@@state)
    @@data       = {}          unless defined?(@@data)
    @@last_error = nil         unless defined?(@@last_error)
    @@machine_id = nil         unless defined?(@@machine_id)
    # True when the license is kept active under extended offline grace and
    # the UI should surface a soft "please reconnect" warning.
    @@connectivity_warning   = false unless defined?(@@connectivity_warning)
    # Tracks whether determine_state has already attempted a silent Gumroad
    # refresh this session, so we don't repeat the network call on every
    # mutation. Reset on initialize_license (i.e. once per SketchUp launch).
    @@grace_retry_attempted  = false unless defined?(@@grace_retry_attempted)

    # =========================================================================
    # PUBLIC API
    # =========================================================================

    # Call once at extension startup to load persisted data and set state.
    def initialize_license
      mid = machine_id
      raw = read_data(mid)

      if raw.nil?
        # File missing OR present-but-unreadable (e.g. encrypted with an old
        # machine-id after a code update).  Start fresh so @@data always has
        # a valid :mid and write_data encrypts with the correct key.
        raw = first_run_data(mid)
        write_data(raw)
      elsif raw[:mid] != mid
        # Machine fingerprint mismatch — treat as fresh install on this machine.
        # Trial starts NOW; any previously stored license key is NOT transferred
        # (key re-activation on the new machine is required).
        raw = first_run_data(mid)
        write_data(raw)
      end

      @@data = raw
      # Fresh SketchUp session — allow one silent grace-retry.
      @@grace_retry_attempted = false
      @@connectivity_warning  = false
      determine_state
    rescue => e
      puts "MLCabinets LicenseManager#initialize_license: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      @@state = :unlicensed
    end

    # Returns true when the extension should be fully functional.
    # :trial, :licensed, :licensed_permanent, :education all grant access.
    def licensed?
      [:trial, :licensed, :licensed_permanent, :education].include?(@@state)
    rescue => e
      puts "MLCabinets LicenseManager#licensed?: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      false
    end

    # Current license state symbol.
    # Possible values: :trial, :trial_expired, :licensed, :licensed_permanent,
    #                  :education, :education_expired, :subscription_lapsed, :unlicensed
    def state
      @@state
    rescue
      :unlicensed
    end

    # True when the license is currently active but the machine has been
    # offline long enough that we couldn't re-verify with Gumroad within the
    # normal grace window. UI layers should show a soft "please reconnect"
    # banner when this returns true.
    def connectivity_warning?
      @@connectivity_warning == true
    rescue
      false
    end

    # Integer days remaining in trial (0 when expired or not in trial).
    def trial_days_remaining
      @@data ||= {}
      return 0 unless [:trial, :trial_expired].include?(@@state)
      elapsed  = Time.now.to_i - @@data[:ts].to_i
      remaining = TRIAL_DAYS - (elapsed / 86_400)
      [remaining, 0].max
    rescue => e
      puts "MLCabinets LicenseManager#trial_days_remaining: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      0
    end

    # Returns a summary hash safe for the UI layer.
    def license_info
      @@data ||= {}
      expiry = nil
      if @@data[:lt] == 'education' && @@data[:la]
        exp_ts = @@data[:la].to_i + EDU_MONTHS * 30 * 86_400
        expiry = Time.at(exp_ts).strftime('%b %d, %Y')
      end

      masked = nil
      if @@data[:lk]
        parts  = @@data[:lk].split('-')
        masked = "#{parts[0]}-****-****-#{parts[3]}" if parts.length == 4
      end

      {
        state:        @@state,
        type:         @@data[:lt],
        days_left:    trial_days_remaining,
        expiry_date:  expiry,
        permanent:    @@data[:pm] == true,
        masked_key:   masked
      }
    rescue => e
      puts "MLCabinets LicenseManager#license_info: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      { state: @@state, type: nil, days_left: 0, expiry_date: nil, permanent: false, masked_key: nil }
    end

    # Last error string, or nil.
    def last_error
      @@last_error
    end

    # Activate a Gumroad license key on this machine.
    # Returns: { success: true/false, state:, type:, permanent: } or { success: false, message: }
    def activate(key)
      @@data     ||= {}
      @@last_error = nil

      unless key.to_s.strip =~ /\A[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}\z/i
        @@last_error = 'Invalid license key format.'
        return { success: false, message: @@last_error }
      end

      clean_key = key.strip.upcase

      if license_server_enabled?
        server_result = activate_with_license_server(clean_key)
        return server_result
      end

      # Only increment uses on first activation of this key on this machine.
      # If already stored locally (same key), skip increment to avoid
      # burning slots on reloads/restarts.
      already_stored = @@data[:lk] == clean_key
      result = verify_with_gumroad(clean_key, increment_uses: !already_stored)

      if result['offline']
        @@last_error = 'Cannot activate while offline. Please check your internet connection.'
        return { success: false, message: @@last_error }
      end

      unless result['success']
        @@last_error = result['message'] || 'Activation failed.'
        return { success: false, message: @@last_error }
      end

      # Machine limit check (only meaningful when we just incremented)
      unless already_stored
        uses = result['uses'].to_i
        if uses > MAX_MACHINES
          @@last_error = "This license is already activated on #{MAX_MACHINES} machines. " \
                         'Please deactivate on another machine first, or contact support.'
          return { success: false, message: @@last_error }
        end
      end

      purchase = result['purchase'] || {}

      if purchase['refunded'] || purchase['chargebacked'] || purchase['disputed']
        @@last_error = 'This license has been refunded or disputed and cannot be activated.'
        return { success: false, message: @@last_error }
      end

      matched_product_id = result['mlc_product_id'].to_s
      license_type = detect_license_type(purchase, matched_product_id)

      # Parse created_at → unix timestamp
      created_at_ts = nil
      begin
        created_at_ts = Time.parse(purchase['created_at'].to_s).to_i
      rescue
        created_at_ts = Time.now.to_i
      end

      # Subscription lapse detection
      sub_status = if purchase['subscription_ended_at'] ||
                      purchase['subscription_cancelled_at'] ||
                      purchase['subscription_failed_at']
                     'lapsed'
                   end

      # Merge activation data
      @@data = @@data.merge(
        lk:         clean_key,
        lt:         license_type,
        lp:         matched_product_id.empty? ? nil : matched_product_id,
        la:         created_at_ts,
        lv:         Time.now.to_i,
        sub_status: sub_status
      )

      # Check permanent ownership (12 monthly installments)
      if installments_complete? && sub_status.nil?
        @@data[:pm] = true
      end

      write_data(@@data)
      determine_state

      { success: true, state: @@state, type: license_type, permanent: @@data[:pm] == true }
    rescue => e
      @@last_error = e.message
      puts "MLCabinets LicenseManager#activate: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      { success: false, message: 'An unexpected error occurred during activation.' }
    end

    # Remove the license key from this machine.
    def deactivate
      @@data ||= {}
      deactivate_with_license_server if license_server_enabled? && @@data[:lk]
      @@data.merge!(lk: nil, lt: nil, lp: nil, lv: nil, la: nil, pm: false, sub_status: nil)
      write_data(@@data)
      determine_state
    rescue => e
      puts "MLCabinets LicenseManager#deactivate: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
    end

    # Re-verify the stored license key against the licensing authority.
    # Called periodically (e.g. once per session) to keep subscription status current.
    def reverify
      @@data ||= {}
      return if @@data[:pm] == true
      return if @@data[:lk].nil?

      refresh_from_authority!
      determine_state
    rescue => e
      puts "MLCabinets LicenseManager#reverify: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
    end

    # =========================================================================
    # PRIVATE
    # =========================================================================
    private

    # -------------------------------------------------------------------------
    # Machine Fingerprint
    # -------------------------------------------------------------------------

    # Returns a stable SHA256 hex fingerprint for the current machine.
    # Cached for the lifetime of the SketchUp process to avoid drift
    # from command output encoding differences across calls.
    def machine_id
      return @@machine_id if @@machine_id

      raw_uuid = nil

      begin
        if Sketchup.platform == :platform_win
          # Query the same SMBIOS UUID that wmic/PowerShell returned, but via
          # WIN32OLE (in-process COM) so no cmd.exe window flashes on startup.
          require 'win32ole'
          wmi = WIN32OLE.connect('winmgmts:\\\\.\\root\\cimv2')
          wmi.ExecQuery('SELECT UUID FROM Win32_ComputerSystemProduct').each do |item|
            raw_uuid = item.UUID
          end
        else
          output = `system_profiler SPHardwareDataType 2>/dev/null`.to_s
          output.each_line do |line|
            if line =~ /Hardware UUID:\s*(.+)/
              raw_uuid = $1.strip
              break
            end
          end
        end
      rescue
        raw_uuid = nil
      end

      if raw_uuid && !raw_uuid.empty?
        @@machine_id = Digest::SHA256.hexdigest(raw_uuid)
        return @@machine_id
      end

      # Fallback: combine environment identifiers
      parts = [
        ENV.fetch('COMPUTERNAME', ''),
        ENV.fetch('USERNAME', ENV.fetch('USER', '')),
        Socket.gethostname.to_s
      ]
      @@machine_id = Digest::SHA256.hexdigest(parts.join('|'))
      @@machine_id
    rescue
      @@machine_id ||= 'fallback_machine_id_00000000'
    end

    # -------------------------------------------------------------------------
    # Data File Path
    # -------------------------------------------------------------------------

    def data_file_path
      if defined?(Sketchup) && Sketchup.platform == :platform_win
        base = ENV.fetch('LOCALAPPDATA', File.expand_path('~'))
        File.join(base, 'ML_Extensions', '.ml_data')
      else
        File.expand_path('~/Library/Application Support/ML_Extensions/.ml_data')
      end
    rescue
      File.expand_path('~/.ml_data')
    end

    # -------------------------------------------------------------------------
    # Obfuscation Helpers
    # -------------------------------------------------------------------------

    # Returns the machine-id string as a bytes array for use as XOR key.
    def derive_key(mid)
      mid.to_s.bytes
    end

    # XOR-obfuscate a string, then Base64-encode the result.
    def obfuscate(str, key_bytes)
      return '' if key_bytes.empty?
      raw = str.bytes.each_with_index.map { |b, i| b ^ key_bytes[i % key_bytes.length] }
      Base64.strict_encode64(raw.pack('C*'))
    rescue
      ''
    end

    # Base64-decode then reverse the XOR to recover the original string.
    def deobfuscate(encoded, key_bytes)
      return nil if key_bytes.empty?
      raw   = Base64.strict_decode64(encoded).bytes
      plain = raw.each_with_index.map { |b, i| b ^ key_bytes[i % key_bytes.length] }
      plain.pack('C*').force_encoding('UTF-8')
    rescue
      nil
    end

    # -------------------------------------------------------------------------
    # Data Write / Read
    # -------------------------------------------------------------------------

    # Persist the data hash to disk and to SketchUp prefs as a backup.
    def write_data(hash)
      @@data = hash

      key_bytes = derive_key(hash[:mid].to_s)

      # Convert symbol keys to strings for JSON serialisation
      str_hash  = Hash[hash.map { |k, v| [k.to_s, v] }]
      json_str  = str_hash.to_json
      encoded   = obfuscate(json_str, key_bytes)

      begin
        FileUtils.mkdir_p(File.dirname(data_file_path))
        File.write(data_file_path, encoded)
      rescue
        # Primary file write failed — only backup remains
      end

      begin
        Sketchup.write_default('MLCabinets', 'ld', encoded)
      rescue
        # SketchUp prefs write failed — silently continue
      end
    rescue => e
      puts "MLCabinets LicenseManager#write_data: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
    end

    # Read persisted data for the given machine fingerprint.
    # Returns a symbolised-key hash or nil.
    def read_data(mid)
      key_bytes = derive_key(mid.to_s)
      encoded   = nil

      # 1. Try primary file
      begin
        if File.exist?(data_file_path)
          encoded = File.read(data_file_path).strip
        end
      rescue
        encoded = nil
      end

      # 2. Fall back to SketchUp prefs
      if encoded.nil? || encoded.empty?
        begin
          encoded = Sketchup.read_default('MLCabinets', 'ld', nil)
        rescue
          encoded = nil
        end
      end

      return nil if encoded.nil? || encoded.empty?

      raw = deobfuscate(encoded, key_bytes)
      return nil if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      parsed.transform_keys(&:to_sym)
    rescue
      nil
    end

    # Build a fresh first-run data hash.
    def first_run_data(mid)
      {
        mid: mid,
        ts:  Time.now.to_i,
        lk:  nil,
        lt:  nil,
        lp:  nil,
        lv:  nil,
        la:  nil,
        pm:  false
      }
    end

    # -------------------------------------------------------------------------
    # State Machine
    # -------------------------------------------------------------------------

    # Evaluate @@data and assign @@state. Called after every data mutation.
    def determine_state
      @@data ||= {}

      # 1. Permanent ownership (priority override)
      if @@data[:pm] == true
        @@state = :licensed_permanent
        return
      end

      # 2. A license key is stored
      if @@data[:lk]
        case @@data[:lt]
        when 'education'
          if education_expired?
            @@state = :education_expired
          else
            @@state = :education
          end

        when 'full'
          sub_lapsed = @@data[:sub_status] == 'lapsed'

          if sub_lapsed
            @@state = :subscription_lapsed
            @@connectivity_warning = false
          elsif @@data[:lv].nil?
            # Never verified — treat as lapsed to be safe (requires online activation)
            @@state = :subscription_lapsed
            @@connectivity_warning = false
          elsif offline_grace_valid?
            @@state = :licensed
            @@connectivity_warning = false
          else
            # Normal grace window expired. Before demoting, attempt one silent
            # Gumroad refresh per session (option 2). If that also fails and
            # we are still within the extended grace window AND Gumroad has
            # never reported the subscription as lapsed, keep the user
            # licensed with a soft connectivity warning (option 3).
            unless @@grace_retry_attempted
              @@grace_retry_attempted = true
              refresh_from_authority!
              # If the refresh changed license/subscription status, reroute
              # the state machine with fresh data.
              if @@data[:pm] == true || @@data[:lk].nil? ||
                 @@data[:sub_status] == 'lapsed' || offline_grace_valid?
                determine_state
                return
              end
            end

            if @@data[:sub_status] != 'lapsed' && extended_grace_valid?
              @@state = :licensed
              @@connectivity_warning = true
            else
              @@state = :subscription_lapsed
              @@connectivity_warning = false
            end
          end

        else
          # Unknown license type — fall through to trial check
          if trial_active?
            @@state = :trial
          else
            @@state = :trial_expired
          end
        end

        return
      end

      # 3. No license key — trial logic
      if trial_active?
        @@state = :trial
      else
        @@state = :trial_expired
      end
    rescue => e
      puts "MLCabinets LicenseManager#determine_state: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      @@state = :unlicensed
    end

    # -------------------------------------------------------------------------
    # Predicate Helpers
    # -------------------------------------------------------------------------

    def trial_active?
      @@data ||= {}
      Time.now.to_i - @@data[:ts].to_i < TRIAL_DAYS * 86_400
    rescue
      false
    end

    def education_expired?
      @@data ||= {}
      return false unless @@data[:la]
      Time.now.to_i > @@data[:la].to_i + EDU_MONTHS * 30 * 86_400
    rescue
      false
    end

    def offline_grace_valid?
      @@data ||= {}
      return false unless @@data[:lv]
      Time.now.to_i - @@data[:lv].to_i < OFFLINE_GRACE_DAYS * 86_400
    rescue
      false
    end

    # Extended offline grace — keeps a licensed user active with a soft
    # warning when the machine has been offline beyond the normal grace
    # window but no lapse has ever been reported by Gumroad.
    def extended_grace_valid?
      @@data ||= {}
      return false unless @@data[:lv]
      Time.now.to_i - @@data[:lv].to_i < EXTENDED_OFFLINE_GRACE_DAYS * 86_400
    rescue
      false
    end

    def installments_complete?
      @@data ||= {}
      return false unless @@data[:la]
      (Time.now.to_i - @@data[:la].to_i) >= INSTALLMENTS_TO_OWN * 30 * 86_400
    rescue
      false
    end

    # -------------------------------------------------------------------------
    # Gumroad API
    # -------------------------------------------------------------------------

    def configured_product_ids
      ids = []
      ids << EDUCATION_PRODUCT_ID.to_s
      ids << FULL_PRODUCT_ID.to_s
      ids << PRODUCT_ID.to_s
      ids.map(&:strip).reject(&:empty?).uniq
    rescue
      [PRODUCT_ID.to_s]
    end

    def license_type_for_product_id(product_id)
      clean_id = product_id.to_s.strip
      return 'education' if !EDUCATION_PRODUCT_ID.to_s.strip.empty? && clean_id == EDUCATION_PRODUCT_ID.to_s.strip
      return 'full' if !FULL_PRODUCT_ID.to_s.strip.empty? && clean_id == FULL_PRODUCT_ID.to_s.strip
      nil
    rescue
      nil
    end

    def detect_license_type(purchase, product_id = nil)
      product_type = license_type_for_product_id(product_id)
      return product_type if product_type

      license_type = 'full'
      begin
        variants = purchase['variants']
        if variants.is_a?(Hash)
          is_education = variants.values.any? { |value| value.to_s =~ /education/i }
          license_type = 'education' if is_education
        elsif variants.is_a?(String) && variants =~ /education/i
          license_type = 'education'
        end

        if license_type == 'full'
          product_name = purchase['product_name'].to_s
          license_type = 'education' if product_name =~ /education/i
        end
      rescue
        license_type = 'full'
      end
      license_type
    end

    def verify_product_with_gumroad(product_id, key, increment_uses: false)
      uri = URI.parse(VERIFY_URL)

      form_data = {
        'product_id'  => product_id,
        'license_key' => key
      }
      # Only include increment_uses_count when we actually want to increment.
      # Omitting the parameter ensures Gumroad does NOT bump the uses counter.
      form_data['increment_uses_count'] = 'true' if increment_uses

      params = URI.encode_www_form(form_data)

      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.read_timeout = 10
        http.open_timeout = 5
        request           = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request.body      = params
        response          = http.request(request)
      end

      body = JSON.parse(response.body.to_s)

      unless response.is_a?(Net::HTTPSuccess)
        return {
          'success' => false,
          'message' => body['message'] || "HTTP #{response.code}: License verification failed."
        }
      end

      unless body['success']
        return {
          'success' => false,
          'message' => body['message'] || 'Invalid license key.'
        }
      end

      body['mlc_product_id'] = product_id if body.is_a?(Hash) && body['success']
      body
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
           SocketError, OpenSSL::SSL::SSLError, StandardError
      { 'offline' => true }
    end

    # POST to Gumroad verify endpoint. Returns a parsed hash.
    # On network error returns { 'offline' => true }.
    def verify_with_gumroad(key, increment_uses: false, product_id: nil)
      candidate_ids = product_id.to_s.strip.empty? ? configured_product_ids : [product_id.to_s.strip]

      if increment_uses
        discovery = verify_with_gumroad(key, increment_uses: false, product_id: product_id)
        return discovery unless discovery['success']

        matched_product_id = discovery['mlc_product_id'].to_s.strip
        return discovery if matched_product_id.empty?

        return verify_product_with_gumroad(matched_product_id, key, increment_uses: true)
      end

      last_failure = nil
      saw_offline = false

      candidate_ids.each do |candidate_id|
        result = verify_product_with_gumroad(candidate_id, key, increment_uses: false)
        if result['offline']
          saw_offline = true
          next
        end
        return result if result['success']
        last_failure = result
      end

      return { 'offline' => true } if saw_offline && last_failure.nil?

      last_failure || { 'success' => false, 'message' => 'Invalid license key.' }
    end

    # Perform a Gumroad verify call for the currently stored license key and
    # apply the result to @@data (in-place). Does NOT call determine_state —
    # callers are responsible for invoking it when they want state recomputed.
    # Safe to call from within determine_state (no recursion).
    #
    # Returns a symbol: :ok, :lapsed, :invalid, :offline, :noop.
    def refresh_from_gumroad!
      @@data ||= {}
      return :noop if @@data[:pm] == true
      return :noop if @@data[:lk].nil?

      result = verify_with_gumroad(@@data[:lk], increment_uses: false, product_id: @@data[:lp])

      if result['offline']
        return :offline
      end

      unless result['success']
        # Key no longer valid on Gumroad — deactivate silently
        @@data.merge!(lk: nil, lt: nil, lp: nil, lv: nil, la: nil, pm: false, sub_status: nil)
        write_data(@@data)
        return :invalid
      end

      purchase = result['purchase'] || {}

      if purchase['refunded'] || purchase['chargebacked'] || purchase['disputed']
        @@data.merge!(lk: nil, lt: nil, lp: nil, lv: nil, la: nil, pm: false, sub_status: nil)
        write_data(@@data)
        return :invalid
      end

      lapsed = purchase['subscription_ended_at'] ||
               purchase['subscription_cancelled_at'] ||
               purchase['subscription_failed_at']

      @@data[:sub_status] = lapsed ? 'lapsed' : nil
      @@data[:lv]         = Time.now.to_i
      @@data[:lp]         = result['mlc_product_id'].to_s unless result['mlc_product_id'].to_s.empty?
      @@data[:lt]         = detect_license_type(purchase, @@data[:lp])
      @@data[:pm]         = true if installments_complete?

      write_data(@@data)
      lapsed ? :lapsed : :ok
    rescue => e
      puts "MLCabinets LicenseManager#refresh_from_gumroad!: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      :offline
    end

    def refresh_from_authority!
      if license_server_enabled?
        result = refresh_from_license_server!
        return result unless result == :offline
      end

      refresh_from_gumroad!
    rescue => e
      puts "MLCabinets LicenseManager#refresh_from_authority!: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      :offline
    end

    # -------------------------------------------------------------------------
    # Optional ML Extensions Activation Server
    # -------------------------------------------------------------------------

    def license_server_enabled?
      !LICENSE_SERVER_URL.to_s.strip.empty?
    rescue
      false
    end

    def activate_with_license_server(key)
      result = post_license_server('/activate', license_server_payload(key))
      if result.nil? || result['offline']
        @@last_error = 'Cannot reach the ML Cabinets license server. Please check your internet connection and try again.'
        return { success: false, message: @@last_error }
      end

      unless result['success']
        @@last_error = result['message'] || 'Activation failed.'
        return { success: false, message: @@last_error }
      end

      license_type = result['type'].to_s.empty? ? 'full' : result['type'].to_s
      @@data = @@data.merge(
        lk:         key,
        lt:         license_type,
        lp:         'license_server',
        la:         Time.now.to_i,
        lv:         Time.now.to_i,
        pm:         result['permanent'] == true,
        sub_status: nil,
        ot:         result['offline_token']
      )

      write_data(@@data)
      determine_state
      { success: true, state: @@state, type: license_type, permanent: @@data[:pm] == true }
    rescue => e
      puts "MLCabinets LicenseManager#activate_with_license_server: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      nil
    end

    def deactivate_with_license_server
      post_license_server('/deactivate', license_server_payload(@@data[:lk]))
    rescue => e
      puts "MLCabinets LicenseManager#deactivate_with_license_server: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      nil
    end

    def refresh_from_license_server!
      @@data ||= {}
      return :noop if @@data[:pm] == true
      return :noop if @@data[:lk].nil?

      result = post_license_server('/verify', license_server_payload(@@data[:lk]))
      return :offline if result.nil? || result['offline']

      if result['success']
        apply_license_server_result(result)
        return :ok
      end

      if result['code'].to_s == 'not_activated'
        activation = post_license_server('/activate', license_server_payload(@@data[:lk]))
        return :offline if activation.nil? || activation['offline']
        if activation['success']
          apply_license_server_result(activation)
          return :ok
        end
        result = activation
      end

      code = result['code'].to_s
      if code == 'subscription_lapsed'
        @@data[:lt] = 'full'
        @@data[:sub_status] = 'lapsed'
        @@data[:lv] = Time.now.to_i
        write_data(@@data)
        return :lapsed
      end

      if code == 'education_expired'
        @@data[:lt] = 'education'
        @@data[:la] = 0
        @@data[:lv] = Time.now.to_i
        write_data(@@data)
        return :lapsed
      end

      if code == 'activation_limit_reached'
        @@last_error = result['message'] || "This license is already activated on #{MAX_MACHINES} machines."
        @@data[:sub_status] = 'lapsed'
        @@data[:lv] = Time.now.to_i
        write_data(@@data)
        return :lapsed
      end

      @@data.merge!(lk: nil, lt: nil, lp: nil, lv: nil, la: nil, pm: false, sub_status: nil, ot: nil)
      write_data(@@data)
      :invalid
    rescue => e
      puts "MLCabinets LicenseManager#refresh_from_license_server!: #{e.message}" if defined?(MLCabinets::DEBUG) && MLCabinets::DEBUG
      :offline
    end

    def apply_license_server_result(result)
      license_type = result['type'].to_s.empty? ? 'full' : result['type'].to_s
      @@data[:lt] = license_type
      @@data[:lp] = 'license_server'
      @@data[:lv] = Time.now.to_i
      @@data[:la] ||= Time.now.to_i
      @@data[:pm] = result['permanent'] == true
      @@data[:sub_status] = nil
      @@data[:ot] = result['offline_token'] if result['offline_token']
      write_data(@@data)
    end

    def license_server_payload(key)
      {
        license_key:      key,
        machine_id:       machine_id,
        platform:         Sketchup.platform == :platform_win ? 'windows' : 'mac',
        app_version:      defined?(MLCabinets::VERSION) ? MLCabinets::VERSION.to_s : '',
        sketchup_version: defined?(Sketchup) ? Sketchup.version.to_s : ''
      }
    end

    def post_license_server(path, payload)
      base = LICENSE_SERVER_URL.to_s.strip.sub(%r{/+\z}, '')
      uri = URI.parse(base + path)

      response = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.read_timeout = 10
        http.open_timeout = 5
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request.body = payload.to_json
        response = http.request(request)
      end

      JSON.parse(response.body.to_s)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
           SocketError, OpenSSL::SSL::SSLError, StandardError
      { 'offline' => true }
    end

    # Declare private methods (required with `extend self`)
    private :machine_id
    private :data_file_path
    private :derive_key
    private :obfuscate
    private :deobfuscate
    private :write_data
    private :read_data
    private :first_run_data
    private :determine_state
    private :trial_active?
    private :education_expired?
    private :offline_grace_valid?
    private :extended_grace_valid?
    private :installments_complete?
    private :configured_product_ids
    private :license_type_for_product_id
    private :detect_license_type
    private :verify_product_with_gumroad
    private :verify_with_gumroad
    private :refresh_from_gumroad!
    private :refresh_from_authority!
    private :license_server_enabled?
    private :activate_with_license_server
    private :deactivate_with_license_server
    private :refresh_from_license_server!
    private :apply_license_server_result
    private :license_server_payload
    private :post_license_server

  end # module LicenseManager
end # module MLCabinets
