# Empirical Pilot Run Chain

<!-- claim_ceiling: empirical_pilot_run_chain_builder_present_and_self_tested -->

Status: Synthetic-self-tested pilot execution chain for future empirical runs.
The chain builds run inputs, records an execution preflight, executes an
explicitly allowed local runner script, validates the pilot transcript and
cost/latency package, derives annotation work items, and creates fillable label
templates. It does not embed provider API code, store credentials, create
completed labels, compute agreement, compute aggregate metrics, prove empirical
effectiveness, or claim paper readiness.

## Purpose

The repository already exposes each empirical step as a separate script. The
pilot run chain makes the first real-execution path reproducible as one command:

1. materialize fixed task-condition-repeat run inputs;
2. freeze a first pilot selection, provider, model alias, runtime surface, and
   budget;
3. call only a user-supplied local runner script after `-AllowRunnerScript`;
4. validate transcript and cost/latency joins;
5. derive unlabeled annotation work items;
6. derive placeholder label templates for future annotation.

This is the handoff before real labeling and measurement. A private runner may
call a hosted model/API, but private runner code, API credentials, and provider
secrets stay outside this public repository.

## Command

Self-test without persistent files or model/API calls:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-run-chain.ps1 -SelfTest
```

Future pilot run with an explicit local runner script:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-run-chain.ps1 `
  -OutputRoot dist/empirical-pilot-run-chain `
  -RunnerScriptPath path/to/private-runner.ps1 `
  -RunnerLabel private-runner-v0 `
  -Provider openai-compatible `
  -ModelNameOrAlias model-under-test `
  -RuntimeSurface private-runner-script `
  -MaxBudgetUsd 1.00 `
  -RecordsPerCondition 1 `
  -AllowRunnerScript `
  -Force
```

The generated package contains these public-safe artifacts:

- `run-inputs/`;
- `execution-preflight.json`;
- `pilot-execution-package/`;
- `annotation-worklist/`;
- `label-template-package/`;
- `metadata/pilot-run-chain-manifest.json`.

## Chain Checks

The builder:

- requires `-AllowRunnerScript` before executing any runner;
- uses the existing run-input, execution-preflight, pilot-package,
  annotation-worklist, and label-template builders and scorers;
- records the runner script hash and label without copying the runner script;
- records relative artifact paths, counts, and nonclaims without local source
  paths in the chain manifest;
- refuses nonempty output directories unless `-Force` is passed;
- with `-Force`, refuses output roots containing files outside the generated
  pilot-chain artifact set;
- fails closed if any downstream scorer rejects an artifact.

## Stop Gates

Stop before labeling, measurement, or paper claims when:

- no explicit local runner script has been reviewed and allowed;
- the execution preflight does not match the intended provider, model, runtime,
  budget, and selected pilot rows;
- any runner output contains private paths, credentials, unsupported result
  fields, or readiness/paper claims;
- the pilot execution package scorer fails;
- the annotation worklist or label-template package scorer fails;
- completed annotations have not passed the annotation-intake validator;
- the assembled evidence package has not passed its validator;
- real agreement checks and aggregate metrics have not been computed from the
  exact validated package.

## Current Nonclaims

This builder does not prove:

- completed model/API eval execution;
- runner quality;
- provider correctness;
- real transcript quality;
- completed human labels;
- completed LLM-judge labels;
- rule-based label quality;
- real agreement;
- real aggregate metrics;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
