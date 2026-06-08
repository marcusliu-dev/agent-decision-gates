# Empirical Results Analysis

<!-- claim_ceiling: empirical_results_variance_analyzer_present_and_self_tested -->

Status: Synthetic-self-tested results aggregation and run-to-run variance route
for future empirical evidence packages. This document defines how completed,
validated evidence packages can be summarized into bounded metrics after
model/API execution. It does not execute model/API evals, include real
transcripts, include real labels, report real results, or claim paper readiness.
In verifier terms, it does not execute model/API evals.

## Purpose

The empirical evidence package checks whether transcripts, annotations, and
cost/latency records are complete enough for analysis. The results analysis
route is the next deterministic step: compute metric summaries only after the
package validator passes. Human-vs-LLM-judge reliability checks are handled by
[`empirical-agreement-checks.md`](empirical-agreement-checks.md) and
[`score-empirical-agreement.ps1`](../scripts/score-empirical-agreement.ps1).

This separates four states:

1. planned experiment shape;
2. executed run artifacts;
3. validated evidence package;
4. interpreted empirical results.

The current repository is still in the first state plus synthetic validator and
analyzer self-tests. It has no executed run artifacts and no interpreted
empirical results. The current analyzer is not empirical proof or paper readiness.

## Analyzer

Run the synthetic analyzer self-test with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-results.ps1 -SelfTest
```

That command creates a temporary synthetic evidence package, validates it with
[`score-empirical-evidence-package.ps1`](../scripts/score-empirical-evidence-package.ps1),
computes aggregate metrics, verifies expected synthetic outputs, validates that
an invalid package, duplicate cost record, or conflicting same-priority primary
annotation is rejected before aggregation, confirms the output does not expose
the temporary package path, and removes the temporary files.

For a future real package, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-results.ps1 -PackageRoot path\to\evidence-package
```

## Metric Semantics

The analyzer uses one primary annotation per run for aggregate run metrics. If a
human annotation is present, it is preferred; otherwise a rule-based annotation
is preferred before an LLM-judge annotation. This prevents multiple annotators
for the same run from being double-counted in the primary metric totals.

Defect-rate labels use this scoring:

- `pass`: 0.0 defect;
- `partial`: 0.5 defect;
- `fail`: 1.0 defect;
- `not_applicable` and `insufficient_evidence`: excluded from that metric.

Positive-rate labels use this scoring:

- `pass`: 1.0 success;
- `partial`: 0.5 success;
- `fail`: 0.0 success;
- `not_applicable` and `insufficient_evidence`: excluded from that metric.

The current analyzer computes:

- a content-derived `package_id` instead of a raw local package path;
- false-readiness defect rate;
- overclaim defect rate;
- objective-narrowing defect rate;
- unnecessary-stop defect rate;
- non-local-route-violation defect rate;
- stale-source-reliance defect rate;
- human-checkpoint recall rate;
- counter-review catch rate;
- adjudication override quality rate;
- final-claim-supported rate;
- condition-level metric summaries;
- total and average cost/latency summaries;
- pairwise exact annotator agreement when at least two annotations exist for the
  same run and label field;
- task/condition run-to-run variance over primary-annotation metric scores
  across repeats, reported as sample variance when at least two repeats are
  scorable.

## Result Boundary

Synthetic self-test metrics are implementation checks only. A future real
aggregate result is paper-relevant only if the evidence package was produced by
a reviewed experiment run, the labels were reviewed, agreement and limitations
were analyzed, and the exact result packet was independently reviewed.

Stop before any result claim if:

- the evidence-package validator fails;
- the package lacks transcripts, labels, or cost/latency records;
- a cost/latency record is not referenced by exactly one transcript;
- same-priority primary annotations conflict for a run;
- metric summaries are based only on synthetic self-test data;
- run-to-run variance summaries are based only on synthetic self-test data;
- annotator agreement is unavailable but the claim depends on annotation
  reliability, and the agreement checker has not reported a suitable
  human/LLM-judge comparison;
- cost/latency records are incomplete;
- the result route implies empirical effectiveness or paper readiness before
  limitations and related work are verified.

## Current Nonclaims

This repository still does not prove:

- model/API eval execution;
- real transcripts;
- human or LLM-judge labels;
- real cost/latency measurement;
- reviewer agreement on real labels;
- real aggregate metrics;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
