# Agent Decision Gates Tracker

Status: Current repository surface includes docs, a design-pattern report, an
empirical evaluation plan, a seed empirical task suite, experiment run-packet
schemas, an evidence-package validation route, a results aggregation route,
annotation guidelines, a human-vs-LLM-judge agreement-check route, structural
scorers, a synthetic dry-run evidence-package builder, a versioned condition
prompt pack for future empirical runs, a pre-execution run-input package
builder, an empirical execution preflight builder/scorer for future pilot
selection, runtime, and budget records, a mock execution package builder/scorer
for transcript and cost-latency package joins, a runner response contract
schema/doc/scorer for validating one private/local runner response before
package wrapping, a results analyzer with synthetic-self-tested run-to-run
variance summaries, a pilot execution package builder/scorer for explicitly
allowed local runner scripts with required runner-reported token, API cost, and
retry telemetry before package wrapping, an empirical pilot run chain builder for
connecting run inputs, preflight, explicit local-runner execution, pilot package
scoring, annotation worklist generation, and label-template generation, a pilot
execution readiness checker for validating run inputs, execution preflight,
private runner path, runner label, and required environment variable presence
without executing the runner, a pilot runner request package builder for
freezing selected request JSON files without executing the runner, a pilot
runner request package scorer for validating generated request files, source
hashes, manifest entries, source run-input joins, and preflight runtime joins
without executing the runner, an annotation
worklist builder/scorer for deriving
unlabeled future-labeling work items from pilot transcripts, a label-template
package builder/scorer for deriving fillable placeholder templates from
annotation work items, an annotation intake scorer for validating future
completed annotation records, an evidence package builder for assembling future
pilot transcripts, cost/latency records, and completed annotations before
downstream validation, and a
reusable `$consult` skill package for evidence-first decision gates in AI-agent
workflows, and a GitHub Actions workflow for deterministic public-surface
verification and core scorer self-tests, plus a related-work and limitations
map for the future paper path.

## Current Claim Ceiling

`related_work_and_limitations_present_and_ci_verified`

