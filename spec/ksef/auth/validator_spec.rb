# frozen_string_literal: true

require "nokogiri"

RSpec.describe Ksef::Auth::Validator do
  let(:valid_xml) do
    Ksef::Auth::TokenRequest.new(
      challenge: "20250604-CR-461EA5B000-537A6BA15D-D7", context_type: :nip, context_value: "5265877635"
    ).to_xml
  end

  # An otherwise well-formed document whose NIP breaks the schema's structural pattern
  # (first digit must be non-zero).
  let(:invalid_xml) { valid_xml.sub("5265877635", "0000000000") }

  it "accepts a valid document given as a String" do
    expect(described_class.valid?(valid_xml)).to be(true)
  end

  it "accepts a valid document given as a parsed Document" do
    expect(described_class.valid?(Nokogiri::XML(valid_xml))).to be(true)
  end

  it "returns messages rather than raising, for callers that want to inspect them" do
    expect(described_class.errors_for(invalid_xml)).to include(/Nip/)
  end

  it "returns no messages for a valid document" do
    expect(described_class.errors_for(valid_xml)).to be_empty
  end

  it "returns true from validate! on success" do
    expect(described_class.validate!(valid_xml)).to be(true)
  end

  it "raises with every violation listed" do
    expect { described_class.validate!(invalid_xml) }
      .to raise_error(Ksef::ValidationError, /does not conform to schema v2\.1/)
  end

  it "appends a caller-supplied advisory" do
    expect { described_class.validate!(invalid_xml, advisory: "\nupstream is at fault") }
      .to raise_error(Ksef::ValidationError, /upstream is at fault\z/)
  end

  it "compiles the schema once and reuses it" do
    first = described_class.schema

    expect(described_class.schema).to be(first)
  end

  # docs/REFERENCE.md §14.4. v2.0 stays pinned for the record, but nothing may load it:
  # libxml2 cannot compile it at all, so a caller reaching for it gets a confusing
  # SyntaxError rather than a validation result.
  it "uses v2.1, the only version that compiles" do
    expect(described_class::SCHEMA).to end_with("schemat_auth_v2-1.xsd")
  end

  it "confirms v2.0 really does fail to compile, so the choice above is not arbitrary" do
    legacy = File.join(described_class::SCHEMA_DIR, "schemat_auth_v2-0.xsd")

    expect { Nokogiri::XML::Schema(File.read(legacy, encoding: "UTF-8")) }
      .to raise_error(Nokogiri::XML::SyntaxError, /not a valid regular expression/)
  end
end
