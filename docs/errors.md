# Error handling

## The hierarchy

```
Ksef::Error                        #problem → Ksef::ProblemDetails or nil
├── Ksef::ConfigurationError       raised locally, before any request
├── Ksef::AuthenticationError      challenge / token / JWT problems, and HTTP 401
├── Ksef::ValidationError          raised locally by the FA(3) validator
├── Ksef::CryptoError              no usable published key, or bad key material
├── Ksef::ApiError                 #status #code #details #trace_id #raw
│   ├── Ksef::InvoiceRejectedError schema or business rejection by KSeF
│   ├── Ksef::SessionError         session could not be opened, used or closed
│   ├── Ksef::AuthorizationError   403 — #reason_code, #security
│   ├── Ksef::ResourceGoneError    410
│   ├── Ksef::RateLimitedError     429 — #retry_after
│   └── Ksef::ServerError          5xx
├── Ksef::TimeoutError             open or read timeout
└── Ksef::ConnectionError          connection or TLS failure
```

Everything descends from `StandardError`, so a bare `rescue Ksef::Error` catches all of
it. `#problem` is `nil` for locally raised errors and populated for anything derived from
a response.

`Ksef::CryptoError` is the one branch with no HTTP status behind it. It means either that
no published KSeF certificate is valid for the usage needed, or that key material is the
wrong size. The first is worth acting on: after an emergency key rotation it is transient,
and `Ksef::Crypto::PublicKeys#refresh!` is the remedy (docs/REFERENCE.md §10.2, §10.3).

## Status mapping

| Status | Class | Notes |
|---|---|---|
| 400 | `Ksef::ApiError` | Carries `errors[]`; `#code` is the KSeF error code |
| 401 | `Ksef::AuthenticationError` | Refresh and replay once, for idempotent requests only |
| 403 | `Ksef::AuthorizationError` | Check `#reason_code` before retrying anything |
| 410 | `Ksef::ResourceGoneError` | The resource existed but is gone |
| 429 | `Ksef::RateLimitedError` | Honour `#retry_after` |
| 5xx | `Ksef::ServerError` | Not declared in the contract; body shape unknown |

## The two error envelopes

KSeF serves errors in two shapes and the response `Content-Type` decides which:

- `application/problem+json` — current. Fields: `title`, `status`, `detail`, `instance`,
  `timestamp`, `traceId`, plus `errors[]` on 400 and `reasonCode`/`security` on 403.
- `application/json` — deprecated but still live. `ExceptionResponse` nests under
  `exception.exceptionDetailList[]`; the 429 variant nests under `status.details[]`, where
  `status` is an **object**, not an integer.

`Ksef::ProblemDetails` normalises all of these, so callers only ever see the flat
accessors. A body that is neither — an HTML block page from the WAF in front of the API,
say — degrades to `#raw` with an empty `#entries`.

## `#trace_id`

Every problem+json error carries a `traceId`. Log it. It is what the Ministry's support
process asks for, and it is the only way to correlate a failure with their side. For the
deprecated envelope, `#trace_id` falls back to `referenceNumber`, its closest analogue.

## Rate limiting

```ruby
begin
  client.invoice(ksef_number)
rescue Ksef::RateLimitedError => e
  sleep e.retry_after if e.retry_after
  retry
end
```

`#retry_after` comes from the `Retry-After` header, in seconds, and is present on every
declared 429. It is authoritative: the block period is **dynamic** and lengthens with
repeat breaches, so waiting less than instructed makes the next block longer.

Limits are counted per **(context, client IP)** pair over a **sliding window** — req/s
over the trailing second, req/min over the trailing 60 seconds, req/h over the trailing
60 minutes. Windows do not reset on the minute or hour. All thresholds apply at once and
the first crossed triggers the block.

KSeF records breaches and explicitly treats spreading one context across many IPs as an
abuse pattern that can escalate to protective action. **Never work around a 429 by
rotating connections.** Live budgets are introspectable via `GET /rate-limits`,
`GET /limits/context` and `GET /limits/subject`.

## Retries

`Ksef::RetryPolicy` retries only **idempotent** methods (GET, HEAD), on 429, 5xx, or a
transport failure. Capped exponential backoff: 1s, 2s, 4s … 30s.

**Invoice submission is never auto-retried.** A duplicate invoice in KSeF is a real tax
problem, so a failed POST surfaces to you rather than being replayed. This is deliberate
and applies even to a 429, which the server rejected before processing.

`Retry-After` is honoured **unclamped** — retrying sooner than instructed is worse than
waiting. If the server demands longer than `max_retry_after` (60s by default), the client
declines to retry at all and raises, rather than waiting a period it was not asked to
wait.

## `X-System-Warning`

The API sets this advisory header on successful responses. It is the Ministry's in-band
channel for notices such as forthcoming contract changes. `Ksef::HTTP::SystemWarning`
logs it at warn level when a logger is configured; watch for it in production, since it
is the earliest signal that something upstream is about to change.

## Error code catalogue

400 responses carry `errors[]`, each with a numeric `code`, a `description`, and optional
`details[]`. Codes observed so far:

| Code | Meaning |
|---|---|
| 21405 | Input validation failure (e.g. unsupported form code) |
| 21157 | Invalid package part size |

This catalogue grows as codes are encountered against the live API; the full published
list is still to be mined from the spec and upstream docs (see `docs/REFERENCE.md` §9).

## 403 reason codes

| `reasonCode` | `security` payload |
|---|---|
| `missing-permissions` | `requiredAnyOfPermissions`, `presentPermissions` |
| `ip-not-allowed` | `clientIp` |
| `insufficient-resource-access` | — |
| `auth-method-not-allowed` | `authenticationMethodCategory` |
| `security-service-blocked` | `incidentId`, `clientIp` |
| `context-type-not-allowed` | `contextIdentifierType` |

`ip-not-allowed` is worth calling out: the API pins a session to the IP seen at
authentication, so a client behind a rotating egress address will hit this. Retrying will
not help — re-authenticate from a stable address.