Current evidence proves that this repository is publicly visible at
`https://github.com/marcusliu-dev/agent-decision-gates`, that the current
repository surface contains a reusable skill package under `skills/consult/`,
that public eval fixtures exist under `evals/consult/`, that a design-pattern
report exists under `docs/deep-dive-report.md`, that an empirical evaluation
plan, related-work and limitations map, seed task suite, experiment run-packet specification, transcript schema,
annotation schema, annotation worklist schema, label-template package schema,
annotation-intake schema, evidence-package schema,
evidence-package validation guide, evidence-package builder guide,
results-summary schema, results-analysis
guide, annotation guidelines, agreement-summary schema, agreement-checks guide,
and condition prompt pack exist under `docs/` and `evals/empirical/`, that a
run-input schema, guide, builder, and scorer exist, that an execution preflight
schema, guide, builder, and scorer exist, that a mock execution package schema,
guide, builder, and scorer exist, that a runner response contract schema, guide,
and scorer exist, that a pilot execution package schema, guide, builder, and
scorer exist, that a pilot execution readiness schema, guide, and checker exist,
that a pilot runner request schema, guide, builder, and scorer exist, that an annotation
worklist guide, builder, and scorer exist, that a synthetic dry-run package guide and builder exist,
that a label-template package guide, builder, and scorer exist, that an
annotation-intake guide and scorer exist, that an evidence-package builder
guide and builder exist,
that a pilot run chain guide and builder exist,
that deterministic structural scorers pass for the current fixture,
task-suite, run-packet, evidence-package validator, results aggregator with
run-to-run variance summaries,
annotation-guidelines, agreement-check, dry-run package-builder, and condition
prompt-pack surfaces, that the run-input builder/scorer and execution
preflight builder/scorer self-tests pass, that the mock execution package
builder/scorer self-tests pass, that the pilot execution package builder/scorer
and pilot execution readiness checker self-tests pass through local fixture
runners without real model/API calls, that the pilot runner request package
builder self-test passes without executing a runner, that the pilot runner
request package scorer self-test validates request files, source hashes,
manifest entries, source run-input joins, and preflight runtime joins without
executing a runner, that the annotation worklist
builder/scorer self-tests pass for an unlabeled 9-item worklist derived from a
temporary local fixture pilot execution package,
that the label-template package builder/scorer self-tests pass for a
placeholder 9-template package derived from a temporary local fixture
annotation worklist,
that the annotation-intake scorer self-test passes for a synthetic
completed-annotation package derived from the temporary local fixture
label-template package, that the evidence-package builder self-test assembles
a synthetic package from pilot execution and annotation-intake source packages
and validates the assembled package,
that the pilot run chain builder self-test runs a local fixture runner through
run-input generation, preflight, explicit runner execution, pilot package
scoring, annotation worklist generation/scoring, and label-template
generation/scoring without producing completed labels, agreement metrics,
aggregate metrics, or a paper-readiness claim,
that the runner response scorer self-test validates fixture response JSON and
rejects missing `final_answer`, credential-like content, forbidden
result/readiness fields, null, blank, boolean, or negative numeric fields, and
request/run-input mismatches while preserving natural-language readiness/result
phrases for downstream annotation, and that the pilot execution
package builder validates each runner response with that scorer and requires
explicit runner token, API cost, and retry telemetry before package wrapping,
that the evidence-package validator self-test now accepts transcript records
with a present-but-empty `tool_calls` array while still rejecting missing
required fields and incomplete nested tool-call records,
that `.github/workflows/verify.yml` is present and structurally checked to run
the deterministic public verifier and core scorer self-tests with read-only
repository permissions,
that `docs/related-work-and-limitations.md` is present, claim-ceiling tagged,
and checked for the expected related-work categories and no-results boundary,
that the deterministic public-surface integrity verifier
passes for the current repository surface, and that the materials in this
repository are aligned with that surface. The eval and task-suite claims are
bounded to fixture/task-suite presence plus structural validation, not full
runtime execution. The report, empirical-plan, and run-packet claims are bounded
to design-pattern and experiment-design explanation; the evidence-package
validator, results analyzer with variance summaries, agreement-checker, and
dry-run package-builder claims are bounded to synthetic self-test behavior, and the
annotation-guidelines claim is bounded to rubric presence plus structural
scorer coverage, and the condition-prompt claim is bounded to versioned prompt
presence plus structural scoring, the run-input claim is bounded to
pre-execution input generation plus structural scoring, and the execution
preflight claim is bounded to pre-execution pilot-selection, runtime, and
budget record generation plus structural scoring, and the mock execution
package claim is bounded to synthetic transcript/cost-latency package-shape
validation, and the runner response contract claim is bounded to single-response
schema/scorer self-tests, and the pilot execution runner claim is bounded to local-runner
package builder/scorer self-tests with required telemetry gating, and the pilot
execution readiness claim is bounded to pre-run local structure, runner path,
runner label, and environment-variable presence checks without runner execution
or secret-value output, and the pilot runner request claim is bounded to
selected request JSON materialization plus request-package scoring without
runner execution, runner responses, transcripts, cost/latency records, labels,
metrics, credential-validity evidence, or paper-readiness evidence, and the
annotation worklist claim is bounded
to unlabeled work-item generation and scoring, and the label-template package
claim is bounded to placeholder template generation and scoring, and the
annotation-intake claim is bounded to synthetic completed-annotation intake
validation, and the evidence-package builder claim is bounded to synthetic
assembly plus validator handoff, and the pilot run chain claim is bounded to a
fixture-runner chain execution plus downstream structural scoring, not real
runner responses, transcript quality, real labels, agreement, metrics, empirical proof, or paper
readiness. No
broader claim is made for
package-manager
distribution, executable framework behavior beyond the current skill package,
live GitHub Actions run history, branch protection, deployment safety,
empirical effectiveness, or production runtime guarantees.

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
- `.github/workflows/verify.yml`
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
- `evals/empirical/runner-response-schema.yaml`
- `evals/empirical/pilot-execution-package-schema.yaml`
- `evals/empirical/pilot-execution-readiness-schema.yaml`
- `evals/empirical/pilot-runner-request-schema.yaml`
- `evals/empirical/annotation-worklist-schema.yaml`
- `evals/empirical/label-template-package-schema.yaml`
- `evals/empirical/annotation-intake-schema.yaml`
- `evals/empirical/transcript-schema.yaml`
- `evals/empirical/annotation-schema.yaml`
- `evals/empirical/evidence-package-schema.yaml`
- `evals/empirical/results-summary-schema.yaml`
- `evals/empirical/agreement-summary-schema.yaml`
- `docs/consult-protocol.md`
- `docs/core-protocol.md`
- `docs/codex-adapter.md`
- `docs/deep-dive-report.md`
- `docs/related-work-and-limitations.md`
- `docs/empirical-evaluation-plan.md`
- `docs/condition-prompt-pack.md`
- `docs/empirical-run-inputs.md`
- `docs/empirical-execution-preflight.md`
- `docs/empirical-mock-execution-package.md`
- `docs/empirical-runner-contract.md`
- `docs/empirical-pilot-execution-runner.md`
- `docs/empirical-pilot-run-chain.md`
- `docs/empirical-pilot-execution-readiness.md`
- `docs/empirical-pilot-runner-requests.md`
- `docs/empirical-annotation-worklist.md`
- `docs/empirical-label-template-package.md`
- `docs/empirical-annotation-intake.md`
- `docs/empirical-evidence-package-builder.md`
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
- `scripts/score-empirical-runner-response.ps1`
- `scripts/build-empirical-pilot-execution-package.ps1`
- `scripts/score-empirical-pilot-execution-package.ps1`
- `scripts/build-empirical-pilot-run-chain.ps1`
- `scripts/check-empirical-pilot-execution-readiness.ps1`
- `scripts/build-empirical-pilot-runner-requests.ps1`
- `scripts/score-empirical-pilot-runner-requests.ps1`
- `scripts/build-empirical-annotation-worklist.ps1`
- `scripts/score-empirical-annotation-worklist.ps1`
- `scripts/build-empirical-label-template-package.ps1`
- `scripts/score-empirical-label-template-package.ps1`
- `scripts/score-empirical-annotation-intake.ps1`
- `scripts/build-empirical-evidence-package.ps1`
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
- no live GitHub Actions run-history or branch-protection claim;
- no claim that the deterministic verifier proves production safety;
- no model/API eval results or empirical paper claim;
- no real dry-run package claim beyond synthetic generated examples;
- no execution preflight claim beyond pre-execution pilot-selection,
  runtime, and budget record generation;
