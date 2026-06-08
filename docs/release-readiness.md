# Release Readiness

<!-- claim_ceiling: empirical_pilot_runner_request_package_scorer_present_and_self_tested -->

Status: Current repository surface includes documentation, a design-pattern
report, an empirical evaluation plan, experiment run-packet schemas, an
evidence-package validator, a results aggregator with run-to-run variance
summaries, an installable `$consult`
skill package, public eval fixtures, a seed empirical task suite, empirical
annotation guidelines, an agreement checker, and deterministic structural
checks, plus a synthetic dry-run evidence-package builder and versioned
condition prompt pack, a pre-execution run-input package builder, and an
execution preflight builder/scorer for future pilot selection, runtime, and
budget records, plus a mock execution package builder/scorer for synthetic
transcript and cost-latency package joins, plus a runner response contract
schema/doc/scorer for validating one private/local runner response before
package wrapping, plus a pilot execution package builder/scorer for explicitly
allowed local runner scripts with required runner token, API cost, and retry
telemetry before package wrapping, plus an annotation worklist builder/scorer for deriving unlabeled future-labeling work items from
pilot transcripts, plus a label-template package builder/scorer for deriving
fillable placeholder templates from annotation work items, plus an annotation
intake scorer for validating future completed annotation records, plus an
evidence-package builder for assembling future pilot transcripts, cost/latency
records, and completed annotations into a validation-ready evidence package,
plus a pilot run chain builder for connecting run inputs, execution preflight,
explicit local-runner execution, pilot package validation, annotation worklist
generation, and label-template generation, plus a pilot execution readiness
checker for validating run inputs, execution preflight, private runner path,
runner label, and required environment variable presence before any explicit
local runner invocation, plus a pilot runner request package builder for
freezing selected request JSON files before any private runner invocation, plus
a pilot runner request package scorer for validating generated request files,
source hashes, manifest entries, source run-input joins, and preflight runtime
joins before runner execution.

## Purpose

This document records the current public release shape of this repository:
what is present, what has been verified, and what still remains intentionally
out of scope.

## Current Scope

The current repository surface includes:

- `README.md`
- `.gitignore`
- `TRACKER.md`
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
- `LICENSE`

This repository is intentionally documentation-first plus a lightweight skill
package. It does not currently include application source code, CI automation,
or a broader framework/runtime distribution surface.

## Current Release Claim

The current release claim is narrow and explicit:

- the public repository contains a reusable decision-gate pattern for agentic
  workflows plus an installable or directly reusable `$consult` skill
  artifact;
- the documentation and skill surface are internally consistent and
  verifier-backed, the design-pattern report is present, and the public eval
  fixtures, seed empirical task suite, experiment run-packet schemas,
  annotation-guidelines surface, and evidence-package validator are
  structurally validated or self-tested, and the agreement-check route is
  synthetic-self-tested, with a synthetic dry-run package builder self-tested
  against the validator chain and a versioned condition prompt pack
  structurally scored, plus a pre-execution run-input builder and scorer
  self-tested, and an execution preflight builder/scorer self-tested for
  pilot-selection, runtime, and budget records before execution, plus a mock
  execution package builder/scorer self-tested for synthetic transcript and
  cost-latency package joins, plus a runner response contract scorer self-tested
  for single-response shape and boundary checks, plus a pilot execution package builder/scorer
  self-tested through a local fixture runner and missing cost-telemetry plus
  budget-overrun rejection,
  plus an annotation worklist
  builder/scorer self-tested for unlabeled future-labeling work items derived
  from pilot transcripts, plus a label-template package builder/scorer
  self-tested for fillable placeholder templates derived from annotation work
  items, plus an annotation-intake scorer self-tested for validating synthetic
  completed annotation records against templates, work items, schema, and
  guideline hashes, plus an evidence-package builder self-tested for assembling
  synthetic pilot transcripts, cost/latency records, and completed annotation
  records before downstream validation, plus a pilot run chain builder
  self-tested through a temporary local fixture runner from run-input
  generation through preflight, explicit runner execution, pilot package
  scoring, annotation worklist generation/scoring, and label-template
  generation/scoring;
  plus a pilot runner request package builder/scorer self-tested for selected
  request JSON materialization and source/preflight/package validation before
  runner execution;
- the current contents are suitable for public reading, reuse, and adaptation
  under `MIT`.

The current claim ceiling is no higher than
`empirical_pilot_runner_request_package_scorer_present_and_self_tested`.

This repository does not claim to be a framework, package, SDK, or deployment
system.

## Verified Evidence

