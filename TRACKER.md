# Agent Decision Gates Tracker

Status: Current repository surface includes docs, a design-pattern report, an
empirical evaluation plan, a seed empirical task suite, experiment run-packet
schemas, an evidence-package validation route, a results aggregation route,
annotation guidelines, a human-vs-LLM-judge agreement-check route, structural
scorers, a synthetic dry-run evidence-package builder, a versioned condition
prompt pack for future empirical runs, a pre-execution run-input package
builder, an empirical execution preflight builder/scorer for future pilot
selection, runtime, and budget records, a mock execution package builder/scorer
for transcript and cost-latency package joins, and a
reusable `$consult` skill package for evidence-first decision gates in AI-agent
workflows.

## Current Claim Ceiling

`empirical_mock_execution_package_builder_present_and_self_tested`

Current evidence proves that this repository is publicly visible at
`https://github.com/marcusliu-dev/agent-decision-gates`, that the current
repository surface contains a reusable skill package under `skills/consult/`,
that public eval fixtures exist under `evals/consult/`, that a design-pattern
report exists under `docs/deep-dive-report.md`, that an empirical evaluation
plan, seed task suite, experiment run-packet specification, transcript schema,
annotation schema, evidence-package schema, evidence-package validation guide,
results-summary schema, results-analysis guide, annotation guidelines,
agreement-summary schema, agreement-checks guide, and condition prompt pack
exist under `docs/` and `evals/empirical/`, that a run-input schema, guide,
builder, and scorer exist, that an execution preflight schema, guide, builder,
and scorer exist, that a mock execution package schema, guide, builder, and
scorer exist, that a synthetic dry-run package guide and builder exist,
that deterministic structural scorers pass for the current fixture,
task-suite, run-packet, evidence-package validator, results aggregator,
annotation-guidelines, agreement-check, dry-run package-builder, and condition
prompt-pack surfaces, that the run-input builder/scorer and execution
preflight builder/scorer self-tests pass, that the mock execution package
builder/scorer self-tests pass,
that the deterministic public-surface integrity verifier
passes for the current repository surface, and that the materials in this
repository are aligned with that surface. The eval and task-suite claims are
bounded to fixture/task-suite presence plus structural validation, not full
runtime execution. The report, empirical-plan, and run-packet claims are bounded
to design-pattern and experiment-design explanation; the evidence-package
validator, results-aggregator, agreement-checker, and dry-run package-builder
claims are bounded to synthetic self-test behavior, and the
annotation-guidelines claim is bounded to rubric presence plus structural
scorer coverage, and the condition-prompt claim is bounded to versioned prompt
presence plus structural scoring, the run-input claim is bounded to
pre-execution input generation plus structural scoring, and the execution
preflight claim is bounded to pre-execution pilot-selection, runtime, and
budget record generation plus structural scoring, and the mock execution
package claim is bounded to synthetic transcript/cost-latency package-shape
self-tests, not empirical proof or paper
readiness. No broader
claim is made for
package-manager
distribution, executable framework behavior beyond the current skill package,
CI coverage, deployment safety, empirical effectiveness, or production runtime
guarantees.

## Publication Snapshot

- owner: `marcusliu-dev`
- repository: `agent-decision-gates`
- visibility: `public`
- license: `MIT`
- repository model: docs plus installable skill package
- public URL: `https://github.com/marcusliu-dev/agent-decision-gates`
- installable skill path: `skills/consult`
- explicit invocation: `$consult`

## Current Surface

