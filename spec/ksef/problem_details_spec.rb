# frozen_string_literal: true

# The API serves errors in two envelopes and picks between them by Content-Type
# (docs/REFERENCE.md §5.1). Every fixture below is taken from the `example` block of the
# corresponding schema in the pinned OpenAPI spec.
RSpec.describe Ksef::ProblemDetails do
  describe "application/problem+json — the current shape" do
    context "with a 400 carrying an errors[] catalogue" do
      subject(:problem) { described_class.parse(status: 400, body: body) }

      let(:body) do
        {
          "title" => "Bad Request",
          "status" => 400,
          "instance" => "/v2/sessions/online",
          "detail" => "Żądanie jest nieprawidłowe.",
          "errors" => [
            { "code" => 21_405, "description" => "Błąd walidacji danych wejściowych.",
              "details" => ["Wskazany kod formularza nie jest wspierany."] },
            { "code" => 21_157, "description" => "Nieprawidłowy rozmiar części pakietu.",
              "details" => ["Rozmiar części 1 przekroczył dozwolony rozmiar 100MB."] }
          ],
          "timestamp" => "2025-07-11T12:23:56.0154302+00:00",
          "traceId" => "673843e023c432286660bc0501a3af44"
        }
      end

      it "reads the envelope fields" do
        expect(problem).to have_attributes(
          status: 400,
          title: "Bad Request",
          detail: "Żądanie jest nieprawidłowe.",
          instance: "/v2/sessions/online",
          trace_id: "673843e023c432286660bc0501a3af44"
        )
      end

      it "exposes the first error code" do
        expect(problem.code).to eq(21_405)
      end

      it "keeps every entry, not just the first" do
        expect(problem.entries.map(&:code)).to eq([21_405, 21_157])
      end

      it "flattens details across all entries" do
        expect(problem.details).to eq([
                                        "Wskazany kod formularza nie jest wspierany.",
                                        "Rozmiar części 1 przekroczył dozwolony rozmiar 100MB."
                                      ])
      end

      it "retains the raw body" do
        expect(problem.raw).to eq(body)
      end

      it "summarises with the code and the details" do
        expect(problem.summary).to start_with("[21405] Żądanie jest nieprawidłowe.")
      end
    end

    context "with a 403 carrying a structured reason" do
      subject(:problem) { described_class.parse(status: 403, body: body) }

      let(:body) do
        {
          "title" => "Forbidden", "status" => 403,
          "detail" => "Brak wymaganych uprawnień do wykonania operacji w bieżącym kontekście.",
          "reasonCode" => "missing-permissions",
          "security" => {
            "requiredAnyOfPermissions" => %w[InvoiceRead InvoiceWrite],
            "presentPermissions" => ["CredentialsRead"]
          },
          "traceId" => "673843e023c432286660bc0501a3af44",
          "timestamp" => "2025-07-11T12:23:56.0154302+00:00"
        }
      end

      it "extracts the reason code" do
        expect(problem.reason_code).to eq("missing-permissions")
      end

      it "keeps the reason-dependent security payload" do
        expect(problem.security["requiredAnyOfPermissions"]).to eq(%w[InvoiceRead InvoiceWrite])
      end
    end

    context "with a 429" do
      subject(:problem) { described_class.parse(status: 429, body: body) }

      let(:body) do
        {
          "title" => "Too Many Requests", "status" => 429, "instance" => "/v2/auth/challenge",
          "detail" => "Przekroczono limit 20 żądań na minutę. Spróbuj ponownie po 30 sekundach.",
          "timestamp" => "2025-07-11T12:23:56.0154302+00:00", "traceId" => "673843e0"
        }
      end

      it "reads the detail" do
        expect(problem.detail).to include("Przekroczono limit 20 żądań na minutę")
      end

      it "has no error code, because the shape carries none" do
        expect(problem.code).to be_nil
      end
    end
  end

  describe "application/json — the deprecated shapes, still live in the wild" do
    context "with an ExceptionResponse" do
      subject(:problem) { described_class.parse(status: 400, body: body) }

      let(:body) do
        {
          "exception" => {
            "exceptionDetailList" => [
              { "exceptionCode" => 12_345, "exceptionDescription" => "Opis błędu.",
                "details" => ["Opcjonalne dodatkowe szczegóły błędu."] }
            ],
            "referenceNumber" => "a1b2c3d4-e5f6-4789-ab12-cd34ef567890",
            "serviceCode" => "00-c02cc3747020c605be02159bf3324f0e-eee7647dc67aa74a-00",
            "serviceCtx" => "srvABCDA", "serviceName" => "Undefined",
            "timestamp" => "2025-10-11T12:23:56.0154302"
          }
        }
      end

      it "normalises the nested code onto #code" do
        expect(problem.code).to eq(12_345)
      end

      it "normalises the nested description onto #detail" do
        expect(problem.detail).to eq("Opis błędu.")
      end

      it "falls back to referenceNumber for correlation, since there is no traceId" do
        expect(problem.trace_id).to eq("a1b2c3d4-e5f6-4789-ab12-cd34ef567890")
      end

      it "keeps the details" do
        expect(problem.details).to eq(["Opcjonalne dodatkowe szczegóły błędu."])
      end
    end

    context "with a TooManyRequestsResponse, where `status` is an object not an integer" do
      subject(:problem) { described_class.parse(status: 429, body: body) }

      let(:body) do
        {
          "status" => {
            "code" => 429, "description" => "Too Many Requests",
            "details" => ["Przekroczono limit 20 żądań na minutę. Spróbuj ponownie po 30 sekundach."]
          }
        }
      end

      it "does not mistake the nested object for the problem+json shape" do
        expect(problem.status).to eq(429)
        expect(problem.title).to eq("Too Many Requests")
      end

      it "lifts the details" do
        expect(problem.detail).to include("Przekroczono limit 20 żądań")
      end
    end
  end

  describe "bodies that are neither" do
    it "degrades gracefully for an HTML block page from the WAF" do
      html = "<html><body>Request blocked</body></html>"
      problem = described_class.parse(status: 403, body: html)

      expect(problem.status).to eq(403)
      expect(problem.raw).to eq(html)
      expect(problem.entries).to be_empty
      expect(problem.summary).to eq("HTTP 403")
    end

    it "degrades for a nil body" do
      expect(described_class.parse(status: 500, body: nil).summary).to eq("HTTP 500")
    end

    it "degrades for a JSON array" do
      expect(described_class.parse(status: 400, body: [1, 2]).raw).to eq([1, 2])
    end
  end
end
