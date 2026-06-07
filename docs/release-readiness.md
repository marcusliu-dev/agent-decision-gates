# Release Readiness

<!-- claim_ceiling: empirical_condition_prompt_pack_present_and_structurally_scored -->

Status: Current repository surface includes documentation, a design-pattern
report, an empirical evaluation plan, experiment run-packet schemas, an
evidence-package validator, a results aggregator, an installable `$consult`
skill package, public eval fixtures, a seed empirical task suite, empirical
annotation guidelines, an agreement checker, and deterministic structural
checks, plus a synthetic dry-run evidence-package builder and versioned
condition prompt pack.

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
  structurally scored;
- the current contents are suitable for public reading, reuse, and adaptation
  under `MIT`.

The current claim ceiling is no higher than
`empirical_condition_prompt_pack_present_and_structurally_scored`.

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
- the deterministic empirical run-packet scorer passes for the current
  manifest, transcript-schema, annotation-schema, and run-packet doc surface;
- the empirical annotation guidelines are present and structurally checked as
  the required future annotation rubric;
- the deterministic empirical evidence-package validator passes its synthetic
  positive and negative self-test and explicitly does not provide real
  transcripts, labels, or model results;
- the deterministic empirical results aggregator passes its synthetic self-test
  and explicitly does not provide real aggregate metrics or paper readiness;
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
- any claim that the synthetic dry-run package is a real experiment output.

## Interpretation Rule

If the repository later adds code, tests, CI, or runtime integrations, this
document should be updated together with the real verification surface before
making broader claims.
