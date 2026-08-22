# frozen_string_literal: true

require "nokogiri"

RSpec.describe Ksef::Auth::TokenRequest do
  # From upstream's own worked example, and long enough that a typo would fail the
  # 36-character length facet rather than passing quietly.
  let(:challenge) { "20250604-CR-461EA5B000-537A6BA15D-D7" }

  def request(challenge: self.challenge, context_type: :nip, context_value: "5265877635", **rest)
    described_class.new(
      challenge: challenge, context_type: context_type, context_value: context_value, **rest
    )
  end

  def parsed(xml) = Nokogiri::XML(xml, &:noblanks)

  describe "document structure" do
    it "is schema-valid for a NIP context" do
      expect(request.validate!).to be(true)
    end

    it "emits the three mandatory children in schema order" do
      names = parsed(request.to_xml).root.element_children.map(&:name)

      expect(names).to eq(%w[Challenge ContextIdentifier SubjectIdentifierType])
    end

    it "puts every element in the v2.1 namespace via a default declaration" do
      namespaces = parsed(request.to_xml).xpath("//*").map { |n| n.namespace&.href }.uniq

      expect(namespaces).to eq([described_class::NAMESPACE])
      expect(parsed(request.to_xml).root.namespace.prefix).to be_nil
    end

    it "declares UTF-8" do
      expect(request.to_xml).to start_with(%(<?xml version="1.0" encoding="UTF-8"?>))
    end

    it "defaults the subject identifier type to certificateSubject" do
      expect(request.subject_identifier_type).to eq("certificateSubject")
    end

    it "is frozen, so a request cannot be mutated after its challenge is validated" do
      expect(request).to be_frozen
    end
  end

  # Ties the implementation to a pinned artifact rather than to my reading of it: upstream
  # ships this exact document as its example, and it is in docs/artifacts.sha256.
  describe "against upstream's pinned example" do
    let(:upstream) do
      markdown = File.read(
        File.expand_path("../../../docs/upstream/auth/context-identifier-nip.md", __dir__), encoding: "UTF-8"
      )
      markdown[/```xml\n(.*?)```/m, 1]
    end

    it "extracts an example to compare against" do
      expect(upstream).to include("AuthTokenRequest", "5265877635")
    end

    it "generates a canonically identical document" do
      # The example declares the 2.0 namespace; ours targets 2.1, which is the only
      # difference that should remain after canonicalisation.
      theirs = parsed(upstream.sub("/auth/token/2.0", "/auth/token/2.1")).canonicalize
      expect(parsed(request.to_xml).canonicalize).to eq(theirs)
    end
  end

  describe "context identifiers" do
    it "wraps the identifier in the element the schema names" do
      xml = parsed(request(context_type: :internal_id, context_value: "5265877635-12345").to_xml)

      expect(xml.at_xpath("//*[local-name()='InternalId']").text).to eq("5265877635-12345")
    end

    it "accepts an internal identifier" do
      expect(request(context_type: :internal_id, context_value: "5265877635-12345").validate!).to be(true)
    end

    it "rejects an unknown context type" do
      expect { request(context_type: :regon) }
        .to raise_error(Ksef::ValidationError, /Unknown context type :regon/)
    end

    # docs/REFERENCE.md §14.4: these two patterns are defective upstream, so a local
    # failure says nothing about the caller's data. The natural value is still emitted.
    %i[nip_vat_ue peppol_id].each do |type|
      it "emits #{type} verbatim but reports it as not locally validatable" do
        subject_request = request(context_type: type, context_value: "PPL123456")

        expect(subject_request.validatable?).to be(false)
        expect(subject_request.valid?).to be(false)
        expect(subject_request.to_xml).to include("PPL123456")
      end

      it "explains that a #{type} failure may be upstream's fault, not the caller's" do
        expect { request(context_type: type, context_value: "PPL123456").validate! }
          .to raise_error(Ksef::ValidationError, %r{defective upstream \(docs/REFERENCE\.md §14\.4\)})
      end
    end

    it "treats nip and internal_id as genuinely validatable" do
      expect(request.validatable?).to be(true)
    end
  end

  describe "challenge validation" do
    it "accepts the documented format" do
      expect(request.challenge).to eq(challenge)
    end

    # Caught locally because a signature is expensive and a stale challenge is the most
    # likely reason for the whole flow to fail.
    [
      ["lowercase hex", "20250604-CR-461ea5b000-537A6BA15D-D7"],
      ["the wrong kind tag", "20250604-XX-461EA5B000-537A6BA15D-D7"],
      ["a truncated value", "20250604-CR-461EA5B000"],
      ["trailing whitespace", "20250604-CR-461EA5B000-537A6BA15D-D7 "]
    ].each do |description, value|
      it "rejects #{description}" do
        expect { request(challenge: value) }.to raise_error(Ksef::ValidationError, /Challenge .* is malformed/)
      end
    end

    it "rejects a non-String without raising NoMethodError" do
      expect { request(challenge: nil) }.to raise_error(Ksef::ValidationError, /malformed/)
    end
  end

  describe "subject identifier type" do
    it "accepts certificateFingerprint" do
      expect(request(subject_identifier_type: "certificateFingerprint").validate!).to be(true)
    end

    it "rejects anything else, listing what is permitted" do
      expect { request(subject_identifier_type: "pesel") }
        .to raise_error(Ksef::ValidationError, /Unknown subject identifier type "pesel".*certificateSubject/m)
    end
  end

  describe "authorization policy" do
    let(:policy) do
      { masks: %w[192.168.1.0/24], addresses: %w[192.168.0.1 10.0.0.7], ranges: ["222.111.0.1-222.111.0.255"] }
    end

    it "is schema-valid with all three list kinds" do
      expect(request(allowed_ips: policy).validate!).to be(true)
    end

    # The input Hash deliberately lists masks first; the schema requires address, range,
    # mask, and getting that wrong would be rejected by KSeF rather than caught here.
    it "emits the lists in schema order, not the caller's order" do
      names = parsed(request(allowed_ips: policy).to_xml)
              .xpath("//*[local-name()='AllowedIps']/*").map(&:name)

      expect(names).to eq(%w[Ip4Address Ip4Address Ip4Range Ip4Mask])
    end

    it "is omitted entirely when not asked for" do
      expect(request.to_xml).not_to include("AuthorizationPolicy")
    end

    it "rejects an unknown key" do
      expect { request(allowed_ips: { ipv6: ["::1"] }) }
        .to raise_error(Ksef::ValidationError, /Unknown allowed_ips key\(s\) :ipv6/)
    end

    # AllowedIps is mandatory inside AuthorizationPolicy, so an empty policy would be
    # schema-invalid. Better to say so than to emit it.
    it "rejects a policy that lists nothing" do
      expect { request(allowed_ips: { addresses: [] }) }
        .to raise_error(Ksef::ValidationError, /lists no addresses/)
    end

    it "rejects more than the ten entries the schema permits" do
      expect { request(allowed_ips: { addresses: Array.new(11) { |i| "10.0.0.#{i}" } }) }
        .to raise_error(Ksef::ValidationError, /has 11 entries; the schema permits 10/)
    end

    it "accepts exactly ten" do
      expect(request(allowed_ips: { addresses: Array.new(10) { |i| "10.0.0.#{i}" } }).validate!).to be(true)
    end
  end
end
