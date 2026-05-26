---
name: consult
description: >-
  Use when explicitly invoked with $consult for high-stakes local review,
  decision support, route-readiness checks, or completion-claim challenge
  passes.
---

# Consult

## Authority And Scope

This skill is an execution adapter, not a decision authority. If it conflicts
with a governing repo instruction, task packet, stop gate, or narrower active
policy, the narrower active source wins.

Use `$consult` only when explicitly invoked. Keep review and adjudication local
to your current runtime with repository access when possible. Do not route local repository material to non-local AI systems or prepare outside-submission bundles.

The `gpt-5.5` + `xhigh` guidance below is a per-spawn override scoped only to
`$consult`'s own internal Step 1 and Step 2 spawned agents. It does not change
the parent lane, global defaults, non-consult defaults, or any other skill's
model or reasoning-effort behavior.

`$consult` may use ordinary current-source search when public current facts are
needed. Search is an evidence tool, not a decision-maker. Use sanitized,
generic public queries and avoid disclosing private repo details.

## Core Principle

Local evidence before advice; independent local challenge before adjudication.

The purpose of `$consult` is to prevent parent-thread framing errors, stale
source assumptions, objective narrowing, and unverified readiness claims inside
the local repository.

## Core Protocol

Every explicit `$consult` run requires:

1. Frame the task.
   - Record the raw user request or faithful excerpt.
   - Lock the decision question and acceptance criteria.
   - Separate verified facts from parent assumptions.
   - List the source map, privacy boundary, and unchecked uncertainties.
2. Inspect local evidence.
   - Read the smallest governing sources that can settle the question.
   - Prefer targeted readback, counts, manifests, rendered artifacts, or
     current-source proof over memory.
3. Run local Step 1.
   - Use a repo-aware primary analysis in an independent spawned context when
     your runtime supports subagents and the skill has been explicitly invoked.
   - When runtime exposes explicit spawn overrides, spawn the Step 1 internal
     agent with model `gpt-5.5` and reasoning effort `xhigh`.
   - If `gpt-5.5` is unavailable or the runtime rejects the override, continue
     the internal consult lane with the runtime-selected model and effort,
     record the actual values, and do not compensate by changing parent,
     global, or other-skill defaults.
   - Require findings, evidence, source-map review, and a local
     route/search/runtime/privacy matrix.
4. Run local Step 2.
   - Use a separate counter-review in an independent spawned context.
   - When runtime exposes explicit spawn overrides, spawn the Step 2 internal
     agent with model `gpt-5.5` and reasoning effort `xhigh`.
   - If `gpt-5.5` is unavailable or the runtime rejects the override, continue
     the internal consult lane with the runtime-selected model and effort,
     record the actual values, and do not compensate by changing parent,
     global, or other-skill defaults.
   - Challenge Step 1, parent framing, stale sources, overclaims, and whether
     a narrower safe answer is required.
5. Parent adjudicates.
   - Accept, reject, or modify the internal findings.
   - State local evidence sufficiency.
   - Return a bounded answer, `not_ready`, `needs_human_checkpoint`,
     `current_state_conflict`, or `source_gap_unresolved`.

## Role-Bounded Internal Prompts

If a prompt assigns this run as `local_codex_primary`, `local_codex_counter_review`,
`Step 1 primary reviewer`, or `Step 2 counter-reviewer`, perform only that
assigned role.

For role-bounded internal prompts:

- do not recursively run the full consult protocol;
- do not issue final parent adjudication;
- mark the output `parent_adjudication_pending`;
- state what local sources were checked and what remains for the parent.

If a role-bounded prompt conflicts with the parent task, report the conflict
instead of silently expanding scope.

## Independence Fallback

If subagents cannot be launched, first distinguish `agent thread limit
reached` from other spawn failures.

On `agent thread limit reached`, attempt bounded current-thread capacity
hygiene before inline fallback:

- inspect only agents visible in the current thread;
- close only agents that are clearly `$consult`-owned and already completed,
  failed, superseded, or explicitly abandoned for the current consult purpose,
  and only after their outputs have already been captured;
- record the reclaimed agent IDs and close outcomes when this reclaim path is
  used; and
- retry the same failed Step 1 or Step 2 spawn once with the same role,
  prompt, privacy boundary, and per-spawn override request.

Never close the parent lane, active agents, ambiguous agents, non-consult
agents, user-owned or unrelated agents, or any agent whose evidence has not
yet been captured. Do not loop repeated reclaim attempts.

If no safe-to-close consult-owned agent is visible, `close_agent` is
unavailable or rejected, or the single retry still fails, say so and run the
strongest possible inline primary plus self-challenge. Do not pretend that
inline self-challenge is independent evidence.

