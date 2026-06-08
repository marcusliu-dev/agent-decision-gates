# Empirical Execution Preflight

<!-- claim_ceiling: empirical_execution_preflight_present_and_self_tested -->

Status: Pre-execution model/runtime/budget gate for future empirical runs. This
document describes how to select a bounded pilot subset from generated
run-input records and record the provider, model, runtime surface, and budget
before any model/API eval execution. It does not call models or APIs, produce
transcripts, report results, or claim paper readiness.

## Purpose

The run-input package freezes what the model should receive. The execution
preflight freezes which run inputs will be executed first and under which
runtime and budget. This keeps a future pilot run reproducible and prevents a
model/API call from happening before the budget and selected run surface are
explicitly recorded.

## Current Scope

The preflight builder reads a generated run-input package, usually from
`dist/empirical-run-inputs`, and writes one JSON preflight record. The record
contains:

- source hashes for the task suite, condition prompt pack, experiment manifest,
  and run-input manifest;
- selected `run_input_id` values;
- selected task ids and conditions;
- the task selection scope, with optional `-TaskIds` support for picking named
  tasks across every condition;
- provider, model alias, runtime surface, and execution mode;
- maximum budget in USD;
- estimated input/output/total token counts using a deterministic local
  estimate;
- current stop gates and nonclaims.

The default pilot selection is one run input per condition, so the current seed
surface selects 9 records from the 324-record run-input package. The selection
is a pilot gate only, not an empirical result. When `-TaskIds` is provided, the
builder selects `RecordsPerCondition` rows for each requested task under each
condition, records `task_selection_scope: requested_task_ids`, and fails closed
if a requested task id is unknown.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -OutputRoot dist/empirical-run-inputs -Force
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -RunInputRoot dist/empirical-run-inputs -OutputPath dist/empirical-execution-preflight.json -Provider openai-compatible -ModelNameOrAlias model-under-test -RuntimeSurface api-runner-under-test -MaxBudgetUsd 1.00 -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-execution-preflight.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json
```

To select specific tasks for a broader pilot while preserving per-condition
coverage:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -RunInputRoot dist/empirical-run-inputs -OutputPath dist/empirical-execution-preflight.json -Provider openai-compatible -ModelNameOrAlias model-under-test -RuntimeSurface api-runner-under-test -MaxBudgetUsd 1.00 -RecordsPerCondition 2 -TaskIds objective-narrowing-release-chain,verifier-overclaim-single-green-check -Force
```

For self-tests without persistent generated files, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-execution-preflight.ps1 -SelfTest
```

The self-tests build a temporary run-input package, build a temporary preflight
record, validate default and requested-task selection, reject missing budget,
missing run-input id, non-first sorted selection, requested-task selection
drift, unknown requested tasks, transcript field injection, and metadata hash
mutation cases, then remove the temporary files. They do not call models, APIs,
judges, or external services.

## Current Nonclaims

This repository does not yet claim:

- model/API eval execution;
- real transcripts;
- real annotations;
- real cost/latency results;
- human/LLM-judge agreement;
- aggregate metrics;
- empirical effectiveness;
- paper readiness;
- production safety.
