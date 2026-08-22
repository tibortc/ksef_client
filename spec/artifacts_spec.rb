# frozen_string_literal: true

require "digest"

# The pinned upstream artifacts are the anti-hallucination backstop for this whole gem
# (DESIGN.md §0.2, §2). If one drifts, code generated from it is silently wrong, so the
# digests are asserted on every run rather than only in a rake task.
RSpec.describe "pinned upstream artifacts" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:manifest) do
    File.read(File.join(root, "docs/artifacts.sha256"), encoding: "UTF-8")
        .each_line.reject { |l| l.strip.empty? }
        .map { |l| l.chomp.split("  ", 2) }
  end

  # Derived from the filesystem rather than hardcoded. The risk being guarded against is
  # adding an upstream artifact and forgetting to manifest it — a hardcoded list catches
  # that too, but needs editing every time, and the edit is exactly the step someone
  # skipping the manifest would also skip.
  it "manifests every upstream artifact present on disk" do
    on_disk = [
      Dir[File.join(root, "lib/**/*.xsd")],
      Dir[File.join(root, "docs/upstream/**/*.md")],
      Dir[File.join(root, "spec/fixtures/upo/*.xml")],
      File.join(root, "spec/fixtures/openapi/open-api.json")
    ].flatten.map { |f| f.sub("#{root}/", "") }

    expect(manifest.map(&:last)).to include(*on_disk)
  end

  it "matches every recorded digest" do
    mismatches = manifest.filter_map do |expected, path|
      full = File.join(root, path)
      next "#{path}: MISSING" unless File.exist?(full)

      actual = Digest::SHA256.file(full).hexdigest
      "#{path}: expected #{expected}, got #{actual}" unless actual == expected
    end

    expect(mismatches).to be_empty,
                          "Pinned artifacts drifted from docs/artifacts.sha256. This means upstream " \
                          "changed; re-verify against DESIGN.md §2 and update docs/REFERENCE.md.\n" \
                          "#{mismatches.join("\n")}"
  end

  it "bundles the upstream licence that permits redistributing the schemas" do
    licence = File.read(File.join(root, "lib/ksef/fa3/schema/LICENSE.upstream.txt"), encoding: "UTF-8")
    expect(licence).to include("MIT License", "Ministerstwo Finansów")
  end

  describe "the FA(3) schema header contract" do
    let(:xsd) do
      File.read(File.join(root, "lib/ksef/fa3/schema/schemat_FA(3)_v1-0E.xsd"), encoding: "UTF-8")
    end

    # Recorded in docs/REFERENCE.md §8. Easy to misread — `FA (3)` is the kodSystemowy
    # attribute, while the element's own value is just `FA`.
    it "targets the verified namespace" do
      expect(xsd).to include('targetNamespace="http://crd.gov.pl/wzor/2025/06/25/13775/"')
    end

    it "fixes kodSystemowy to 'FA (3)'" do
      expect(xsd).to include('name="kodSystemowy" type="xsd:string" use="required" fixed="FA (3)"')
    end

    it "fixes wersjaSchemy to '1-0E'" do
      expect(xsd).to include('name="wersjaSchemy" type="xsd:string" use="required" fixed="1-0E"')
    end

    it "qualifies elements, so the serializer must namespace every child" do
      expect(xsd).to include('elementFormDefault="qualified"')
    end
  end

  describe "the AuthTokenRequest schema" do
    let(:xsd) do
      File.read(File.join(root, "lib/ksef/auth/schema/schemat_auth_v2-1.xsd"), encoding: "UTF-8")
    end

    # Recorded in docs/REFERENCE.md §4.1.
    it "targets the verified auth namespace" do
      expect(xsd).to include('targetNamespace="http://ksef.mf.gov.pl/auth/token/2.1"')
    end

    it "declares the AuthTokenRequest root" do
      expect(xsd).to include('<xsd:element name="AuthTokenRequest"')
    end

    it "offers exactly the two documented subject identifier types" do
      expect(xsd.scan(/enumeration value="(certificate\w+)"/).flatten)
        .to contain_exactly("certificateSubject", "certificateFingerprint")
    end
  end

  # Locks in docs/REFERENCE.md §14.3 — upstream's own UPO examples do not validate against
  # upstream's own UPO schema. This matters because it dictates that UPO validation cannot
  # hard-fail on this element: doing so would reject every UPO that TEST issues. Asserting
  # it here means an upstream fix shows up as a red build rather than going unnoticed.
  describe "the UPO schema versus upstream's own examples (REFERENCE.md §14.3)" do
    let(:xsd_source) { File.read(File.join(root, "lib/ksef/upo/schema/upo-v4-3.xsd"), encoding: "UTF-8") }
    let(:examples) { Dir[File.join(root, "spec/fixtures/upo/*.xml")].sort }
    let(:relaxed) { Nokogiri::XML::Schema(xsd_source.sub(/ fixed="Ministerstwo Finansów"/, "")) }

    def errors_for(schema, path)
      schema.validate(Nokogiri::XML(File.read(path, encoding: "UTF-8")))
    end

    it "pins all six worked examples" do
      expect(examples.size).to eq(6)
    end

    it "is self-contained, needing no schemaLocation rewrite unlike FA(3)" do
      expect(xsd_source).not_to include("xsd:import", "xsd:include")
    end

    it "constrains the receiving party to the production name" do
      expect(xsd_source).to include('name="NazwaPodmiotuPrzyjmujacego" fixed="Ministerstwo Finansów"')
    end

    it "rejects every example, because each carries the TEST environment marker" do
      schema = Nokogiri::XML::Schema(xsd_source)

      examples.each do |path|
        messages = errors_for(schema, path).map(&:to_s)
        expect(messages.size).to eq(1), "#{File.basename(path)}: expected exactly one error, got #{messages}"
        expect(messages.first).to include("NazwaPodmiotuPrzyjmujacego", "środowisko testowe (TE)")
      end
    end

    # The important half: nothing else about these documents is wrong, so relaxing that one
    # constraint is a sufficient and narrow fix.
    it "accepts every example once that one constraint is relaxed" do
      examples.each do |path|
        expect(errors_for(relaxed, path)).to be_empty, "#{File.basename(path)} still invalid"
      end
    end
  end
end
