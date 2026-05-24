# Release Readiness

Status: Published public reference repository with a doc-only verification
surface.

## Purpose

This document records the current public release shape of this repository:
what is present, what has been verified, and what still remains intentionally
out of scope.

## Current Scope

The current public release includes:

- `README.md`
- `TRACKER.md`
- `docs/consult-protocol.md`
- `docs/human-checkpoints.md`
- `docs/verification-and-safety.md`
- `docs/release-readiness.md`
- `docs/provenance.md`
- `examples/consult-stage-gate.md`
- `scripts/verify-public-safety.ps1`
- `LICENSE`

This repository is intentionally doc-first. It does not currently include
application source code, test suites, or CI automation.

## Current Release Claim

The current release claim is narrow and explicit:

- the public repository contains a reusable decision-gate pattern for agentic
  workflows;
- the documentation surface is internally consistent and verifier-backed;
- the current contents are suitable for public reading, reuse, and adaptation
  under `MIT`.

This repository does not claim to be a framework, package, SDK, or deployment
system.

## Verified Evidence

- the deterministic public-safety verifier passes for the current doc-only
  surface;
- required public files and directories are present;
- blocked markers and blocked private leakage terms do not appear;
- relative markdown links resolve;
- `src/` and `tests/` remain absent on the current doc-only surface;
- `LICENSE` and `docs/provenance.md` are present and aligned with the current
  repository state.

## Current Intentional Deferrals

These are intentionally outside the current release scope:

- CI setup;
- executable product scaffolding;
- a package or framework distribution surface;
- deployment automation;
- any claim that a doc-only verifier proves production safety.

## Interpretation Rule

If the repository later adds code, tests, CI, or runtime integrations, this
document should be updated together with the real verification surface before
making broader claims.
