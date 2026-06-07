# Agent Decision Gates Tracker

Status: Current repository surface includes docs, a design-pattern report, an
empirical evaluation plan, a seed empirical task suite, experiment run-packet
schemas, an evidence-package validation route, a results aggregation route,
structural scorers, and a
reusable `$consult` skill package for evidence-first decision gates in AI-agent
workflows.

## Current Claim Ceiling

`empirical_results_aggregator_present_and_self_tested`

Current evidence proves that this repository is publicly visible at
`https://github.com/marcusliu-dev/agent-decision-gates`, that the current
repository surface contains a reusable skill package under `skills/consult/`,
that public eval fixtures exist under `evals/consult/`, that a design-pattern
report exists under `docs/deep-dive-report.md`, that an empirical evaluation
plan, seed task suite, experiment run-packet specification, transcript schema,
annotation schema, evidence-package schema, evidence-package validation guide,
results-summary schema, and results-analysis guide exist under `docs/` and
`evals/empirical/`, that deterministic structural scorers pass for the current
fixture, task-suite, run-packet, evidence-package validator, and results
aggregator surfaces, that the deterministic public-surface integrity verifier
passes for the current repository surface, and that the materials in this
repository are aligned with that surface. The eval and task-suite claims are
bounded to fixture/task-suite presence plus structural validation, not full
runtime execution. The report, empirical-plan, and run-packet claims are bounded
to design-pattern and experiment-design explanation; the evidence-package
validator and results-aggregator claims are bounded to synthetic self-test
behavior, not empirical proof or paper readiness. No broader claim is made for
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
- `evals/empirical/transcript-schema.yaml`
- `evals/empirical/annotation-schema.yaml`
- `evals/empirical/evidence-package-schema.yaml`
- `evals/empirical/results-summary-schema.yaml`
- `docs/consult-protocol.md`
- `docs/core-protocol.md`
- `docs/codex-adapter.md`
- `docs/deep-dive-report.md`
- `docs/empirical-evaluation-plan.md`
- `docs/experiment-run-packet.md`
- `docs/empirical-evidence-package.md`
- `docs/empirical-results-analysis.md`
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
- `scripts/score-empirical-run-packet.ps1`
- `scripts/score-empirical-evidence-package.ps1`
- `scripts/score-empirical-results.ps1`
- `TRACKER.md`
- `LICENSE`

## Active Boundaries

- no application source tree;
- no `src/` or application runtime surface;
- no `tests/` surface;
- no CI automation yet;
- no claim that the deterministic verifier proves production safety;
- no model/API eval results or empirical paper claim;
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
- the empirical run-packet scorer passes for the current run-packet schema
  surface;
- the empirical evidence-package validator self-test passes on synthetic
  positive and negative packages;
- the empirical results aggregator self-test passes on a synthetic evidence
  package and rejects an invalid package before aggregation;
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
