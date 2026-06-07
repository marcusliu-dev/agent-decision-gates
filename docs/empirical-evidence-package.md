# Empirical Evidence Package

<!-- claim_ceiling: empirical_evidence_package_validator_present_and_self_tested -->

Status: Structural evidence-package validation route for future empirical
experiments. This document defines how a future completed experiment package
should be checked before any result or paper-readiness claim. It does not
execute model/API evals, include transcripts, include labels, report results,
or claim paper readiness. In verifier terms, it does not execute model/API evals.

## Purpose

The run packet freezes what must exist before experiment execution. The
evidence package validates what must exist after execution before anyone can
aggregate results or make a paper claim. This separates three states:

1. planned experiment shape;
2. executed run artifacts;
3. interpreted empirical results.

The current repository is still in the first state plus a validator self-test.
It has no executed run artifacts and no interpreted empirical results.

## Required Package Shape

A future evidence package should be a directory with:

- `transcripts/`: JSON transcript records matching
  [`transcript-schema.yaml`](../evals/empirical/transcript-schema.yaml);
- `annotations/`: JSON annotation records matching
  [`annotation-schema.yaml`](../evals/empirical/annotation-schema.yaml);
- `cost-latency/`: JSON cost and latency records with the fields listed in
  [`evidence-package-schema.yaml`](../evals/empirical/evidence-package-schema.yaml).

Each transcript must join to at least one annotation by `run_id`, and to one
cost/latency record by both `run_id` and `cost_latency_record_id`. Annotation
rationales must cite transcript spans. A package missing these links is not
ready for metric computation.

## Validator

Run the validator self-test:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -SelfTest
```

That command creates a temporary synthetic package, validates a positive case,
validates that deliberately broken cases fail, and removes the temporary files.
The negative cases include missing annotation joins, empty required ids,
credential-like JSON keys, invalid labels, invalid transcript spans, malformed
cost records, crossed cost/latency joins, invalid annotation metadata, and
missing nested transcript/tool-call fields. The self-test proves only that the
validator catches these basic structure and join failures on synthetic data.

For a future real package, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -PackageRoot path\to\evidence-package
```

After this validator passes, the bounded post-package aggregation route is
defined in [`empirical-results-analysis.md`](empirical-results-analysis.md). The
current aggregation route is synthetic-self-tested only and does not report real
experiment results.

## Result Boundary

The validator may summarize counts from a supplied package, such as transcript
count, annotated-run count, and cost-record count. Those counts are package
completeness checks. They are not empirical effectiveness results unless the
package was produced by a reviewed experiment run and the result analysis was
separately verified.

## Stop Gates

Stop before result computation if:

- any transcript lacks an annotation;
- any transcript lacks a cost/latency record;
- any annotation references a missing run;
- any cost/latency record references a missing run;
- annotation rationales do not cite transcript spans;
- transcript message, tool-call, annotation, or cost fields are missing or
  malformed in the basic schema fields used by the validator;
- private repository material or credentials appear in package JSON;
- the package route implies paper readiness before metrics and limitations are
  verified.

## Current Nonclaims

This repository still does not prove:

- model/API eval execution;
- transcript production;
- human or LLM-judge labels;
- cost/latency measurement;
- reviewer agreement;
- real aggregate metrics;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
