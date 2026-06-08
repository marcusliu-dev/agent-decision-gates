# Empirical Pilot Runner Requests

<!-- claim_ceiling: empirical_pilot_runner_request_package_builder_present_and_self_tested -->

Status: Pre-execution request-package builder for future private/local pilot
runner execution. It materializes the exact JSON request files selected by the
run-input package and execution preflight so a private runner can consume a
stable request package later.

It does not execute the runner, call hosted model APIs, read credentials, print
environment variable values, create runner responses, create transcripts, create
cost/latency records, create labels, compute metrics, prove runner quality,
prove credential validity, or claim paper readiness.

## Purpose

The public pilot route already defines run inputs, execution preflight, runner
response scoring, package wrapping, and readiness checks. A private runner still
needs a durable request boundary: the public repo should be able to freeze what
will be sent to the runner before any provider-specific code or credentials are
used.

The request builder therefore:

- scores the run-input package before materializing requests;
- scores the execution preflight before materializing requests;
- writes one request JSON per selected preflight `run_input_id`;
- records source preflight and run-input manifest hashes;
- rejects selected ids that are missing from the run-input package;
- rejects blank runner labels or labels with path separators;
- refuses non-generated files when `-Force` is used;
- exits before runner execution.

## Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-runner-requests.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -OutputRoot dist/empirical-pilot-runner-requests -RunnerLabel private-runner-v0
```

For deterministic self-tests without persistent generated files, runner
execution, model/API calls, or secret output, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-runner-requests.ps1 -SelfTest
```

No runner script was executed by this builder.

## Output Shape

The generated package contains:

- `requests/pilot-request-<run_input_id>.json`
- `metadata/pilot-runner-request-manifest.json`
- `metadata/source-preflight-hash.json`
- `metadata/source-run-input-manifest-hash.json`

Each request includes the selected run id, source run-input id, task id,
condition, repeat index, prompt versions, input prompt, expected failure modes,
required conditions, forbidden claims, preflight id, provider, model alias,
runtime surface, and runner label.

## Current Nonclaims

This repository does not yet claim:

- completed public model/API eval execution;
- validated real runner responses;
- real transcripts;
- real labels;
- real cost/latency accuracy;
- aggregate metrics;
- runner quality;
- credential validity;
- empirical effectiveness;
- paper readiness.
