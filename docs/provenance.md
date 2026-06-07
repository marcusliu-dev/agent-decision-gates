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
| `evals/empirical/transcript-schema.yaml` | Written locally as a public transcript schema for future experiment runs, with no transcripts. |
| `evals/empirical/annotation-schema.yaml` | Written locally as a public annotation schema for future human or judge labels, with no labels. |
| `evals/empirical/evidence-package-schema.yaml` | Written locally as a public evidence-package schema for future experiment outputs, with no transcripts, labels, or results. |
| `docs/consult-protocol.md` | Written locally as public-facing protocol guidance and updated to align with the installable consult skill package. |
| `docs/core-protocol.md` | Written locally as runtime-neutral protocol guidance for adopters outside the original Codex environment. |
| `docs/codex-adapter.md` | Written locally to isolate Codex-specific adapter behavior from the runtime-neutral pattern. |
| `docs/deep-dive-report.md` | Written locally as a public design-pattern report explaining claim ceilings, decision gates, verification boundaries, and the empirical paper path. |
| `docs/empirical-evaluation-plan.md` | Written locally as a public experiment-design plan for future empirical paper work, with explicit no-results and no-paper-readiness boundaries. |
| `docs/experiment-run-packet.md` | Written locally as a public run-packet specification for freezing future experiment artifacts before model/API eval execution. |
| `docs/empirical-evidence-package.md` | Written locally as a public evidence-package validation guide for future post-run completeness checks, with no executed experiment evidence. |
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
| `scripts/score-empirical-evidence-package.ps1` | Written locally as a dependency-free deterministic validator and synthetic self-test route for future empirical evidence packages. |
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
