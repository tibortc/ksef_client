# frozen_string_literal: true

require "spec_helper"
require "yaml"

# **A workflow step is the least-tested code in this repository, and some of it only runs when
# a mistake is expensive.**
#
# `release.yml`'s announce job had never executed and was broken; `record-cassettes.yml` had
# never succeeded and discarded two recordings that each cost a permanent TEST invoice; and the
# production guard in two workflows compared a literal against a different literal, so it could
# not fire. None of that was reachable from a spec, because nothing read these files.
#
# Both have since run green — `announce` on the `v0.1.0` tag and `record-cassettes` as a dry
# run, both on 2026-09-15 — which is the argument rather than a retirement of it: each was
# repaired against these assertions *before* it next got the chance to fail somewhere
# irreversible.
#
# These do. Every rule here is one the repository already states in prose — CLAUDE.md's hard
# rules, or a decision written in the workflow's own comments — moved somewhere that fails.
RSpec.describe "the GitHub Actions workflows" do
  # Keyed by basename so a failure names the file.
  def workflows
    Dir.glob(File.expand_path("../.github/workflows/*.yml", __dir__))
       .to_h { |path| [File.basename(path), YAML.safe_load_file(path, aliases: true)] }
  end

  # Every step of every job, tagged with where it came from.
  def steps
    workflows.flat_map do |file, workflow|
      workflow.fetch("jobs").flat_map do |job_name, job|
        (job["steps"] || []).each_with_index.map do |step, index|
          { file: file, job: job_name, index: index, step: step,
            where: "#{file} #{job_name}[#{index}] #{step["name"] || step["uses"]}" }
        end
      end
    end
  end

  it "has workflows to check, so this file cannot pass by finding nothing" do
    expect(workflows.keys).to include("nightly.yml", "record-cassettes.yml", "release.yml", "test.yml")
    expect(steps.size).to be > 20
  end

  # CLAUDE.md, hard rule: **never interpolate `${{ }}` into a `run:` script.** GitHub
  # substitutes it textually before the shell parses, so a dispatch input can close the quote
  # and append commands — on workflows that export a live KSeF credential. Values reach the
  # shell through `env:`, where they are data.
  #
  # This was a rule enforced by a comment and by whoever last read the file. One violation had
  # already shipped (`record-cassettes.yml`, 2026-08-26).
  it "never interpolates an expression into a run: script" do
    offenders = steps.select { |s| s[:step]["run"].to_s.include?("${{") }.map { |s| s[:where] }

    expect(offenders).to be_empty,
                         "#{offenders.join("; ")} — pass the value through `env:` and " \
                         "reference \"$VAR\" instead (CLAUDE.md, hard rules)."
  end

  # A moving tag is a supply-chain hole; Dependabot keeps the pins current, which is what makes
  # pinning affordable (`.github/dependabot.yml`).
  it "pins every action to a full commit SHA" do
    unpinned = steps.select { |s| s[:step].key?("uses") }
                    .reject { |s| s[:step]["uses"].match?(/@[0-9a-f]{40}\z/) }
                    .map { |s| s[:where] }

    expect(unpinned).to be_empty
  end

  # DESIGN.md §4.5 and a hard rule: never target production. The runtime guards read this
  # value; this reads it a merge earlier, and covers a credentialed workflow that forgets to
  # carry a guard at all.
  it "sets KSEF_ENV to test wherever it sets it, and nowhere else" do
    assignments = workflows.flat_map do |file, workflow|
      workflow.fetch("jobs").flat_map do |job_name, job|
        scopes = [job["env"]].concat((job["steps"] || []).map { |step| step["env"] })
        scopes.compact.filter_map { |env| ["#{file} #{job_name}", env["KSEF_ENV"]] if env.key?("KSEF_ENV") }
      end
    end

    expect(assignments).not_to be_empty
    expect(assignments.map(&:last).uniq).to eq(["test"])
  end

  # The guard is only a guard if it can fail. Both of these set `KSEF_ENV` in the step's own
  # `env:` and then tested it against `prod` — a literal against a different literal. Reading
  # an inherited job-level value is what makes the comparison mean something, so the absence of
  # a step-level override is the property worth pinning.
  describe "the TEST-only guard on the credentialed workflows" do
    %w[nightly.yml record-cassettes.yml].each do |file|
      it "in #{file}, compares a value it did not just set" do
        job = workflows.fetch(file).fetch("jobs").values.first
        guard = job.fetch("steps").find { |step| step["name"].to_s.include?("Refuse to run") }

        expect(job["env"]).to include("KSEF_ENV" => "test")
        expect(guard).not_to be_nil
        expect(guard["env"].to_h).not_to include("KSEF_ENV")
        expect(guard.fetch("run")).to include("$KSEF_ENV")
      end
    end
  end

  # **A dry run must skip exactly one step.** The point of it is to exercise everything the
  # recording job does *except* the irreversible part, so that the upload — which had never
  # executed before the dry run of 2026-09-15 — could be proven without spending a permanent
  # TEST invoice. A flag that grew to skip the hygiene scan as well would quietly turn the
  # rehearsal into a weaker check than the thing it rehearses.
  #
  # **That dry run proved the success path only.** The condition asserted below exists so a
  # recording survives a *failed replay*, and a green rehearsal cannot reach that branch — so
  # this assertion, not the run history, is still the only thing holding it.
  it "skips only the recording step on a dry run" do
    job = workflows.fetch("record-cassettes.yml").fetch("jobs").fetch("record")
    gated = job.fetch("steps").select { |step| step["if"].to_s.include?("dry_run") }

    expect(gated.map { |step| step["name"] }).to eq(["Record"])
  end

  # Still confirmed, still TEST-only, still not a schedule: a dry run is a mode of this job,
  # not a relaxation of it.
  #
  # **And `dry_run` defaults to true**, so the mode an accidental dispatch gets is the free
  # one. The two ways of forgetting are not symmetric — meaning to rehearse and forgetting the
  # flag cost two permanent TEST invoices, while meaning to record and forgetting to clear it
  # costs a re-dispatch.
  #
  # **No schedule, ever, and here the policy has teeth beyond policy.** `Record` is gated on
  # `${{ !inputs.dry_run }}`, and a `schedule` event carries no `inputs` at all — so
  # `inputs.dry_run` is null, `!null` is true, and Record would *run*. A cron on this workflow
  # would record for real every night. Anyone adding one has to change that condition first.
  it "keeps the dispatch guards regardless of the dry-run flag" do
    # `fetch(true)`, not `fetch("on")`: YAML reads a bare `on` as the boolean, so that is the
    # key Psych hands back for a workflow's trigger block.
    triggers = workflows.fetch("record-cassettes.yml").fetch(true)
    inputs = triggers.fetch("workflow_dispatch").fetch("inputs")

    expect(triggers.keys).to eq(["workflow_dispatch"]) # see above: a cron here would record
    expect(inputs.fetch("confirm").fetch("required")).to be(true)
    expect(inputs.fetch("dry_run").fetch("default")).to be(true)
  end

  # **A nightly can fail by passing, and that failure reaches nobody.** Failure notifications
  # cover a red run; they cannot cover a green one, because it is a success. Two paths produce a
  # green run that verified nothing: `KSEF_INTEGRATION` unset filters the whole tier out (RSpec
  # exits 0 on zero examples), and absent or rotated credentials make `session_flow_spec.rb` and
  # `crypto_spec.rb` skip wholesale (RSpec exits 0 on an all-pending file). The second is the
  # one to expect — a credential lapsing is a matter of time. This is why the example count was
  # read by hand after every run.
  #
  # The guard turns both into a red run, where the existing notifications already work. What is
  # pinned here is the **correspondence**: the step that writes the JSON and the step that reads
  # it must name the same file. Asserting only that both exist is exactly the mistake
  # `docs/field_mapping.md`'s guards made — two ends that each looked right and did not pair.
  it "fails the nightly when it passes without having run anything" do
    job = workflows.fetch("nightly.yml").fetch("jobs").fetch("integration")
    runner = job.fetch("steps").find { |step| step["run"].to_s.include?("rspec --tag integration") }
    guard = job.fetch("steps").find { |step| step["name"].to_s.include?("vacuously green") }

    expect(guard).not_to be_nil
    expect(runner.fetch("run")).to include("--format json", "$RSPEC_JSON")
    expect(guard.fetch("env").fetch("RSPEC_JSON")).to eq(runner.fetch("env").fetch("RSPEC_JSON"))
  end

  # The guard is only a guard if it can fail, and the number it compares against is the whole
  # rule. One legitimate skip exists — the collective UPO page, which KSeF generates
  # asynchronously — so the tolerance is one, and a tolerance wide enough to swallow a whole
  # file's worth of skips would restore the silence it was built to end.
  it "tolerates the one legitimate skip and no more" do
    job = workflows.fetch("nightly.yml").fetch("jobs").fetch("integration")
    guard = job.fetch("steps").find { |step| step["name"].to_s.include?("vacuously green") }

    expect(guard.fetch("env").fetch("MAX_PENDING")).to eq("1")
    expect(guard.fetch("run")).to include("exit 1")
  end

  # **The per-push tier is the only thing that can see a dependency break, and it runs only when
  # someone pushes.** `Gemfile.lock` is gitignored, so every leg resolves fresh — that is what
  # makes this suite a drift detector, and what makes it useless in a quiet week. Twice in one
  # month an upstream release broke `main` with no commit here: `json` 3.0.0, then faraday
  # 2.14.4. The second sat red for five days, under five consecutive *green* nightlies that
  # could not see it, because `nightly.yml` runs only `--tag integration`.
  #
  # Asserted because removing the schedule reopens a hole whose only symptom is silence.
  it "runs the unit tier on a schedule, not only when someone pushes" do
    triggers = workflows.fetch("test.yml").fetch(true)

    expect(triggers.keys).to include("schedule", "push", "pull_request")
    expect(triggers.fetch("schedule").map { |entry| entry.fetch("cron") }).to all(be_a(String))
  end

  # **The coverage gate is what stops this suite passing vacuously, and any selector switches it
  # off.** `spec_helper.rb` skips `minimum_coverage` on a filtered run, so a `--tag`, a path or a
  # `--pattern` on this step would exit 0 having proved nothing. That exact failure already
  # shipped once, through `rake spec`'s own `--pattern` (2026-08-23) — and a scheduled run that
  # nobody watches is where it would hide best.
  it "runs the scheduled suite unfiltered, so the coverage gate stays armed" do
    job = workflows.fetch("test.yml").fetch("jobs").fetch("spec")
    step = job.fetch("steps").find { |s| s["name"] == "Run specs" }

    expect(step.fetch("run").strip).to eq("bundle exec rspec")
  end

  # A scheduled run is not a change, so it must not post a commit status against one.
  it "does not report coverage to Coveralls on a scheduled run" do
    job = workflows.fetch("test.yml").fetch("jobs").fetch("spec")
    step = job.fetch("steps").find { |s| s["uses"].to_s.include?("coverallsapp") }

    expect(step.fetch("if")).to include("github.event_name != 'schedule'")
  end

  # **The run-page summary restates the coverage floors, and it had already gone stale.** The
  # line floor moved 99 -> 100 at the Phase 3 boundary and this copy kept saying 99, so every run
  # page printed a floor the build does not enforce — found 2026-09-21, because the grep that
  # chased the ratchet covered `*.md` and `*.rb` and this one lives in YAML.
  #
  # `spec/spec_helper.rb` is the authority (CLAUDE.md). This reads both and fails when they
  # disagree, which is the check the "five documents kept saying 95" episode should have left
  # behind instead of an instruction to grep.
  it "summarises the same coverage floors the build enforces" do
    step = workflows.fetch("test.yml").fetch("jobs").fetch("spec").fetch("steps")
                    .find { |s| s["name"].to_s.include?("Summarise coverage") }
    gate = File.read(File.expand_path("spec_helper.rb", __dir__), encoding: "UTF-8")

    enforced = gate[/minimum_coverage\s+(.+)/, 1].scan(/(\w+):\s*(\d+)/).to_h
    summarised = step.fetch("run").scan(/"(\w+)"\s*=>\s*(\d+)/).to_h

    expect(summarised).to eq(enforced)
  end

  # The recording is the expensive artifact in this repository — one permanent, unwithdrawable
  # TEST invoice per example. It must survive a failed *replay* and must never be published
  # after a failed *credential scan*, which `if: always()` would do. See the step's comment.
  it "uploads a recording that passed the credential scan, whatever the replay did" do
    job = workflows.fetch("record-cassettes.yml").fetch("jobs").fetch("record")
    scan = job.fetch("steps").find { |step| step["name"].to_s.include?("Scan the recordings") }
    upload = job.fetch("steps").find { |step| step["uses"].to_s.include?("upload-artifact") }

    expect(scan.fetch("id")).to eq("hygiene")
    expect(upload.fetch("if")).to eq("always() && steps.hygiene.outcome == 'success'")
  end
end
