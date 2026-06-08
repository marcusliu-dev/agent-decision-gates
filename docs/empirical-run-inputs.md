# Empirical Run Inputs

<!-- claim_ceiling: empirical_run_input_builder_present_and_self_tested -->

Status: Pre-execution run-input package route for future empirical experiments.
This document describes how to materialize fixed input records from the public
task suite and condition prompt pack. It does not execute model/API evals,
produce transcripts, report results, or claim paper readiness.

## Purpose

The empirical task suite defines what to test, and the condition prompt pack
defines how each condition should instruct the model. The run-input builder
combines those surfaces into immutable JSON input records before any model/API
run. This makes later transcripts traceable to exact task, condition, repeat,
prompt, and hash evidence.

## Current Scope

The builder reads:

- [`agent-decision-gates-task-suite.yaml`](../evals/empirical/agent-decision-gates-task-suite.yaml);
- [`condition-prompt-pack.yaml`](../evals/empirical/condition-prompt-pack.yaml);
- [`experiment-run-manifest.yaml`](../evals/empirical/experiment-run-manifest.yaml).

It writes:

- one `run-inputs/*.json` file per task, condition, and repeat;
- metadata hash records for the task suite, prompt pack, and manifest;
- a run-input manifest with the builder version, record count, condition count,
  task count, repeat count, and current nonclaims.

Use `dist/empirical-run-inputs` as the default local package root for manual
builds. `dist/` is ignored by this repository so generated JSON packages do not
become part of the public source surface by accident.

With the current public seed surfaces, the expected package contains 324
run-input records: 12 tasks, 9 conditions, and 3 repeats.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-run-inputs.ps1 -SelfTest
```

The self-tests generate a temporary run-input package, verify the expected
record count and hashes, reject packages with missing inputs, and remove the
temporary files. They do not call models, APIs, judges, or external services.

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
