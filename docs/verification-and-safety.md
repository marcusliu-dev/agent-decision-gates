# Verification And Safety

## Core Rule

Do not make a readiness or completion claim without fresh evidence that matches
the scope of the claim.

This repository's main verifier is deterministic. A passing public-surface
integrity verifier plus fresh readback can prove the integrity of the current
documentation, skill, and public eval surface. It does not, by itself, prove
broader operational safety, deployment safety, empirical effectiveness, or
product correctness outside that surface.

## Match Evidence To Scope

Use the narrowest verification surface that truly proves the current stage:

- real tests for executable behavior when code exists;
- readback of created or updated files;
- structure checks;
- skill-config and explicit-invocation policy checks;
- denylist or placeholder scans;
- path and route checks;
- cross-file consistency checks;
- explicit confirmation that blocked actions did not occur.

A narrow check may support a narrow claim. It should not be stretched into a
broader release, deployment, or risk-acceptance claim.

Conservative wording is allowed. For example, a README may keep a narrower
claim ceiling than the tracker. What is not allowed is any file claiming a
broader state than the tracker and current verifier evidence support.

## Stage-Based Verification

- A skeleton stage can rely on a minimal safety script if it checks the actual
  skeleton surface.
- A drafting stage should use readback, denylist scans, and cross-file
  consistency checks.
- A doc-only verifier should expand only as far as the real doc-only surface
  requires.
- The verifier in this repository checks:
  - required public files and directories exist;
  - the installable skill package and public eval fixtures exist;
  - the skill remains explicit-use only;
  - core consult invariants appear in the public skill text;
  - blocked markers and blocked private leakage terms do not appear;
  - relative markdown links resolve;
  - claim-bearing release surfaces carry machine-readable claim-ceiling
    metadata and do not claim a broader state than `TRACKER.md`;
  - the repository remains free of unexpected executable scaffolding such as
    `src/` and `tests/`.
- Broader verification belongs to the broader surface. If you add code, CI, or
  deployment behavior, add real tests for those surfaces instead of pretending
  the doc-only verifier covers them.

## Safety Rules

- keep claims narrower than the evidence;
- keep drafts separate from public-ready artifacts when the repo is not yet
  public;
- treat missing fields as blockers;
- prefer deterministic checks over assumptions;
- record residual risks explicitly;
- fail closed when a required grant, independent consult, or verification route
  is missing.

If a verifier expansion would require a new file or surface that is not already
authorized, stop and re-checkpoint before writing it.

## Recommended Verification Sequence

1. Read back the changed files.
2. Run the nearest real verifier already in scope.
3. Run any stage-specific denylist or consistency checks.
4. Verify any public route or consumer surface that materially changes the
   claim.
5. State the exact claim ceiling supported by the evidence.

## Current Repository Surface

The live verifier in this repository is intentionally limited to the current
public reference, skill-package, and eval-fixture surface. It is useful
because it is honest about what it can and cannot prove.

It can support integrity claims about the current public repository surface. It
does not replace broader verification for code, CI, deployment,
infrastructure, empirical effectiveness, or high-risk external actions.