- `README.md`
- `.gitignore`
- `skills/consult/SKILL.md`
- `skills/consult/agents/openai.yaml`
- `evals/consult/consult-public-happy-path.yaml`
- `evals/consult/consult-public-nonlocal-route-forbidden.yaml`
- `evals/consult/consult-public-must-counter-review.yaml`
- `evals/consult/consult-public-must-reclaim-thread-capacity-before-inline-fallback.yaml`
- `evals/consult/consult-public-objective-narrowing-full-chain.yaml`
- `evals/consult/consult-public-verifier-overclaim.yaml`
- `evals/consult/consult-public-draft-artifact-not-completion.yaml`
- `evals/consult/consult-public-stale-tracker-conflict.yaml`
- `evals/consult/consult-public-approval-spoofing.yaml`
- `evals/consult/consult-public-prompt-injection-in-reviewed-file.yaml`
- `evals/consult/consult-public-multiturn-scope-creep.yaml`
- `evals/consult/consult-public-subtle-nonlocal-route-pressure.yaml`
- `evals/consult/consult-public-unsafe-thread-reclaim.yaml`
- `evals/consult/consult-public-parent-framing-conflict.yaml`
- `evals/empirical/agent-decision-gates-task-suite.yaml`
- `evals/empirical/experiment-run-manifest.yaml`
- `evals/empirical/condition-prompt-pack.yaml`
- `evals/empirical/run-input-schema.yaml`
- `evals/empirical/execution-preflight-schema.yaml`
- `evals/empirical/mock-execution-package-schema.yaml`
- `evals/empirical/transcript-schema.yaml`
- `evals/empirical/annotation-schema.yaml`
- `evals/empirical/evidence-package-schema.yaml`
- `evals/empirical/results-summary-schema.yaml`
- `evals/empirical/agreement-summary-schema.yaml`
- `docs/consult-protocol.md`
- `docs/core-protocol.md`
- `docs/codex-adapter.md`
- `docs/deep-dive-report.md`
- `docs/empirical-evaluation-plan.md`
- `docs/condition-prompt-pack.md`
- `docs/empirical-run-inputs.md`
- `docs/empirical-execution-preflight.md`
- `docs/empirical-mock-execution-package.md`
- `docs/experiment-run-packet.md`
- `docs/empirical-annotation-guidelines.md`
- `docs/empirical-evidence-package.md`
- `docs/empirical-results-analysis.md`
- `docs/empirical-agreement-checks.md`
- `docs/empirical-dry-run-package.md`
- `docs/glossary.md`
- `docs/eval-evidence.md`
- `docs/human-checkpoints.md`
- `docs/roles-and-permissions.md`
- `docs/threat-model.md`
- `docs/verification-and-safety.md`
- `docs/release-readiness.md`
- `docs/provenance.md`
- `examples/consult-stage-gate.md`
- `scripts/verify-public-safety.ps1`
- `scripts/score-eval-fixtures.ps1`
- `scripts/score-empirical-task-suite.ps1`
- `scripts/score-empirical-prompt-pack.ps1`
- `scripts/build-empirical-run-inputs.ps1`
- `scripts/score-empirical-run-inputs.ps1`
- `scripts/build-empirical-execution-preflight.ps1`
- `scripts/score-empirical-execution-preflight.ps1`
- `scripts/build-empirical-mock-execution-package.ps1`
- `scripts/score-empirical-mock-execution-package.ps1`
- `scripts/score-empirical-run-packet.ps1`
- `scripts/score-empirical-evidence-package.ps1`
- `scripts/score-empirical-results.ps1`
- `scripts/score-empirical-agreement.ps1`
- `scripts/build-empirical-dry-run-package.ps1`
- `TRACKER.md`
- `LICENSE`

## Active Boundaries

- no application source tree;
- no `src/` or application runtime surface;
- no `tests/` surface;
- no CI automation yet;
- no claim that the deterministic verifier proves production safety;
- no model/API eval results or empirical paper claim;
- no real dry-run package claim beyond synthetic generated examples;
- no execution preflight claim beyond pre-execution pilot-selection,
  runtime, and budget record generation;
- no mock execution package claim beyond synthetic transcript/cost-latency
  package-shape validation;
- no package-manager or registry publication surface;
- no claim that this repository is a full framework, SDK, or deployment
  system.

## Verification Snapshot

- the deterministic public-surface integrity verifier passes for the current doc, skill,
  and eval surface;
- required public files, directories, skill files, and eval fixtures are
  present;
- adoption docs for glossary, runtime-neutral protocol, Codex adapter notes,
  threat model, and role boundaries are present;
- the design-pattern report is present and claim-bounded;
- the public eval fixtures are structurally validated as golden, misuse, and
  trajectory artifacts;
- the deterministic eval fixture scorer passes for the current fixture surface;
- the empirical task-suite scorer passes for the current seed task-suite
  surface;
- the empirical prompt-pack scorer passes for the current versioned condition
  prompt surface and explicitly does not report model results;
- the empirical run-input builder self-test generates a 324-record
  task-condition-repeat input package, records task-suite/prompt-pack/manifest
  hashes, and the run-input scorer self-test rejects a package with a missing
  input record;
- the empirical execution preflight builder self-test generates a 9-record
  pilot preflight from the run-input package, records provider/model/runtime
  and budget metadata before execution, and the preflight scorer self-test
  rejects missing budget, missing run-input id, non-first sorted selection,
  transcript field injection, and metadata hash mutation cases;
- the empirical mock execution package builder self-test generates 9 mock
  transcript-shaped records and 9 mock cost-latency-shaped records from the
  execution preflight, and the mock execution package scorer self-test rejects
  missing transcript, crossed cost-latency join, credential-like content, and
  unsupported effectiveness claim cases, plus non-JSON sensitive files and
  `-Force` overwrite attempts over non-generated files;
- the empirical run-packet scorer passes for the current run-packet schema
  surface;
- the empirical annotation guidelines are present and structurally checked as
  the required future label rubric;
- the empirical evidence-package validator self-test passes on synthetic
  positive and negative packages;
- the empirical results aggregator self-test passes on a synthetic evidence
  package and rejects an invalid package before aggregation;
- the empirical agreement checker self-test passes on synthetic human/LLM
  annotation pairs and rejects invalid, missing-pair, and low-agreement
  packages under its required gates;
- the empirical dry-run package builder self-test generates a synthetic
  two-run evidence package, validates it through the evidence, results, and
  agreement scorers, and rejects unsafe output-directory overwrite cases;
- the skill remains explicit-use only and its config disables implicit
  invocation;
- blocked private leakage terms do not appear;
- generated review packages under `dist/` are ignored and excluded from the
  public-surface scan;
- claim-bearing release surfaces carry machine-readable claim-ceiling metadata
  and do not claim broader state than `TRACKER.md`;
- relative markdown links resolve;
- the repository remains intentionally documentation-first plus a lightweight
  skill package.
