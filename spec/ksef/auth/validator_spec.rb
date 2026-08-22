# frozen_string_literal: true

require "nokogiri"

RSpec.describe Ksef::Auth::Validator do
  def request(**overrides)
    Ksef::Auth::TokenRequest.new(
      challenge: "20250604-CR-461EA5B000-537A6BA15D-D7", context_type: :nip, context_value: "5265877635", **overrides
    ).to_xml
  end

  let(:valid_xml) { request }

  # Well-formed but for a NIP that breaks the schema's structural pattern: the first digit
  # must be non-zero.
  let(:invalid_xml) { valid_xml.sub("5265877635", "0000000000") }

  describe "accepting documents" do
    it "validates a 2.0 document, which is the default and what the API expects" do
      expect(described_class.valid?(valid_xml)).to be(true)
    end

    it "validates a 2.1 document too, against the same rules" do
      expect(described_class.valid?(request(schema_version: "2.1"))).to be(true)
    end

    it "accepts an already-parsed Document as well as a String" do
      expect(described_class.valid?(Nokogiri::XML(valid_xml))).to be(true)
    end
  end

  describe "reporting problems" do
    it "returns messages rather than raising, for callers that want to inspect them" do
      expect(described_class.errors_for(invalid_xml)).to include(/Nip/)
    end

    it "returns nothing for a valid document" do
      expect(described_class.errors_for(valid_xml)).to be_empty
    end

    it "returns true from validate! on success" do
      expect(described_class.validate!(valid_xml)).to be(true)
    end

    it "raises with every violation listed" do
      expect { described_class.validate!(invalid_xml) }
        .to raise_error(Ksef::ValidationError, /AuthTokenRequest is not schema-valid/)
    end

    it "appends a caller-supplied advisory" do
      expect { described_class.validate!(invalid_xml, advisory: "\nupstream is at fault") }
        .to raise_error(Ksef::ValidationError, /upstream is at fault\z/)
    end
  end

  # docs/REFERENCE.md §14.4. Retargeting v2.1's rules is what makes validating a 2.0
  # document possible at all, so these are the load-bearing assertions.
  describe "schema selection" do
    it "derives the rules from v2.1's file, the only one that compiles" do
      expect(described_class::SOURCE).to end_with("schemat_auth_v2-1.xsd")
    end

    it "memoises one compiled schema per namespace" do
      first = described_class.schema_for(Ksef::Auth::NAMESPACES.fetch("2.0"))

      expect(described_class.schema_for(Ksef::Auth::NAMESPACES.fetch("2.0"))).to be(first)
    end

    it "compiles a distinct schema per namespace, not one shared retargeted copy" do
      v20 = described_class.schema_for(Ksef::Auth::NAMESPACES.fetch("2.0"))

      expect(described_class.schema_for(Ksef::Auth::NAMESPACES.fetch("2.1"))).not_to be(v20)
    end

    # Otherwise a typo'd namespace would be retargeted to itself and validate happily,
    # which is worse than a clear failure.
    it "refuses a namespace that is not a known schema version" do
      stranger = valid_xml.sub(Ksef::Auth::NAMESPACES.fetch("2.0"), "http://example.test/auth/9.9")

      expect { described_class.validate!(stranger) }
        .to raise_error(Ksef::ValidationError, %r{namespace "http://example\.test/auth/9\.9".*not a known}m)
    end

    it "refuses a document with no namespace at all" do
      expect { described_class.validate!("<AuthTokenRequest/>") }
        .to raise_error(Ksef::ValidationError, /declares namespace nil/)
    end

    it "still discriminates after retargeting, rather than passing everything" do
      expect(described_class.valid?(invalid_xml)).to be(false)
    end

    it "confirms v2.0's own file really does fail to compile, so retargeting is necessary" do
      legacy = File.join(described_class::SCHEMA_DIR, "schemat_auth_v2-0.xsd")

      expect { Nokogiri::XML::Schema(File.read(legacy, encoding: "UTF-8")) }
        .to raise_error(Nokogiri::XML::SyntaxError, /not a valid regular expression/)
    end
  end
end
