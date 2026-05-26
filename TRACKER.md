# Agent Decision Gates Tracker

Status: Current repository surface includes docs plus a reusable `$consult`
skill package for evidence-first decision gates in AI-agent workflows.

## Current Claim Ceiling

`public_consult_skill_package_present_and_verifier_backed`

Current evidence proves that this repository is publicly visible at
`https://github.com/marcusliu-dev/agent-decision-gates`, that the current
repository surface contains a reusable skill package under `skills/consult/`,
that public eval fixtures exist under `evals/consult/`, that the deterministic
public-safety verifier passes for the current repository surface, and that the
materials in this repository are aligned with that surface. The eval claim is
bounded to fixture presence plus structural validation, not full runtime
execution. No broader claim is made for package-manager distribution,
executable framework behavior beyond the current skill package, CI coverage,
deployment safety, or production runtime guarantees.

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
- `skills/consult/SKILL.md`
- `skills/consult/agents/openai.yaml`
- `evals/consult/consult-public-happy-path.yaml`
- `evals/consult/consult-public-nonlocal-route-forbidden.yaml`
- `evals/consult/consult-public-must-counter-review.yaml`
- `evals/consult/consult-public-must-reclaim-thread-capacity-before-inline-fallback.yaml`
- `docs/consult-protocol.md`
- `docs/human-checkpoints.md`
- `docs/verification-and-safety.md`
- `docs/release-readiness.md`
- `docs/provenance.md`
- `examples/consult-stage-gate.md`
- `scripts/verify-public-safety.ps1`
- `TRACKER.md`
- `LICENSE`

## Active Boundaries

- no application source tree;
- no `src/` or application runtime surface;
- no `tests/` surface;
- no CI automation yet;
- no claim that the deterministic verifier proves production safety;
- no package-manager or registry publication surface;
- no claim that this repository is a full framework, SDK, or deployment
  system.

## Verification Snapshot

- the deterministic public-safety verifier passes for the current doc, skill,
  and eval surface;
- required public files, directories, skill files, and eval fixtures are
  present;
- the public eval fixtures are structurally validated as golden, misuse, and
  trajectory artifacts;
- the skill remains explicit-use only and its config disables implicit
  invocation;
- blocked private leakage terms do not appear;
- relative markdown links resolve;
- the repository remains intentionally documentation-first plus a lightweight
  skill package.
