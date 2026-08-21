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

  it "lists every artifact it should" do
    expect(manifest.map(&:last)).to contain_exactly(
      "lib/ksef/fa3/schema/schemat_FA(3)_v1-0E.xsd",
      "lib/ksef/fa3/schema/bazowe/ElementarneTypyDanych_v10-0E.xsd",
      "lib/ksef/fa3/schema/bazowe/KodyKrajow_v10-0E.xsd",
      "lib/ksef/fa3/schema/bazowe/StrukturyDanych_v10-0E.xsd",
      "spec/fixtures/openapi/open-api.json"
    )
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
end
