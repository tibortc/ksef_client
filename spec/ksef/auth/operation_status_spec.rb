# frozen_string_literal: true

RSpec.describe Ksef::Auth::OperationStatus do
  def status(code) = described_class.from({ "status" => { "code" => code } })

  it "forwards retryability to the status catalogue" do
    expect(status(Ksef::Auth::Status::CANCELLED).retryable?).to be(true)
    expect(status(Ksef::Auth::Status::NO_PERMISSIONS).retryable?).to be(false)
  end

  it "exposes the authentication method without shadowing Object#method" do
    parsed = described_class.from({ "authenticationMethod" => "QualifiedSignature", "status" => { "code" => 200 } })

    expect(parsed.authentication_method).to eq("QualifiedSignature")
    expect(parsed.method(:success?)).to be_a(Method)
  end
end
