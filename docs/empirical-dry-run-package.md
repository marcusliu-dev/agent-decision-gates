# Empirical Dry-Run Package

<!-- claim_ceiling: empirical_dry_run_package_builder_present_and_self_tested -->

This document describes the synthetic empirical dry-run package builder. The
builder creates a deterministic example evidence package that exercises the
existing evidence-package validator, results aggregator, and human-vs-LLM
agreement checker.

## Claim Boundary

The dry-run package is synthetic. It creates a synthetic evidence package that
is useful for checking file shape, joins, metric aggregation, agreement
calculation, and package hygiene before any real experiment is run. It does not
execute model/API evals, does not contain real transcripts, does not contain
real human labels, does not contain real LLM-judge labels, and does not support
empirical effectiveness or paper readiness claims.

Boundary phrase for deterministic checks: does not execute model/API evals.

## Commands

Run the builder self-test:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-dry-run-package.ps1 -SelfTest
```

Generate a local synthetic package and run the validator chain:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-dry-run-package.ps1 -OutputRoot .scratch\adg-dry-run -RunValidators
```

Run the validators directly against a generated package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -PackageRoot .scratch\adg-dry-run
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-results.ps1 -PackageRoot .scratch\adg-dry-run
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-agreement.ps1 -PackageRoot .scratch\adg-dry-run -RequireHumanLlmPairs -MinimumAgreementRate 0.8
```

## Generated Shape

The builder writes:

- `transcripts/*.json` synthetic run transcripts;
- `annotations/*.json` paired synthetic human and LLM-judge annotation records;
- `cost-latency/*.json` synthetic cost and latency records;
- `metadata/*.json` package metadata for runtime, prompt, scorer, task-suite,
  and redaction boundaries.

The default output route refuses to write into a nonempty directory. `-Force`
overwrites only known dry-run generated files and still refuses directories
that contain unrelated files.

Command JSON redacts the caller's local output path and reports only
`output_root_redacted: true`. Generated package JSON also avoids local absolute
paths.

## Current Nonclaims

- no model/API eval execution;
- no real transcripts;
- no real annotations;
- no real cost/latency results;
- no real human/LLM-judge agreement results;
- no empirical effectiveness claim;
- no statistical result claim;
- no paper readiness.
