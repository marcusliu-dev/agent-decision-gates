# Empirical Pilot Execution Runner

<!-- claim_ceiling: empirical_pilot_execution_runner_present_and_self_tested -->

Status: Explicit local-runner route for future pilot transcript and
cost-latency package generation. This runner consumes a scored run-input
package and execution preflight record, then calls only a user-supplied local
runner script when explicitly allowed. The self-test uses a temporary local
fixture runner and does not call hosted model APIs, produce labels, compute
metrics, prove empirical effectiveness, or claim paper readiness.

## Purpose

The execution preflight records what should run first. The pilot execution
runner records how those selected inputs can be executed without putting
credentials, private paths, or provider-specific API code into this public
repository. A private adapter can be supplied at runtime, but the generated
package must contain only public synthetic task prompts, transcript records,
cost-latency records, source hashes, and a runner-script hash.

This keeps the public repository useful for reproducible experiments while
preserving the no-export boundary for credentials and private runtime details.

## Runner Contract

The runner script is invoked once per selected run input with:

```powershell
powershell -ExecutionPolicy Bypass -File <runner-script> -RequestPath <request.json> -ResponsePath <response.json>
```

The request JSON includes the selected `run_input_id`, task metadata,
condition, repeat index, input prompt, preflight provider, model alias, and
runtime surface. The response JSON must include at least `final_answer`.

Optional response fields include:

- `transcript_messages`;
- `tool_calls`;
- `final_claim`;
- `checked_evidence`;
- `selected_claim_ceiling`;
- `stop_or_continue_decision`;
- `human_checkpoint_decision`;
- `input_tokens`;
- `output_tokens`;
- `wall_time_ms`;
- `api_cost_usd`;
- `retry_count`.

The package scorer rejects credentials, private paths, non-JSON package files,
unsupported result or paper-readiness claims, provider/model/runtime mismatch,
broken transcript/cost joins, and missing selected run inputs.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -OutputRoot dist/empirical-run-inputs -Force
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -RunInputRoot dist/empirical-run-inputs -OutputPath dist/empirical-execution-preflight.json -Provider openai-compatible -ModelNameOrAlias model-under-test -RuntimeSurface private-runner-script -MaxBudgetUsd 1.00 -Force
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-execution-package.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -OutputRoot dist/empirical-pilot-execution-package -RunnerScriptPath path\to\private-runner.ps1 -RunnerLabel private-runner-v0 -AllowRunnerScript -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-execution-package.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -PackageRoot dist/empirical-pilot-execution-package
```

For self-tests without persistent generated files or model/API calls, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-execution-package.ps1 -SelfTest
```

The self-tests build temporary run inputs and an execution preflight, execute a
temporary local fixture runner, validate the resulting transcript/cost package,
reject missing transcripts, crossed cost-latency joins, credential-like content,
provider/model/runtime mismatches, metadata hash tampering, non-JSON sensitive
files, unsupported result/paper-readiness tokens, and `-Force` overwrite
attempts over non-generated files, then remove the temporary files.

## Current Nonclaims

This repository does not yet claim:

- completed public model/API eval execution;
- annotations or labels;
- human/LLM-judge agreement;
- aggregate metrics;
- statistical results;
- empirical effectiveness;
- paper readiness;
- production safety;
- runner quality or provider correctness.