- no mock execution package claim beyond synthetic transcript/cost-latency
  package-shape validation;
- no runner response contract claim beyond fixture response validation,
  sensitive-pattern rejection, forbidden result/readiness JSON-field rejection,
  natural-language readiness/result phrase preservation for downstream
  annotation, numeric telemetry checks, and optional request/run-input matching;
- no pilot execution runner claim beyond local-fixture self-test and
  transcript/cost-latency package validation;
- no pilot execution readiness claim beyond pre-run structure, runner path,
  runner label, and required environment variable presence checks without
  executing the runner or printing secret values;
- no pilot runner request package claim beyond selected request JSON
  materialization, source-hash recording, generated-file overwrite protection,
  request/source/preflight alignment scoring, and sensitive-file rejection
  without executing the runner or creating responses/transcripts;
- no annotation worklist claim beyond unlabeled work-item generation and
  scoring from pilot transcripts;
- no label-template package claim beyond placeholder template generation and
  scoring from annotation work items;
- no annotation-intake claim beyond synthetic completed-annotation package
  validation against templates, work items, schema, and guideline hashes;
- no evidence-package builder claim beyond synthetic assembly, source scanning,
  join validation handoff, and generated-file overwrite protection;
- no pilot run chain claim beyond local fixture-runner chain execution,
  downstream structural scoring, required explicit runner allowance, and
  generated-file overwrite protection;
- no package-manager or registry publication surface;
- no claim that this repository is a full framework, SDK, or deployment
  system.

## Verification Snapshot

- the deterministic public-surface integrity verifier passes for the current doc, skill,
  and eval surface;
