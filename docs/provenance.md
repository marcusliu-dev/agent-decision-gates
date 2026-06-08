# Provenance

Status: Public-surface provenance recorded for the current published
repository.

## Purpose

This document records provenance for the files currently present in this
repository and the source boundaries used to keep the public surface generic.

## Public-Surface Provenance Summary

| surface | provenance |
| --- | --- |
| `.gitignore` | Written locally to keep generated review-package output such as `dist/` out of the public repository surface. |
| `README.md` | Written locally as public-facing overview text for this repository and updated to include the installable consult skill package. |
| `skills/consult/SKILL.md` | Written locally as a public-safe adaptation of an internal consult workflow, with private paths, private trackers, and local-only boundaries removed. |
| `skills/consult/agents/openai.yaml` | Written locally as a public skill config for explicit `$consult` invocation. |
| `evals/consult/consult-public-happy-path.yaml` | Written locally as a public golden eval fixture for the consult skill. |
| `evals/consult/consult-public-nonlocal-route-forbidden.yaml` | Written locally as a public misuse eval fixture for the consult skill. |
| `evals/consult/consult-public-must-counter-review.yaml` | Written locally as a public trajectory eval fixture for the consult skill. |
| `evals/consult/consult-public-must-reclaim-thread-capacity-before-inline-fallback.yaml` | Written locally as a public trajectory eval fixture for the consult skill's bounded thread-limit fallback behavior. |
| `evals/consult/consult-public-objective-narrowing-full-chain.yaml` | Written locally as a public trajectory eval fixture for objective narrowing. |
| `evals/consult/consult-public-verifier-overclaim.yaml` | Written locally as a public misuse eval fixture for verifier overclaim. |
| `evals/consult/consult-public-draft-artifact-not-completion.yaml` | Written locally as a public misuse eval fixture for draft/completion confusion. |
| `evals/consult/consult-public-stale-tracker-conflict.yaml` | Written locally as a public trajectory eval fixture for stale tracker conflict. |
| `evals/consult/consult-public-approval-spoofing.yaml` | Written locally as a public misuse eval fixture for approval spoofing. |
| `evals/consult/consult-public-prompt-injection-in-reviewed-file.yaml` | Written locally as a public misuse eval fixture for prompt injection inside reviewed content. |
| `evals/consult/consult-public-multiturn-scope-creep.yaml` | Written locally as a public trajectory eval fixture for multi-turn scope creep. |
| `evals/consult/consult-public-subtle-nonlocal-route-pressure.yaml` | Written locally as a public misuse eval fixture for subtle non-local route pressure. |
| `evals/consult/consult-public-unsafe-thread-reclaim.yaml` | Written locally as a public trajectory eval fixture for unsafe thread reclaim. |
| `evals/consult/consult-public-parent-framing-conflict.yaml` | Written locally as a public trajectory eval fixture for parent-framing conflict. |
| `evals/empirical/agent-decision-gates-task-suite.yaml` | Written locally as a public seed empirical task suite for future reproducible experiments, with no model results. |
| `evals/empirical/experiment-run-manifest.yaml` | Written locally as a public run-packet manifest schema for future empirical experiments, with no model results. |
| `evals/empirical/condition-prompt-pack.yaml` | Written locally as a public condition prompt pack for future empirical experiments, with no model/API execution or results. |
| `evals/empirical/run-input-schema.yaml` | Written locally as a public run-input schema for future empirical experiments, with no model/API execution or results. |
| `evals/empirical/execution-preflight-schema.yaml` | Written locally as a public execution-preflight schema for recording future pilot selection, runtime, and budget metadata before model/API execution, with no model/API calls or results. |
| `evals/empirical/mock-execution-package-schema.yaml` | Written locally as a public mock execution package schema for synthetic transcript and cost-latency package joins before model/API execution, with no real model results. |
| `evals/empirical/pilot-execution-package-schema.yaml` | Written locally as a public pilot execution package schema for explicit local-runner transcript and cost-latency packages, with no labels, metrics, or paper-readiness claim. |
| `evals/empirical/annotation-worklist-schema.yaml` | Written locally as a public annotation worklist schema for deriving unlabeled future-labeling work items from pilot execution packages, with no labels, agreement metrics, aggregate results, or paper-readiness claim. |
| `evals/empirical/label-template-package-schema.yaml` | Written locally as a public label-template package schema for deriving fillable placeholder templates from annotation worklists, with no completed labels, agreement metrics, aggregate results, or paper-readiness claim. |
| `evals/empirical/transcript-schema.yaml` | Written locally as a public transcript schema for future experiment runs, with no transcripts. |
| `evals/empirical/annotation-schema.yaml` | Written locally as a public annotation schema for future human or judge labels, with no labels. |
| `evals/empirical/evidence-package-schema.yaml` | Written locally as a public evidence-package schema for future experiment outputs, with no transcripts, labels, or results. |
| `evals/empirical/results-summary-schema.yaml` | Written locally as a public results-summary schema for future post-package aggregation, with no real aggregate metrics and no raw local package path requirement. |
| `evals/empirical/agreement-summary-schema.yaml` | Written locally as a public agreement-summary schema for future human-vs-LLM-judge agreement checks, with no real labels or agreement results. |
| `docs/consult-protocol.md` | Written locally as public-facing protocol guidance and updated to align with the installable consult skill package. |
| `docs/core-protocol.md` | Written locally as runtime-neutral protocol guidance for adopters outside the original Codex environment. |
| `docs/codex-adapter.md` | Written locally to isolate Codex-specific adapter behavior from the runtime-neutral pattern. |
| `docs/deep-dive-report.md` | Written locally as a public design-pattern report explaining claim ceilings, decision gates, verification boundaries, and the empirical paper path. |
| `docs/empirical-evaluation-plan.md` | Written locally as a public experiment-design plan for future empirical paper work, with explicit no-results and no-paper-readiness boundaries. |
| `docs/experiment-run-packet.md` | Written locally as a public run-packet specification for freezing future experiment artifacts before model/API eval execution. |
| `docs/condition-prompt-pack.md` | Written locally as public documentation for the condition prompt pack and its no-results boundary. |
| `docs/empirical-run-inputs.md` | Written locally as public documentation for reproducible pre-execution run-input package generation, with no model/API execution or results. |
| `docs/empirical-execution-preflight.md` | Written locally as public documentation for execution preflight records that freeze pilot selection, provider/model/runtime, and budget before model/API execution, with no model/API calls or results. |
| `docs/empirical-mock-execution-package.md` | Written locally as public documentation for synthetic mock transcript and cost-latency package generation, with no model/API calls or real results. |
| `docs/empirical-pilot-execution-runner.md` | Written locally as public documentation for an explicit local-runner route that keeps private runner code and credentials outside this public repository. |
| `docs/empirical-annotation-worklist.md` | Written locally as public documentation for unlabeled annotation worklist generation from pilot execution packages, with no human labels, LLM-judge labels, agreement measurements, or aggregate metrics. |
| `docs/empirical-label-template-package.md` | Written locally as public documentation for label-template package generation from annotation worklists, with placeholders only and no completed labels, agreement measurements, or aggregate metrics. |
| `docs/empirical-annotation-guidelines.md` | Written locally as public annotation rubric guidance for future human, LLM-judge, and rule-based labels, with no real labels or agreement results. |
| `docs/empirical-evidence-package.md` | Written locally as a public evidence-package validation guide for future post-run completeness checks, with no executed experiment evidence. |
| `docs/empirical-results-analysis.md` | Written locally as a public results-analysis guide for future metric aggregation after evidence-package validation, with no real experiment results. |
| `docs/empirical-agreement-checks.md` | Written locally as a public agreement-checks guide for future human-vs-LLM-judge comparisons, with no real agreement or judge-validity claim. |
| `docs/empirical-dry-run-package.md` | Written locally as a public synthetic dry-run package guide for exercising validators without model/API eval execution or real results. |
| `docs/eval-evidence.md` | Written locally to describe the deterministic fixture scorer and its evidence boundary. |
| `docs/glossary.md` | Written locally to define public terms such as claim ceiling, parent framing, and human checkpoint. |
| `docs/human-checkpoints.md` | Written locally as public-facing checkpoint guidance and updated to align with public skill publication/update workflows. |
| `docs/roles-and-permissions.md` | Written locally as a compact role/authority matrix for adopters. |
| `docs/threat-model.md` | Written locally to state protected properties, in-scope failures, and out-of-scope safety claims. |
| `docs/verification-and-safety.md` | Written locally as public-facing verification guidance matched to the current doc-plus-skill surface. |
| `examples/consult-stage-gate.md` | Written locally as a fictional example for this repository. |
| `scripts/verify-public-safety.ps1` | Written locally as a deterministic public-surface integrity verifier for this repository's current public doc, skill, and eval surface. |
| `scripts/score-eval-fixtures.ps1` | Written locally as a dependency-free deterministic scorer for the public consult eval fixture surface. |
| `scripts/score-empirical-task-suite.ps1` | Written locally as a dependency-free deterministic structural scorer for the public empirical task-suite seed. |
| `scripts/score-empirical-run-packet.ps1` | Written locally as a dependency-free deterministic structural scorer for the public empirical run packet. |
| `scripts/score-empirical-prompt-pack.ps1` | Written locally as a dependency-free deterministic structural scorer for the public empirical condition prompt pack. |
| `scripts/build-empirical-run-inputs.ps1` | Written locally as a dependency-free deterministic builder for public pre-execution empirical run-input packages. |
| `scripts/score-empirical-run-inputs.ps1` | Written locally as a dependency-free deterministic structural scorer for generated empirical run-input packages. |
| `scripts/build-empirical-execution-preflight.ps1` | Written locally as a dependency-free deterministic builder for public pre-execution pilot selection, runtime, and budget records. |
| `scripts/score-empirical-execution-preflight.ps1` | Written locally as a dependency-free deterministic structural scorer for empirical execution preflight records and their no-results boundary. |
| `scripts/build-empirical-mock-execution-package.ps1` | Written locally as a dependency-free deterministic builder for synthetic mock transcript and cost-latency packages, with no model/API calls. |
| `scripts/score-empirical-mock-execution-package.ps1` | Written locally as a dependency-free deterministic structural scorer for synthetic mock execution packages and their no-results boundary. |
| `scripts/build-empirical-pilot-execution-package.ps1` | Written locally as a dependency-free builder for transcript and cost-latency packages produced through explicitly allowed local runner scripts, with no embedded credentials or provider-specific public adapter. |
| `scripts/score-empirical-pilot-execution-package.ps1` | Written locally as a dependency-free structural scorer for pilot execution packages and their no-labels/no-metrics/no-paper-readiness boundary. |
| `scripts/build-empirical-annotation-worklist.ps1` | Written locally as a dependency-free builder for unlabeled annotation worklists derived from pilot execution packages and the public annotation guidelines. |
| `scripts/score-empirical-annotation-worklist.ps1` | Written locally as a dependency-free structural scorer for annotation worklists and their no-labels/no-metrics/no-paper-readiness boundary. |
| `scripts/build-empirical-label-template-package.ps1` | Written locally as a dependency-free builder for placeholder label-template packages derived from annotation worklists and the public annotation schema. |
| `scripts/score-empirical-label-template-package.ps1` | Written locally as a dependency-free structural scorer for label-template packages and their no-completed-labels/no-metrics/no-paper-readiness boundary. |
| `scripts/score-empirical-evidence-package.ps1` | Written locally as a dependency-free deterministic validator and synthetic self-test route for future empirical evidence packages. |
| `scripts/score-empirical-results.ps1` | Written locally as a dependency-free deterministic results aggregator and synthetic self-test route for future validated empirical evidence packages. |
| `scripts/score-empirical-agreement.ps1` | Written locally as a dependency-free deterministic human-vs-LLM-judge agreement checker and synthetic self-test route for future validated empirical evidence packages. |
| `scripts/build-empirical-dry-run-package.ps1` | Written locally as a dependency-free deterministic synthetic dry-run package builder that exercises existing empirical validators without model/API calls. |
| `TRACKER.md` | Written locally as the bounded outside-repo stage ledger for this repository. |
| `docs/release-readiness.md` | Written locally as the release-state record for this repository. |
| `docs/provenance.md` | Written locally as the provenance record for this repository. |
| `LICENSE` | Standard MIT license text added after explicit human choice of `MIT`. |

## Source Boundaries

- This repository is intended to contain generic public material only.
- Private repository paths, private trackers, private prompts, unpublished
  material, and frozen third-party source are out of scope for public
  carryover.
- If a future release adds a materially different artifact type or external
  source dependency, update this document before making broader provenance or
  readiness claims.

## Provenance Gaps

No unresolved provenance gap is currently known for the files listed above.

If a future gap is found, record it here rather than silently broadening the
claim ceiling.
