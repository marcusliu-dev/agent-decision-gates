# Empirical Evidence Package Builder

<!-- claim_ceiling: empirical_evidence_package_builder_present_and_self_tested -->

Status: Synthetic-self-tested assembly route for future empirical evidence
packages. This builder copies validated pilot transcripts, cost/latency records,
and completed annotation records into the evidence-package shape consumed by
the evidence-package validator, results aggregator, and agreement checker. It
does not execute model/API evals, create labels, compute agreement, compute
aggregate metrics, prove empirical effectiveness, or claim paper readiness.

## Purpose

After a pilot execution package has produced transcript and cost/latency JSON
records, and after a completed annotation-intake package has passed its own
validation, the next step is to assemble one package for downstream validation
and analysis. Manual copying is easy to get wrong: transcripts can lose their
cost joins, annotations can be mismatched, local paths can leak into metadata,
and force-overwrite behavior can hide stale files.

`scripts/build-empirical-evidence-package.ps1` makes that handoff explicit. It
copies only JSON files from:

- `pilot-package/transcripts/`;
- `pilot-package/cost-latency/`;
- `annotation-intake/annotations/`.

It writes bounded metadata hashes under `metadata/`, records only content
digests and counts, and runs the evidence-package validator by default after
assembly. `-RunValidators` is accepted for explicit command readability;
`-SkipValidators` is the only route that skips the validator and it cannot
support any evidence-package validity, result, agreement, or readiness claim.

## Commands

Self-test without persistent files:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-evidence-package.ps1 -SelfTest
```

Build a future package after pilot execution and annotation intake:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-evidence-package.ps1 `
  -PilotPackageRoot dist/empirical-pilot-execution-package `
  -AnnotationIntakeRoot dist/empirical-annotation-intake `
  -OutputRoot dist/empirical-evidence-package `
  -RunValidators `
  -Force
```

Then run the downstream checks:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -PackageRoot dist/empirical-evidence-package
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-results.ps1 -PackageRoot dist/empirical-evidence-package
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-agreement.ps1 -PackageRoot dist/empirical-evidence-package -RequireHumanLlmPairs
```

## Assembly Checks

The builder:

- requires source transcript, cost/latency, and annotation JSON files;
- rejects non-JSON source files under the source packages;
- scans copied source JSON for credential-like strings and local absolute paths;
- writes source package content hashes, not local source paths;
- writes an `evidence-package-manifest.json` with counts and the builder
  version;
- refuses to write into a nonempty output directory unless `-Force` is passed;
- with `-Force`, refuses to overwrite files outside the exact generated file
  set for the current sources;
- runs `scripts/score-empirical-evidence-package.ps1` by default and fails if
  the assembled package is rejected;
- allows `-SkipValidators` only for low-level assembly debugging, and records a
  warning that no validity, result, agreement, or readiness claim is supported.

## Stop Gates

Stop before result or paper claims when:

- the pilot execution package has not passed its scorer;
- the annotation-intake package has not passed its scorer;
- the builder was run with `-SkipValidators` or returned
  `validator_status: not_run`;
- the assembled evidence package has not passed the evidence-package validator;
- source package hashes or counts do not match the reviewed run packet;
- non-JSON or credential-like source material is present;
- the package contains only synthetic self-test data;
- human/LLM-judge agreement is required but the agreement checker has not
  reported acceptable real-label agreement;
- aggregate metrics have not been independently reviewed against the exact
  package used to compute them.

## Current Nonclaims

This builder does not prove:

- model/API eval execution;
- real transcript quality;
- real human labels;
- real LLM-judge labels;
- rule-based label quality;
- real agreement;
- real aggregate metrics;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
