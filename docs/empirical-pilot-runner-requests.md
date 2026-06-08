# Empirical Pilot Runner Requests

<!-- claim_ceiling: empirical_pilot_runner_request_package_scorer_present_and_self_tested -->

Status: Pre-execution request-package builder and scorer for future
private/local pilot runner execution. The builder materializes the exact JSON
request files selected by the run-input package and execution preflight so a
private runner can consume a stable request package later. The scorer validates
that generated package against the source run inputs, execution preflight,
manifest hashes, and no-results boundary before any runner is invoked.

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

The request scorer therefore:

- reruns the run-input and execution-preflight scorers before checking the
  request package;
- validates generated request files, manifest records, and source hash sidecar
  files;
- checks that each request matches the source run input and execution preflight
  runtime fields;
- rejects request JSON fields outside the exact request schema, even if the
  manifest request hash is updated;
- rejects malformed package metadata JSON as a structured scorer failure;
- rejects forbidden response, transcript, cost, annotation, metric, readiness,
  and result fields;
- rejects unexpected package files and sensitive non-JSON files;
- exits before runner execution.

## Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-runner-requests.ps1 -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json -OutputRoot dist/empirical-pilot-runner-requests -RunnerLabel private-runner-v0
```

Score the generated request package before invoking any private runner:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-runner-requests.ps1 -PackageRoot dist/empirical-pilot-runner-requests -RunInputRoot dist/empirical-run-inputs -PreflightPath dist/empirical-execution-preflight.json
```

For deterministic self-tests without persistent generated files, runner
execution, model/API calls, or secret output, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-runner-requests.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-runner-requests.ps1 -SelfTest
```

No runner script was executed by this builder.
No runner script was executed by this scorer.

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

The scorer rejects package files outside this shape, including runner response
fields, transcript fields, cost/latency result fields, annotation labels,
aggregate metric fields, paper-readiness fields, and sensitive non-JSON files.

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
