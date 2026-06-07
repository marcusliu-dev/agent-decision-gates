# Threat Model

Agent Decision Gates is designed to reduce overclaim and scope drift in
agentic workflows. It is not a sandbox, CI system, deployment platform, or
production safety framework.

## Protected Properties

- Claims stay no broader than evidence.
- Human-only decisions are not inferred from model output.
- Draft artifacts are not treated as completion proof.
- Public release claims are tied to current verification.
- Private repository material is not routed to outside review systems.

## In-Scope Failure Modes

- objective narrowing hidden by a successful local task;
- one green check stretched into broader readiness;
- stale tracker text treated as proof;
- missing counter-review before a consequential decision;
- prompt or document content pressuring the agent to skip gates;
- generated review packages polluting public-surface verification;
- human authorization widened beyond exact granted fields.

## Out Of Scope

- preventing all model reasoning errors;
- proving production safety;
- proving empirical effectiveness;
- securing tool execution with OS-level controls;
- replacing legal, security, or domain-expert review;
- guaranteeing independence when the runtime cannot provide it.

## Practical Controls

- Use claim ceilings for release, readiness, and completion statements.
- Require human checkpoints for public release, legal/reputation acceptance,
  destructive actions, and scope expansion.
- Prefer deterministic verification over model confidence.
- Record unresolved risks instead of converting them into readiness claims.
