# frozen_string_literal: true

require "date"
require "openssl"
require "securerandom"

# One-time provisioning of a TEST credential — DESIGN.md §12 item 4, docs/REFERENCE.md §6a.
#
# Invents a checksum-valid NIP and PESEL, registers them through the unauthenticated
# `/testdata/person` endpoint, authenticates with a self-signed certificate, and mints a
# KSeF token. The output is the pair `nightly.yml` reads from repository secrets.
#
# Lives in `tasks/` so it is never packaged, but it is **not** an untested script: every
# method here is exercised against WebMock stubs in `spec/tasks/ksef_bootstrap_spec.rb`. A
# checksum bug would otherwise surface as an opaque rejection from a remote server.
#
# §6a.2 previously recorded that the interim workaround was a one-time mint via the
# official C# client. That is obsolete — this gem can now do it itself.
module KsefBootstrap
  # Only what the integration suite needs. The set is fixed when the token is minted;
  # changing it means minting a new one (`tokeny-ksef.md`).
  DEFAULT_PERMISSIONS = %w[InvoiceRead InvoiceWrite].freeze

  # Checksum-valid Polish identifiers.
  #
  # Both algorithms are confirmed the way §6a.1 confirmed the NIP one — by validating every
  # example the upstream documentation ships, rather than by trusting a recollection of the
  # rules. See the spec.
  module Identifiers
    # `1,3,7,9` repeating across the first ten digits; the eleventh is
    # `(10 - sum % 10) % 10`. Verified against `15062788702`, `30112206276`,
    # `38092277125` and `88102341294` — every PESEL appearing in the upstream docs.
    PESEL_WEIGHTS = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3].freeze

    # A PESEL is **not** eleven arbitrary digits with a check digit: the first six encode a
    # birth date, with the century folded into the month field by these offsets. KSeF
    # enforces this — a checksum-valid PESEL with a nonsense date is rejected with
    # `400 [21405] Invalid PESEL format` (docs/REFERENCE.md §6a.3).
    PESEL_CENTURY_OFFSETS = { 80 => 1800, 0 => 1900, 20 => 2000, 40 => 2100, 60 => 2200 }.freeze

    # Births are drawn from the 1900s, which needs no offset and matches every upstream
    # example. Adults, and comfortably in the past.
    PESEL_BIRTH_YEARS = (1950..1999)

    class << self
      # Digit 1 must be non-zero and digits 2–3 must not both be zero, per the auth
      # schema's own `TNIP` pattern (§4.1) — a checksum-valid NIP can still be rejected on
      # shape alone.
      # The check digit *is* `weighted sum % 11` — not `11 - (sum % 11)`. Confirmed against
      # every NIP in the upstream docs. A value of 10 is unrepresentable, so redraw.
      # Bounded rather than `loop do`: an error in the arithmetic here should fail loudly,
      # not hang.
      def nip(random = Random.new, attempts: 100)
        attempts.times do
          candidate = nip_candidate(random)
          return candidate if candidate && Ksef::FA3::NIP.valid?(candidate)
        end
        raise "Could not generate a checksum-valid NIP in #{attempts} attempts — the algorithm is wrong"
      end

      # Shaped to satisfy the auth schema's `TNIP` pattern as well as the checksum.
      # A check digit of 10 is unrepresentable, so that draw is discarded.
      def nip_candidate(random)
        body = [random.rand(1..9), random.rand(0..9), random.rand(1..9)] + Array.new(6) { random.rand(0..9) }
        check = nip_check_digit(body)
        return nil if check == 10

        (body + [check]).join
      end

      def nip_check_digit(digits)
        Ksef::FA3::NIP::WEIGHTS.each_with_index.sum { |weight, i| weight * digits[i] } % 11
      end

      def pesel(random = Random.new)
        birth = random_birth(random)
        body = format(
          "%<yy>02d%<mm>02d%<dd>02d%<serial>04d",
          yy: birth.year % 100, mm: birth.month, dd: birth.day, serial: random.rand(0..9999)
        ).chars.map(&:to_i)
        (body + [pesel_check_digit(body)]).join
      end

      def random_birth(random)
        year = random.rand(PESEL_BIRTH_YEARS)
        month = random.rand(1..12)
        Date.new(year, month, random.rand(1..Date.new(year, month, -1).day))
      end

      # @return [Date, nil] nil when the first six digits do not encode a real date
      def pesel_birth_date(value)
        parts = pesel_date_parts(value)
        return nil unless parts && Date.valid_date?(*parts)

        Date.new(*parts)
      end

      # @return [Array(Integer, Integer, Integer), nil] year, month, day — nil when the
      #   month field decodes to no known century
      def pesel_date_parts(value)
        month_field = value[2, 2].to_i
        offset = (month_field - 1) / 20 * 20
        century = PESEL_CENTURY_OFFSETS[offset]
        return nil if century.nil?

        [century + value[0, 2].to_i, month_field - offset, value[4, 2].to_i]
      end

      def pesel_check_digit(digits)
        (10 - (PESEL_WEIGHTS.each_with_index.sum { |w, i| w * digits[i] } % 10)) % 10
      end

      # Checks the encoded date as well as the checksum. Checking only the checksum is what
      # let the generator emit `44812176391` (1844) and `98681059372` (year 2298) — both
      # checksum-perfect, both rejected by KSeF.
      def pesel_valid?(value)
        return false unless value.to_s.match?(/\A\d{11}\z/)

        digits = value.to_s.chars.map(&:to_i)
        pesel_check_digit(digits.first(10)) == digits[10] && !pesel_birth_date(value.to_s).nil?
      end
    end
  end

  # A self-signed certificate of the kind TEST accepts (§4.6 — **TEST only**), carrying the
  # PESEL in `serialNumber` as `PNOPL-<pesel>`, one of the two patterns §4.4 records as
  # recognised.
  module Certificate
    class << self
      def personal(pesel:, given_name: "Jan", surname: "Kowalski", validity: 86_400)
        key = OpenSSL::PKey::RSA.generate(2048)
        subject = OpenSSL::X509::Name.parse(
          "/C=PL/CN=#{given_name} #{surname}/GN=#{given_name}/SN=#{surname}/serialNumber=PNOPL-#{pesel}"
        )
        [issue(subject, key, validity), key]
      end

      private

      def issue(subject, key, validity)
        OpenSSL::X509::Certificate.new.tap do |cert|
          cert.version = 2
          # Random, so two runs are distinguishable in KSeF's own records.
          cert.serial = OpenSSL::BN.new(SecureRandom.hex(8), 16)
          cert.subject = subject
          cert.issuer = subject
          cert.public_key = key.public_key
          set_validity(cert, validity)
          cert.sign(key, OpenSSL::Digest.new("SHA256"))
        end
      end

      # Valid from a minute ago, so clock skew cannot make it not-yet-valid — the same
      # reasoning as the signer's backdated SigningTime (§4.3).
      def set_validity(cert, validity)
        cert.not_before = Time.now - 60
        cert.not_after = Time.now + validity
      end
    end
  end

  # Drives the whole flow. Every network call goes through the injected connection, so the
  # spec can stub all of them.
  class Runner
    # @param certificate [OpenSSL::X509::Certificate, nil] supply a real qualified
    #   certificate to use it; omitted, a self-signed one is generated, which TEST accepts
    #   and no other environment does (§4.6)
    # @param key [OpenSSL::PKey::RSA, nil] its private key, required with `certificate`
    # @param sleeper [#call] injected so tests need not actually wait
    def initialize(configuration:, io: $stdout, random: Random.new,
                   certificate: nil, key: nil, poll_interval: Ksef::Auth::Client::POLL_INTERVAL,
                   sleeper: nil)
      refuse_unless_test_data(configuration)
      raise ArgumentError, "certificate: and key: must be given together" if certificate.nil? ^ key.nil?

      @configuration = configuration
      @connection = Ksef::HTTP::Connection.build(configuration)
      @auth = Ksef::Auth::Client.new(@connection)
      @io = io
      @random = random
      @certificate = certificate
      @key = key
      @poll_interval = poll_interval
      @sleeper = sleeper
    end

    # @return [Hash] `{nip:, pesel:, token:, reference_number:}`
    def call(nip: nil, pesel: nil, permissions: DEFAULT_PERMISSIONS)
      nip ||= Identifiers.nip(@random)
      pesel ||= Identifiers.pesel(@random)
      say "context NIP #{nip}, PESEL #{pesel}"

      register_person(nip: nip, pesel: pesel)
      access = authenticate(nip: nip, pesel: pesel)
      minted = mint_token(access, permissions)

      { nip: nip, pesel: pesel, token: minted.fetch("token"), reference_number: minted["referenceNumber"] }
    end

    private

    # `/testdata/person` is unauthenticated (§6a.1), which is the only reason this whole
    # chain is not circular: `POST /tokens` needs a session, and a session needs a context
    # that somebody has been granted rights in.
    def register_person(nip:, pesel:)
      @connection.post("testdata/person") do |request|
        request.body = {
          nip: nip, pesel: pesel, isBailiff: false, isDeceased: false,
          description: "ksef_client integration suite"
        }
      end
      say "registered on TEST — Owner permissions granted"
    end

    def authenticate(nip:, pesel:)
      initiated = submit(nip: nip, pesel: pesel)
      say "submitted, reference #{initiated.reference_number} — polling"

      @auth.authenticate!(initiated.reference_number, token: initiated.authentication_token,
                                                      **poll_options) do |status|
        say "  #{status.code} #{status.explain}"
      end
      @auth.redeem(token: initiated.authentication_token).access_token
    end

    # Challenge, build, sign, submit. Split from the polling above so each half stays
    # readable — and because this is the half that can fail on our side.
    def submit(nip:, pesel:)
      certificate, key = signing_material(pesel)
      challenge = @auth.challenge
      say "challenge #{challenge} (expires #{challenge.expires_at})"

      request = Ksef::Auth::TokenRequest.new(
        challenge: challenge.to_s, context_type: :nip, context_value: nip
      )
      @auth.submit_xades(Ksef::Auth::Signer.new(certificate: certificate, key: key).sign(request))
    end

    def signing_material(pesel)
      return [@certificate, @key] if @certificate

      say "generating a self-signed certificate (TEST only)"
      Certificate.personal(pesel: pesel)
    end

    # `sleeper` is omitted rather than passed as nil so {Ksef::Auth::Client} keeps its own
    # default, which is the real `Kernel#sleep`.
    def poll_options
      options = { interval: @poll_interval }
      options[:sleeper] = @sleeper if @sleeper
      options
    end

    def mint_token(access_token, permissions)
      response = @connection.post("tokens") do |request|
        request.headers["Authorization"] = "Bearer #{access_token.token}"
        request.body = { permissions: permissions, description: "ksef_client nightly integration suite" }
      end
      say "token minted with #{permissions.join(", ")}"
      response.body
    end

    # Never PROD, from any script (a hard rule). Checked against the environment's declared
    # capability rather than its name, so a `custom` environment cannot slip past.
    def refuse_unless_test_data(configuration)
      return if configuration.environment.test_data_api?

      raise ArgumentError,
            "Refusing to bootstrap against #{configuration.environment.name}: the /testdata endpoints " \
            "exist on TEST only, and this must never touch DEMO or PROD."
    end

    def say(message) = @io.puts("  #{message}")
  end
end
