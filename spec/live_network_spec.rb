# frozen_string_literal: true

# The seam the nightly runs through, tested offline.
#
# Every one of these drives the exact call `Net::HTTP#request` makes under WebMock, against
# the exact URL the nightly's first example requests — so the question asked here is the
# question that failed there, minus the socket and the credential.
RSpec.describe LiveNetwork do
  # `POST /auth/challenge`, the first request every live flow makes.
  let(:challenge) { "https://api-test.ksef.mf.gov.pl/v2/auth/challenge" }

  # These examples move global state on purpose. Restore it however the example ended,
  # including the ones that never opened the seam — `close!` is idempotent.
  after { described_class.close! }

  # The negative control, and the reason the rest of this file means anything: if the suite's
  # ordinary state did *not* intercept, `.open!` could be a no-op and every example below
  # would still pass. It is also the state the nightly was actually running in.
  it "is intercepted by the recorded tier in the state an ordinary spec runs in" do
    expect { described_class.handler_for(:post, challenge) }
      .to raise_error(VCR::Errors::UnhandledHTTPRequestError)
  end

  describe ".open!" do
    before { described_class.open! }

    it "leaves nothing at all handling the request, so it reaches the socket" do
      expect(described_class.handler_for(:post, challenge)).to be_nil
    end

    it "turns VCR off, which is what stops its global WebMock stub matching" do
      expect(VCR).not_to be_turned_on
    end

    it "allows a real connection" do
      expect(WebMock::Config.instance.allow_net_connect).to be(true)
    end
  end

  describe ".close!" do
    before do
      described_class.open!
      described_class.close!
    end

    it "restores the interception, so the next example cannot reach KSeF" do
      expect { described_class.handler_for(:post, challenge) }
        .to raise_error(VCR::Errors::UnhandledHTTPRequestError)
    end

    it "disallows a real connection again" do
      expect(WebMock::Config.instance.allow_net_connect).to be(false)
    end
  end
end
