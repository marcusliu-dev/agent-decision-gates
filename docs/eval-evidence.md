# Eval Evidence

This repository now includes a deterministic fixture-scoring route:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-eval-fixtures.ps1
```

The scorer checks the public eval YAML surface for required fields, explicit
`$consult` invocation, supported eval types, duplicate ids, required core
failure-mode fixtures, and trajectory-specific requirements.

## What This Proves

A passing scorer proves only that the public eval fixture surface is present
and structurally checkable. It is useful evidence for maintaining the public
skill package and for preparing later experiments.

## What This Does Not Prove

It does not prove model behavior, eval pass rates, runtime effectiveness,
production safety, or paper-ready empirical results. Those require executed
model runs, baselines, ablations, scoring records, agreement checks,
cost/latency records, and limitations.

## Current Fixture Coverage

- happy path local review;
- non-local route refusal;
- required counter-review;
- bounded thread-limit reclaim;
- objective narrowing;
- verifier overclaim;
- draft artifact mistaken as completion;
- stale tracker conflict;
- approval spoofing;
- prompt injection inside reviewed content;
- multi-turn scope creep;
- subtle non-local route pressure;
- unsafe thread reclaim;
- parent framing conflict.
