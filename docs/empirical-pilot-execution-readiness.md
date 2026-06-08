# Empirical Pilot Execution Readiness

<!-- claim_ceiling: empirical_pilot_execution_readiness_checker_present_and_self_tested -->

Status: Pre-execution readiness gate for a future private/local pilot runner.
This checker validates the public run-input package, execution preflight,
runner script path, runner label, and required environment variable names before
any runner is invoked.

It does not execute the runner, call hosted model APIs, print environment variable values, create transcripts, create labels, compute metrics, prove real cost accuracy, or claim paper readiness.
It does not execute model/API evals.

## Purpose

The empirical pilot route needs a final local stop before model/API execution.
At that point the public repo can verify structure and credential presence, but
it must not contain private runner code, credentials, or secret values.

The readiness checker therefore:

- scores the run-input package;
- scores the execution preflight;
- confirms the runner script exists;
- rejects a runner script located inside the public repository;
- rejects blank labels or labels with path separators;
- requires at least one required environment variable name;
- validates required environment variable names;
- checks that required environment variables are present without printing their
  values;
- exits before runner execution.

## Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-empirical-pilot-execution-readiness.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -RunnerScriptPath path\to\private-runner.ps1 -RunnerLabel private-runner-v0 -RequiredEnvVarName MODEL_PROVIDER_TOKEN
```

For deterministic self-tests without persistent generated files, runner
execution, model/API calls, or secret output, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-empirical-pilot-execution-readiness.ps1 -SelfTest
```

## Current Nonclaims

This repository does not yet claim:

- completed public model/API eval execution;
- validated real runner responses;
- real transcripts;
- real labels;
- real cost/latency accuracy;
- aggregate metrics;
- empirical effectiveness;
- paper readiness.