If subagents launch but the `gpt-5.5` override is unavailable or rejected,
record the actual Step 1/Step 2 model and reasoning effort instead of
pretending the override happened. Do not change parent, global, or other-skill
defaults to satisfy the `$consult` override.

When independent review is unavailable, set `Local evidence sufficiency:
limited` or `independence_unavailable`. Do not issue `ready`, `approved`,
`signoff`, or equivalent claims when independence materially matters.

## Local Route Matrix

Use only these route labels:

| Route | Meaning |
| --- | --- |
| `local_codex_primary` | First local repo-aware analysis. |
| `local_codex_counter_review` | Separate local challenge pass. |
| `ordinary_current_source_search` | Sanitized public web search for current facts, not an outside review route. |
| `local_readback` | File, tracker, schema, line-count, hash, manifest, render, or artifact readback. |
| `human_checkpoint` | Ask the human for a decision when local evidence cannot settle the issue safely. |

Non-local AI routes and outside submissions are out of scope.

## Risk Gates

### Parent-Framing Gate

Before relying on the parent thread, check for:

- leading assumptions;
- missing governing files;
- stale tracker or current-state surfaces;
- raw objective narrowed into a smaller stage;
- omitted privacy, source, or acceptance criteria.

If the source map is incomplete and the missing source could change the answer,
return `source_gap_unresolved` or ask for a human checkpoint.

### P0 And Readiness Gate

Before any readiness, signoff, route-ready, send-ready, material-ready,
recovery-ready, or completion claim:

- lock the claim and critical invariant;
- identify the consumer, actor, intended route, suspect surface, and evidence
  route;
- verify through a route independent of the suspect surface when possible;
- fail closed as `not_ready` if the invariant cannot be checked.

Producer-side file existence is not enough for material readiness. Use
readback, manifest, route reachability, or consumer-context evidence.

### Full-Chain Narrowing Gate

When the question concerns broad completion, objective drift, repeated manual
relay, stale current state, or a large workflow, map the chain:

- raw user request;
- current tracker or stop gate;
- task packet or plan;
- review prompts and subagent prompts;
- artifacts, readback, and provenance;
- omitted obligations and continuation conditions.

Do not claim broad completion from a stage-local artifact.

### Current Objective Gate

When deciding what to continue or reopen, classify plausible objectives as
`current`, `superseded`, `stale`, `bounded_stage`, `evidence_only`,
`blocked_true_gate`, or `current_state_conflict`. Select the umbrella
objective before selecting the runtime step.

### Policy And Harness Gate

For skill, eval, policy, or prompt changes:

- separate durable invariant from dated or tool-specific facts;
- put concrete failure prompts in evals, not broad policy;
- avoid teaching only the observed prompt;
- prefer held-out, adversarial, and trajectory checks.

### Repeated Local Failure Gate

After repeated same-family failures, do not keep looping in the same way.
Expand local evidence, rebuild the source map, use a fresh counter-review, run
ordinary current-source search when public facts matter, or return `not_ready`
or `needs_human_checkpoint`.

## Output Shape

Use the compact form below unless the user requests another format:

```text
Task class:
Privacy class:
Repository access:
Current-source search:
Internal local review:
Acceptance criteria:
P0/readiness gate:
Parent framing:
Full-chain/current-objective state:
Local evidence checked:
Local evidence sufficiency:
Internal Step 1:
Internal Step 2:
Parent adjudication:
Route/search/runtime/privacy matrix:
Ledger/run-log:
Stop gates:
Next safe local action:
Rationale:
```

When independent Step 1 or Step 2 runs, include the actual model and reasoning
effort used in those fields, or state that the run was inline or
override-limited.

## Verification And Run-Log

Record a privacy-safe run note when the host repo defines an appropriate path.
If no safe durable path exists, state that no run-log path is available rather
than pretending one exists.

Before saying a consult result is ready or complete, read back the files or
evidence supporting the claim and state the exact verification performed.

## Boundaries

STOP and refuse when asked to:

- use non-local AI systems or outside submission routes;
- upload, submit, or prepare local repository material for outside systems;
- skip the local counter-review for urgency or authority;
- claim readiness without current evidence;
- treat a stale tracker, parent assertion, or agent report as proof;
- treat a human-only checkpoint as satisfied without explicit approval;
- broaden a granted surface without reopening the checkpoint.

## Bottom Line

`$consult` is a local evidence and counter-review gate. The execution lane is
not the decision lane: it prepares evidence and implements bounded work, while
`$consult` governs stage decisions inside already granted envelopes without
changing the fixed final target.
