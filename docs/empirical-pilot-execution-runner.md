# Empirical Pilot Execution Runner

<!-- claim_ceiling: empirical_pilot_budget_gate_present_and_self_tested -->

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

For the integrated first-pilot route that chains run-input generation,
execution preflight, this runner, annotation worklist generation, and
label-template generation, use
[`docs/empirical-pilot-run-chain.md`](empirical-pilot-run-chain.md). That
chain remains bounded to fixture/self-test execution until a real authorized
runner produces reviewed transcripts that are separately labeled and validated
through the annotation-intake route.

## Runner Contract

The runner script is invoked once per selected run input with:

```powershell
powershell -ExecutionPolicy Bypass -File <runner-script> -RequestPath <request.json> -ResponsePath <response.json>
```

The request JSON includes the selected `run_input_id`, task metadata,
condition, repeat index, input prompt, preflight provider, model alias, and
runtime surface. The response JSON must include at least `final_answer`.

For pilot package generation, the runner must also report explicit telemetry
before wrapping: `input_tokens`, `output_tokens`, `api_cost_usd`, and
`retry_count`. The builder measures wall-clock time if `wall_time_ms` is not
reported, but it does not silently convert missing API cost into zero cost.

Other optional response fields include:

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

Before a runner response is wrapped into a pilot transcript and cost-latency
record, the builder calls
[`score-empirical-runner-response.ps1`](../scripts/score-empirical-runner-response.ps1).
That scorer validates the single response contract, blocked sensitive patterns,
unsupported result/readiness fields, numeric telemetry fields, and optional
request/run-input matching. It does not prove runner quality or model/API eval
results.

The package builder rejects missing required runner telemetry before wrapping.
The package scorer rejects missing or invalid cost-latency package fields,
credentials, private paths, non-JSON package files, unsupported result or
paper-readiness claims, provider/model/runtime mismatch, broken transcript/cost
joins, missing selected run inputs, and total API cost above the preflight max
budget.
It explicitly rejects credentials before any pilot package can support a public
claim.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -OutputRoot dist/empirical-run-inputs -Force
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -RunInputRoot dist/empirical-run-inputs -OutputPath dist/empirical-execution-preflight.json -Provider openai-compatible -ModelNameOrAlias model-under-test -RuntimeSurface private-runner-script -MaxBudgetUsd 1.00 -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-runner-response.ps1 -ResponsePath path\to\sample-response.json -RequestPath path\to\sample-request.json
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-execution-package.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -OutputRoot dist/empirical-pilot-execution-package -RunnerScriptPath path\to\private-runner.ps1 -RunnerLabel private-runner-v0 -AllowRunnerScript -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-execution-package.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -PackageRoot dist/empirical-pilot-execution-package
```

For self-tests without persistent generated files or model/API calls, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-runner-response.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-execution-package.ps1 -SelfTest
```

The self-tests build temporary run inputs and an execution preflight, execute a
temporary local fixture runner, validate the resulting transcript/cost package,
reject missing runner cost telemetry, missing transcripts, crossed
cost-latency joins, total API cost above the preflight max budget,
credential-like content, provider/model/runtime mismatches,
metadata hash tampering, non-JSON sensitive files, unsupported
result/paper-readiness tokens, and `-Force` overwrite attempts over
non-generated files, then remove the temporary files.

## Current Nonclaims

This repository does not yet claim:

- completed public model/API eval execution;
- annotations or labels;
- human/LLM-judge agreement;
- aggregate metrics;
- measured cost accuracy beyond runner-reported telemetry;
- statistical results;
- empirical effectiveness;
- paper readiness;
- production safety;
- runner quality or provider correctness.
