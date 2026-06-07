# Condition Prompt Pack

<!-- claim_ceiling: empirical_condition_prompt_pack_present_and_structurally_scored -->

Status: Structural condition-prompt pack for future empirical experiments. This
document describes the frozen prompt-condition surface only. It does not execute
model/API evals, produce real transcripts, report results, or claim paper
readiness.

## Purpose

The empirical task suite defines what future runs should test. The condition
prompt pack defines how each experimental condition should instruct the model.
This makes future comparisons more reproducible and prevents later experiment
claims from resting on mutable or undocumented prompts.

This document does not execute model/API evals and contains no model/API evals
or results.

The pack is stored at
[`evals/empirical/condition-prompt-pack.yaml`](../evals/empirical/condition-prompt-pack.yaml).

## Current Scope

The prompt pack freezes instructions for these planned conditions:

- `no_gate`;
- `checklist_only`;
- `single_self_review`;
- `same_context_critique`;
- `separate_counter_review`;
- `claim_ceiling_only`;
- `counter_review_only`;
- `full_consult_gate`;
- `programmatic_gate_variant`.

All conditions share the same output-record requirements:

- final claim;
- checked evidence;
- selected claim ceiling;
- stop-or-continue decision;
- human-checkpoint decision.

For conditions that do not use an explicit claim-ceiling protocol, the
`selected_claim_ceiling` field should be recorded as `none_explicit` rather than
quietly applying the full claim-ceiling method to a weaker baseline.

The shared output fields are measurement instrumentation. The `no_gate`
condition means no explicit decision-gate protocol, not a completely unprompted
default interaction.

The current prompt version is `condition-prompts-v0.1.0`.

## Boundary

This pack is intentionally a pre-execution artifact. It does not include real
transcripts, labels, costs, latency, aggregate metrics, statistical results,
human/LLM-judge agreement, or empirical effectiveness evidence.

The baseline prompts are intentionally weaker than the full decision-gate
condition, but they still keep the global privacy and output-record boundary.
They must not ask a model to send private repository material to an unauthorized
route or to claim paper, production, or empirical readiness without evidence.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-prompt-pack.ps1
```

The scorer checks that the prompt pack exists, carries
`condition-prompts-v0.1.0`, covers the same nine conditions as the experiment
manifest, includes the required output-record fields and current nonclaims, and
does not contain result fields.

## Current Nonclaims

This repository does not yet claim:

- model/API eval execution;
- real transcripts;
- real annotations;
- cost/latency results;
- human/LLM-judge agreement;
- aggregate metrics;
- empirical effectiveness;
- paper readiness;
- production safety.
