# Agent Decision Gates

Evidence-first decision gates for AI agents: independent challenge reviews,
human checkpoints, and verification before high-risk actions.

This repository packages both a public decision-gate reference and a reusable
`$consult` skill for teams that want stronger decision discipline around
AI-agent workflows. It is designed for moments when a model or execution lane
is about to make an expensive decision: publish, ship, claim completion,
expand scope, accept risk, or act on ambiguous evidence.

## Why This Exists

Many agent workflows fail in the same way:

- execution silently narrows the real goal;
- one green check gets stretched into a broader readiness claim;
- a draft artifact gets mistaken for proof of completion;
- no one clearly owns the final risky decision.

This repo packages a simple alternative:

1. Frame the real decision question.
2. Gather the smallest sufficient evidence.
3. Run a primary analysis.
4. Run an independent challenge pass.
5. Make a bounded adjudication and record what remains blocked.

## Who This Is For

- teams running AI agents against real repositories or operations workflows;
- developers building human-in-the-loop controls for agentic systems;
- researchers who want explicit decision and verification boundaries;
- anyone who needs claims to stay narrower than the evidence.

## What You Get

- an installable [`$consult` skill package](skills/consult/SKILL.md);
- a machine-readable skill config in
  [`skills/consult/agents/openai.yaml`](skills/consult/agents/openai.yaml);
- public eval fixtures under [`evals/consult/`](evals/consult/);
- a reusable [consult protocol](docs/consult-protocol.md);
- [human checkpoint rules](docs/human-checkpoints.md) for high-risk actions;
- [verification guidance](docs/verification-and-safety.md) for keeping claims
  aligned with evidence;
- a fictional [stage-gate example](examples/consult-stage-gate.md);
- a lightweight local verifier in
  [`scripts/verify-public-safety.ps1`](scripts/verify-public-safety.ps1);
- a small [tracker](TRACKER.md) and [release record](docs/release-readiness.md)
  for keeping state honest.

## Quick Start

If you want to install the skill package:

```text
scripts/install-skill-from-github.py --repo marcusliu-dev/agent-decision-gates --path skills/consult
```

This is the GitHub repo/path install route used by Codex's `skill-installer`
helper. After installation, restart Codex and invoke the skill explicitly with
`$consult`.

If you want to adapt the underlying pattern:

1. Write down the exact decision question.
2. Separate verified facts from assumptions.
3. Read only the smallest live surfaces that can answer the question.
4. Run a primary pass and an independent challenge pass.
5. Record what is allowed now, what is still blocked, and the exact claim
   ceiling supported by the evidence.

For decision-bearing consults, the reference workflow prefers independent
spawned agents at the strongest model and highest reasoning effort your runtime
supports. In the example workflow here, that means `gpt-5.5` with `xhigh`
when available. If your runtime cannot supply that route, record what actually
ran and fail closed when independence materially matters.

## Repository Guide

- Start with [`skills/consult/SKILL.md`](skills/consult/SKILL.md) if you want
  the installable skill artifact.
- Start with [docs/consult-protocol.md](docs/consult-protocol.md).
- Then read [docs/human-checkpoints.md](docs/human-checkpoints.md).
- Use [docs/verification-and-safety.md](docs/verification-and-safety.md) to
  match claims to evidence.
- Read [examples/consult-stage-gate.md](examples/consult-stage-gate.md) for a
  compact worked example.
- See [docs/provenance.md](docs/provenance.md) for authorship and source
  boundaries.

## Design Principles

- Evidence first.
- Execution and decision authority are separate concerns.
- Human-only gates stay explicit for high-risk actions.
- Independence matters when the decision is consequential.
- A narrow verifier can support only a narrow claim.

## Project Status

This is a published public repository with a reusable `$consult` skill package,
public eval fixtures, documentation, and one deterministic verifier under
`MIT`. It intentionally does not ship CI, deployment automation, application
source scaffolding, or a broader framework/runtime product surface.

If this pattern is useful in your own agent workflows, adapt it, improve it,
and make the decision boundaries explicit in your own systems.