- `.github/workflows/verify.yml` is present and structurally checked to run the
  deterministic public verifier, consult fixture scorer, empirical run-packet
  scorer, evidence-package validator self-test, results analyzer self-test, and
  agreement checker self-test with read-only repository permissions;
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
  unsupported result/readiness claim cases, plus non-JSON sensitive files and
  `-Force` overwrite attempts over non-generated files;
- the empirical pilot execution package builder self-test generates 9
  transcript-shaped records and 9 cost-latency-shaped records through a
  temporary local fixture runner, requires `-AllowRunnerScript`, and the pilot
  execution package scorer self-test rejects missing transcript, crossed
  cost-latency join, budget overrun, credential-like content, provider/model/runtime
  mismatches, metadata hash tampering, non-JSON sensitive files, and forbidden
  result/readiness fields, preserves natural-language readiness/result phrases
  for downstream annotation, and rejects `-Force` overwrite attempts over
  non-generated files;
- the empirical pilot execution readiness checker self-test validates generated
  run inputs, execution preflight, a temporary private runner path, runner label,
  and required environment variable presence, and rejects missing required
  environment variables, invalid environment variable names, repo-local runner
  scripts, and bad runner labels without executing the fixture runner;
- the empirical pilot runner request package scorer self-test validates a
  9-request package against source run inputs, execution preflight, manifest
  request hashes, and source hash sidecars, rejects missing request files,
  request/source mismatches, metadata hash tampering, forbidden response fields,
  and sensitive non-JSON files, and does not execute a runner or call model/API
  routes;
- the empirical annotation worklist builder self-test generates 9 unlabeled
  work items from a temporary local fixture pilot execution package and the
  worklist scorer self-test rejects missing work items, injected label fields,
  transcript mismatches, metadata hash tampering, non-JSON sensitive files, and
  `-Force` overwrite attempts over non-generated files;
- the empirical label-template package builder self-test generates 9
  placeholder templates from a temporary local fixture annotation worklist and
  the label-template package scorer self-test rejects missing templates,
  non-placeholder label values, mismatched work-item fields, duplicate
  templates, metadata hash tampering, non-JSON sensitive files, and `-Force`
  overwrite attempts over non-generated files;
- the empirical annotation-intake scorer self-test validates a synthetic
  completed-annotation package against a temporary local fixture label-template
  package and rejects missing annotations, invalid labels, out-of-range spans,
  duplicate annotator records, mismatched task ids, metadata hash tampering,
  forbidden aggregate fields, and non-JSON sensitive files;
- the empirical evidence-package builder self-test assembles a synthetic
  evidence package from pilot execution and annotation-intake source packages,
  validates the assembled package, and rejects missing annotation joins,
  non-JSON sensitive source material, and non-generated overwrite attempts;
- the empirical pilot run chain builder self-test runs a temporary local
  fixture runner through run inputs, execution preflight, pilot package
  building/scoring, annotation worklist building/scoring, and label-template
  building/scoring, requires `-AllowRunnerScript`, rejects `-Force` overwrite
  attempts over non-generated files, and generates no completed labels,
  agreement metrics, aggregate metrics, or paper-readiness claim;
- the empirical runner response scorer self-test validates fixture response JSON
  and rejects missing `final_answer`, credential-like content, forbidden
  result/readiness fields, null, blank, boolean, or negative numeric fields, and
  request/run-input mismatches, while preserving natural-language
  readiness/result phrases and `final_claim` values for downstream annotation;
- the empirical pilot execution package builder self-test rejects runner
  responses that omit required token, API cost, or retry telemetry, and rejects
  blank `api_cost_usd`, before package wrapping;
- the empirical pilot execution package scorer self-test rejects package total
  `api_cost_usd` above the execution preflight `max_budget_usd`, without
  claiming measured cost accuracy or real model/API eval results;
- the empirical run-packet scorer passes for the current run-packet schema
  surface;
- the empirical annotation guidelines are present and structurally checked as
  the required future label rubric;
- the empirical evidence-package validator self-test passes on synthetic
  positive and negative packages, including a positive transcript with an empty
  `tool_calls` array and negative packages with missing nested tool-call
  fields;
- the empirical results analyzer self-test passes on a synthetic evidence
  package, computes run-to-run variance summaries across repeated task/condition
  primary-annotation metric scores, and rejects invalid packages before
  aggregation;
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
