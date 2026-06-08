# Empirical Runner Response Contract

<!-- claim_ceiling: empirical_runner_response_contract_present_and_self_tested -->

Status: Structural runner-response contract and deterministic scorer for one
local runner response before that response is wrapped into a pilot execution
package. The scorer validates response shape, blocked sensitive patterns,
unsupported result/readiness JSON fields, numeric telemetry fields, and
optional request/run-input matching. It preserves natural-language
readiness/result phrases in model output for downstream annotation instead of
rejecting the behavior before measurement. It does not call hosted model APIs,
produce pilot transcripts by itself, produce labels, compute metrics, prove
runner quality, or claim paper readiness.

## Purpose

The pilot execution route intentionally keeps provider-specific code and
credentials outside this public repository. That makes the runner script a
trust boundary: it is private or user-supplied, but its response must still
fit the public experiment packet before the response becomes a transcript and
cost-latency record.

Use this contract as a preflight for a private runner adapter. A runner response
can pass this scorer and still be low quality; it does not prove runner quality.
The scorer only checks that the response meets the structural and sensitive-
content preconditions for entering the pilot package route.

## Response Contract

The runner script receives a request JSON and writes a response JSON. The
response must include:

- `final_answer`

Optional fields are defined in
[`runner-response-schema.yaml`](../evals/empirical/runner-response-schema.yaml)
and include transcript messages, final claim, checked evidence, selected claim
ceiling, stop/continue decision, human-checkpoint decision, token counts,
wall-clock time, API cost, retry count, and optional `run_input_id` for joining
back to the request.

The scorer rejects:

- missing or empty `final_answer`;
- credential-like content, private paths, and private-key markers;
- forbidden result/readiness JSON fields such as `paper_ready`,
  `production_ready`, `pass_rate`, and `aggregate_metrics`;
- null, blank, boolean, negative, or non-finite numeric telemetry fields;
- non-integer token, latency, or retry fields;
- optional `run_input_id` values that do not match the request JSON.

The scorer does not reject natural-language claim phrases inside
`final_answer`, transcript messages, or `final_claim` values. Those phrases are
the behavior the empirical route is meant to measure, so they must survive into
the transcript package for later annotation.

Join validation covers request/run-input mismatches.

The standalone response scorer treats token, cost, latency, and retry fields as
optional because it can score one response before the final execution route is
known. The pilot execution package builder is stricter: before package wrapping,
it requires explicit `input_tokens`, `output_tokens`, `api_cost_usd`, and
`retry_count` from the runner response so missing API cost cannot be recorded as
zero cost.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-runner-response.ps1 -ResponsePath path\to\response.json -RequestPath path\to\request.json
```

For self-tests without persistent generated files or model/API calls, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-runner-response.ps1 -SelfTest
```

The self-test validates a fixture runner response, then rejects missing
`final_answer`, credential-like content, forbidden result/readiness fields,
null, blank, boolean, or negative numeric fields, and request/run-input
mismatches. It also verifies that natural-language readiness/result phrases and
`final_claim` values are preserved for downstream annotation.

## Current Nonclaims

This repository does not yet claim:

- completed public model/API eval execution;
- validated real runner responses;
- pilot transcript quality;
- measured cost accuracy beyond runner-reported telemetry;
- annotations or labels;
- human/LLM-judge agreement;
- aggregate metrics;
- statistical results;
- empirical effectiveness;
- runner quality or provider correctness;
- paper readiness;
- production safety.