- the deterministic public-surface integrity verifier passes for the current public
  doc-plus-skill surface;
- required public files, directories, skill files, and eval fixtures are
  present;
- adoption docs for glossary, runtime-neutral protocol, Codex adapter notes,
  threat model, and role boundaries are present;
- the design-pattern report states its non-empirical boundary and does not
  claim paper readiness;
- the public eval fixtures expose golden, misuse, and trajectory scenarios and
  pass the repository's structural fixture checks;
- the deterministic eval fixture scorer passes for the current fixture surface;
- the deterministic empirical task-suite scorer passes for the current seed
  task-suite surface and explicitly does not report model results;
- the deterministic empirical prompt-pack scorer passes for the current
  versioned condition prompt surface and explicitly does not report model
  results;
- the deterministic empirical run-input builder and scorer self-tests pass for
  a generated 324-record pre-execution input package and explicitly do not call
  model/API routes;
- the deterministic empirical execution preflight builder and scorer self-tests
  pass for a generated 9-record pilot preflight that records provider, model
  alias, runtime surface, budget, selected run-input ids, and source hashes
  before execution, reject a non-first sorted selection tamper case, and
  explicitly do not call model/API routes;
- the deterministic empirical mock execution package builder and scorer
  self-tests pass for a generated 9-record mock transcript/cost-latency package
  and reject missing transcript, crossed cost-latency join, credential-like
  content, non-JSON sensitive files, unsupported result/readiness claim cases, and
  `-Force` overwrite attempts over non-generated files;
- the deterministic empirical pilot execution package builder and scorer
  self-tests pass for a generated 9-record transcript/cost-latency package
  produced through a temporary local fixture runner, require
  `-AllowRunnerScript`, and reject missing transcript, crossed cost-latency
  join, budget overrun, credential-like content, provider/model/runtime mismatches, metadata
  hash tampering, non-JSON sensitive files, unsupported result/readiness claim
  cases, and `-Force` overwrite attempts over non-generated files;
- the deterministic empirical pilot execution readiness checker self-test
  validates generated run inputs, execution preflight, a temporary private
  runner path, runner label, and required environment variable presence, and
  rejects missing required environment variables, invalid environment variable
  names, repo-local runner scripts, and bad runner labels without executing the
  fixture runner or printing secret values;
- the deterministic empirical pilot runner request package builder self-test
  generates 9 selected request JSON files from the run-input package and
  execution preflight, records source hashes, rejects missing selected
  run-input ids, bad runner labels, and non-generated overwrite attempts, and
  does not execute a runner or call model/API routes;
- the deterministic empirical pilot runner request package scorer self-test
  validates a 9-request package against source run inputs, execution preflight,
  manifest request hashes, and source hash sidecars, rejects missing request
  files, request/source mismatches, metadata hash tampering, forbidden response
  fields, and sensitive non-JSON files, and does not execute a runner or call
  model/API routes;
- the deterministic empirical annotation worklist builder and scorer
  self-tests pass for a generated 9-item unlabeled worklist derived from a
  temporary local fixture pilot execution package and reject missing work
  items, injected label fields, transcript mismatches, metadata hash tampering,
  non-JSON sensitive files, and `-Force` overwrite attempts over
  non-generated files;
- the deterministic empirical label-template package builder and scorer
  self-tests pass for a generated 9-template placeholder package derived from a
  temporary local fixture annotation worklist and reject missing templates,
  non-placeholder label values, mismatched work-item fields, duplicate
  templates, metadata hash tampering, non-JSON sensitive files, and `-Force`
  overwrite attempts over non-generated files;
- the deterministic empirical annotation-intake scorer self-test validates a
  synthetic completed-annotation package against a temporary local fixture
  label-template package and rejects missing annotations, invalid labels,
  out-of-range spans, duplicate annotator records, mismatched task ids,
  metadata hash tampering, forbidden aggregate fields, and non-JSON sensitive
  files;
- the deterministic empirical evidence-package builder self-test assembles a
  synthetic evidence package from pilot execution and annotation-intake source
  packages, validates the assembled package, and rejects missing annotation
  joins, non-JSON sensitive source material, and non-generated overwrite
  attempts;
- the deterministic empirical pilot run chain builder self-test runs a
  temporary local fixture runner through run inputs, execution preflight,
  pilot package building/scoring, annotation worklist building/scoring, and
  label-template building/scoring, requires `-AllowRunnerScript`, rejects
  `-Force` overwrite attempts over non-generated files, and generates no
  completed labels, agreement metrics, aggregate metrics, or paper-readiness
  claim;
