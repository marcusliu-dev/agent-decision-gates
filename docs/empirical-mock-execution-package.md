# Empirical Mock Execution Package

<!-- claim_ceiling: empirical_mock_execution_package_builder_present_and_self_tested -->

Status: Synthetic transcript and cost-latency package route for future
empirical execution harness work. This package is generated from a run-input
package and execution preflight record, but it does not call models or APIs,
does not produce real model transcripts, and does not report empirical results
or paper readiness.

## Purpose

The execution preflight freezes what should run first. The mock execution
package exercises the next artifact contract: every selected run input should
produce one transcript-shaped record and one cost-latency-shaped record that
join cleanly. This catches package and scorer defects before any real model/API
budget is spent.

## Current Scope

The mock builder reads:

- a generated run-input package, usually `dist/empirical-run-inputs`;
- an execution preflight record, usually
  `dist/empirical-execution-preflight.json`.

It writes:

- `transcripts/*.json` mock transcript records;
- `cost-latency/*.json` mock cost-latency records;
- `metadata/*.json` source hash and package manifest records.

The current default seed path produces 9 mock transcript records and 9 mock
cost-latency records, one pair for each selected run input in the preflight.
The records use deterministic synthetic answers and zero API cost. They are
not real model outputs.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -OutputRoot dist/empirical-run-inputs -Force
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -RunInputRoot dist/empirical-run-inputs -OutputPath dist/empirical-execution-preflight.json -Provider openai-compatible -ModelNameOrAlias model-under-test -RuntimeSurface api-runner-under-test -MaxBudgetUsd 1.00 -Force
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-mock-execution-package.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -OutputRoot dist/empirical-mock-execution-package -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-mock-execution-package.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -PackageRoot dist/empirical-mock-execution-package
```

For self-tests without persistent generated files, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-mock-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-mock-execution-package.ps1 -SelfTest
```

The self-tests build temporary run-input and preflight records, generate a mock
execution package, validate it, reject missing transcript, crossed
cost-latency join, credential-like content, non-JSON sensitive files,
unsupported effectiveness claim cases, and `-Force` overwrite attempts over
non-generated files, then remove the temporary files. They do not call models,
APIs, judges, or external services.

## Current Nonclaims

This repository does not yet claim:

- real model/API eval execution;
- real transcripts;
- real annotations;
- real cost/latency results;
- human/LLM-judge agreement;
- aggregate metrics;
- statistical results;
- empirical effectiveness;
- paper readiness;
- production safety.
