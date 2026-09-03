# frozen_string_literal: true

# The seam a live integration spec opens to reach KSeF, and closes again afterwards
# (DESIGN.md §4.5, §9.1).
#
# ## Why `WebMock.allow_net_connect!` stopped being enough on 2026-08-26
#
# It was enough for as long as WebMock was the only thing hooking `Net::HTTP`. The recorded
# tier's `config.hook_into :webmock` changed that, and the change is not visible at the call
# site: VCR installs a **global** WebMock stub — `WebMock.globally_stub_request` — and
# `StubRegistry#response_for_request` consults it *before* WebMock ever asks whether a real
# connection is allowed. With no cassette in use and `record: :none`, VCR's handler reaches
# `on_unhandled_request` and raises. So every request a live spec made was refused by the
# recorded tier rather than sent.
#
# VCR also aliases `WebMock.net_connect_allowed?` to answer `true` whenever it is turned on, so
# the flag the old hook set was not even being read.
#
# The nightly went green -> 27 examples, 27 failures, one error class, and stayed there for six
# nights. Nothing else could have caught it: the live tier is the only tier that opens this
# seam, and neither PR CI nor a local `rake` runs it.
#
# Turning VCR off for the example's duration puts the decision back where the tier boundary
# assumes it is. `VCR.real_http_connections_allowed?` answers `!turned_on?` once no cassette is
# in use, so the handler classifies the request `:recordable` and returns nil, the global stub
# therefore does not match, and the un-aliased `net_connect_allowed?` consults the flag below.
module LiveNetwork
  # Opens the seam. Both halves are needed; neither implies the other.
  def self.open!
    WebMock.allow_net_connect!
    VCR.turn_off!
  end

  # Closes it. `turn_off!` refuses while a cassette is in use, so a spec that is somehow both
  # live and recorded fails loudly rather than recording over a cassette.
  def self.close!
    VCR.turn_on!
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  # What WebMock finds handling a request to `url` right now: nil when nothing does and it
  # would go to the socket, a response when a stub answers it — and a raise from VCR when the
  # recorded tier is intercepting, which is the state this seam exists to leave.
  #
  # This is the exact call `Net::HTTP#request` makes under WebMock, so a spec asking it asks
  # the question the nightly asked, without a socket and without a credential.
  def self.handler_for(method, url)
    WebMock::StubRegistry.instance.response_for_request(WebMock::RequestSignature.new(method, url))
  end
end
