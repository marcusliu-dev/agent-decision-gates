# Empirical Annotation Worklist

<!-- claim_ceiling: empirical_annotation_worklist_builder_present_and_self_tested -->

Status: Structural worklist route for future annotation. This surface derives
annotation work items from a pilot execution package and the public annotation
guidelines. It does not create labels, run human review, run LLM-judge review,
measure agreement, compute aggregate metrics, prove empirical effectiveness, or
claim paper readiness.

## Purpose

Pilot execution packages contain transcript and cost-latency records. The next
empirical step is labeling those transcripts against the annotation rubric. The
annotation worklist builder creates one work item per pilot transcript, records
the annotation guideline version, copies only the public synthetic prompt and
model-output fields needed by a future annotator, and records hashes for the
source pilot manifest and annotation guidelines.

This keeps the future labeling route reproducible while preserving the boundary
that worklists are not annotations.

## Worklist Contract

Each `annotation-work-items/*.json` record contains:

- run and task identifiers;
- condition and repeat metadata;
- model provider, model alias, and runtime surface copied from the transcript;
- input prompt, final answer, final claim, checked evidence, and selected claim
  ceiling;
- transcript message count and the transcript source identifier for future
  span references;
- annotation guideline version;
- required label field names from `evals/empirical/annotation-schema.yaml`;
- redaction status.

The worklist scorer rejects missing work items, work items that do not match the
source pilot transcript including `checked_evidence`, injected annotation label
fields, metadata hash tampering, non-JSON sensitive files, credentials, private
paths, and unsupported result or paper-readiness claim fields.

## Structural Verification

Run after producing a pilot execution package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-annotation-worklist.ps1 -PilotPackageRoot dist/empirical-pilot-execution-package -OutputRoot dist/empirical-annotation-worklist -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-worklist.ps1 -PilotPackageRoot dist/empirical-pilot-execution-package -WorklistRoot dist/empirical-annotation-worklist
```

For self-tests without persistent generated files, model/API calls, labels, or
external services, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-annotation-worklist.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-worklist.ps1 -SelfTest
```

The self-tests build a temporary local fixture pilot execution package, derive a
worklist, validate one work item per pilot transcript, reject injected label
fields, mismatched transcript fields, metadata hash tampering, non-JSON
sensitive files, and `-Force` overwrite attempts over non-generated files, then
remove temporary files.

## Current Nonclaims

This repository does not yet claim:

- human annotations or labels;
- LLM-judge annotations or labels;
- agreement measurements;
- aggregate metrics;
- statistical results;
- empirical effectiveness;
- paper readiness;
- production safety;
- annotator quality or judge validity.
