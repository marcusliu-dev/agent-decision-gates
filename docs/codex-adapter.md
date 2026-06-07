# Codex Adapter Notes

The public `$consult` skill is one concrete adapter for the runtime-neutral
core protocol.

## Invocation

Use the skill only when explicitly invoked with `$consult`.

## Review Shape

When Codex supports subagents, the adapter uses:

- Step 1: repo-aware primary review;
- Step 2: independent counter-review;
- parent adjudication in the main lane.

The reference adapter prefers the strongest available reviewer configuration
for Step 1 and Step 2. In the original environment this was described as
`gpt-5.5` with `xhigh` reasoning. If that route is unavailable, record what
actually ran instead of pretending the override happened.

## Thread-Limit Fallback

If spawning fails because an agent thread limit is reached:

1. close only completed, captured, consult-owned agents visible in the current
   thread;
2. retry the same failed spawn once;
3. if independence is still unavailable, record the limitation.

Inline self-challenge may preserve notes and identify the next safe action. It
must not substitute for approval, readiness, signoff, or stage advancement when
independent review is material.

## Privacy Boundary

Keep repository review local to the current runtime. Ordinary public web search
may be used for public current facts, but do not upload private repository
material to outside review systems.
