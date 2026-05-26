# Provenance

Status: Public-surface provenance recorded for the current published
repository.

## Purpose

This document records provenance for the files currently present in this
repository and the source boundaries used to keep the public surface generic.

## Public-Surface Provenance Summary

| surface | provenance |
| --- | --- |
| `README.md` | Written locally as public-facing overview text for this repository and updated to include the installable consult skill package. |
| `skills/consult/SKILL.md` | Written locally as a public-safe adaptation of an internal consult workflow, with private paths, private trackers, and local-only boundaries removed. |
| `skills/consult/agents/openai.yaml` | Written locally as a public skill config for explicit `$consult` invocation. |
| `evals/consult/consult-public-happy-path.yaml` | Written locally as a public golden eval fixture for the consult skill. |
| `evals/consult/consult-public-nonlocal-route-forbidden.yaml` | Written locally as a public misuse eval fixture for the consult skill. |
| `evals/consult/consult-public-must-counter-review.yaml` | Written locally as a public trajectory eval fixture for the consult skill. |
| `evals/consult/consult-public-must-reclaim-thread-capacity-before-inline-fallback.yaml` | Written locally as a public trajectory eval fixture for the consult skill's bounded thread-limit fallback behavior. |
| `docs/consult-protocol.md` | Written locally as public-facing protocol guidance and updated to align with the installable consult skill package. |
| `docs/human-checkpoints.md` | Written locally as public-facing checkpoint guidance and updated to align with public skill publication/update workflows. |
| `docs/verification-and-safety.md` | Written locally as public-facing verification guidance matched to the current doc-plus-skill surface. |
| `examples/consult-stage-gate.md` | Written locally as a fictional example for this repository. |
| `scripts/verify-public-safety.ps1` | Written locally as a deterministic verifier for this repository's current public doc, skill, and eval surface. |
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