- the deterministic empirical runner response scorer self-test validates fixture
  response JSON and rejects missing `final_answer`, credential-like content,
  forbidden result/readiness fields, unsupported result/readiness claim text,
  null, blank, boolean, or negative numeric fields, and request/run-input
  mismatches;
- the deterministic empirical run-packet scorer passes for the current
  manifest, transcript-schema, annotation-schema, and run-packet doc surface;
- the empirical annotation guidelines are present and structurally checked as
  the required future annotation rubric;
- the deterministic empirical evidence-package validator passes its synthetic
  positive and negative self-test and explicitly does not provide real
  transcripts, labels, or model results;
- the deterministic empirical results analyzer passes its synthetic self-test,
  includes run-to-run variance summaries across repeated task/condition
  primary-annotation metric scores, and explicitly does not provide real
  aggregate metrics, real variance results, or paper readiness;
- the deterministic empirical pilot execution package builder rejects runner
  responses that omit required token, API cost, or retry telemetry, and rejects
  blank API cost telemetry, before package wrapping; it explicitly does not
  prove real cost accuracy, runner quality, or model/API eval results;
- the deterministic empirical pilot execution package scorer rejects package
  total API cost above the execution preflight budget; it explicitly does not
  prove real cost accuracy, runner quality, or model/API eval results;
- the deterministic empirical agreement checker passes its synthetic self-test
  and explicitly does not provide real human/LLM-judge agreement or judge
  validity evidence;
- the deterministic empirical dry-run package builder passes its self-test by
  generating a synthetic two-run evidence package, validating it through the
  evidence-package, results, and agreement scorers, and rejecting unsafe
  output-directory overwrite cases;
- the skill remains explicit-use only and the public config keeps implicit
  invocation disabled;
- blocked markers and blocked private leakage terms do not appear;
- generated review packages under `dist/` are ignored and excluded from the
  public-surface scan;
- relative markdown links resolve;
- `src/` and `tests/` remain absent on the current doc-plus-skill surface;
- `LICENSE` and `docs/provenance.md` are present and aligned with the current
  repository state.

## Current Intentional Deferrals

These are intentionally outside the current release scope:

- CI setup;
- executable product scaffolding beyond the current skill package;
- a package or framework distribution surface;
- deployment automation;
- any claim that this deterministic verifier proves production safety,
  empirical effectiveness, paper readiness, or universal runtime correctness;
- model/API eval execution, transcript/label production, real aggregate metrics,
  human/LLM-judge agreement measurement, judge-validity evidence, or result
  publication;
- any claim that the execution preflight is itself a real model/API run,
  transcript, annotation, cost/latency result, or empirical finding;
- any claim that the mock execution package is itself a real model/API run,
  real transcript, annotation, cost/latency result, or empirical finding;
- any claim that the pilot execution runner self-test is itself a completed
  public model/API study, annotation set, metric result, agreement result, or
  empirical finding;
- any claim that the pilot execution readiness checker is itself a completed
  model/API run, proof of credential validity, runner-quality result, real cost
  accuracy result, transcript, annotation, metric result, agreement result, or
  empirical finding;
- any claim that the pilot runner request package builder or scorer is itself a completed
  model/API run, validated runner response, transcript, cost/latency result,
  proof of credential validity, runner-quality result, annotation, metric
  result, agreement result, or empirical finding;
- any claim that the annotation worklist self-test is itself a completed
  annotation set, human-label result, LLM-judge result, agreement measurement,
  metric result, annotator-quality claim, or empirical finding;
- any claim that the label-template package self-test is itself a completed
  annotation set, human-label result, LLM-judge result, agreement measurement,
  metric result, annotator-quality claim, or empirical finding;
- any claim that the annotation-intake self-test is itself a real completed
  annotation set, human-label result, LLM-judge result, agreement measurement,
  metric result, annotator-quality claim, judge-validity claim, or empirical
  finding;
- any claim that the evidence-package builder self-test is itself a real
  transcript-quality, annotation-quality, agreement, metric, model-quality,
  empirical-effectiveness, or paper-readiness finding;
- any claim that the pilot run chain self-test is itself a completed model/API
  experiment, real transcript-quality finding, completed annotation set,
  human/LLM-judge agreement measurement, aggregate metric, empirical
  effectiveness result, or paper-readiness finding;
- any claim that the synthetic dry-run package is a real experiment output.

## Interpretation Rule

If the repository later adds code, tests, CI, or runtime integrations, this
document should be updated together with the real verification surface before
making broader claims.
