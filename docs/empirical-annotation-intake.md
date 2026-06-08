<!-- claim_ceiling: empirical_annotation_intake_validator_present_and_self_tested -->

# Empirical Annotation Intake

This route validates completed annotation records after a label-template package
has been filled by a human annotator, LLM judge, or rule-based scorer. It does not create labels. It does not compute agreement, aggregate metrics, or claim
paper readiness.

Use it after:

1. a pilot execution package has produced redacted transcripts;
2. an annotation worklist has been built and scored;
3. a label-template package has been built and scored;
4. annotators have filled records using the frozen annotation guideline version.

The validator links each completed annotation back to the label template,
annotation work item, annotation schema, and guideline hash. It is the intake
gate before evidence-package validation, results aggregation, and
human-vs-LLM-judge agreement checks.

## Required Shape

The completed annotation intake package must contain:

- `annotations/*.json`
- `metadata/annotation-intake-manifest.json`
- `metadata/source-label-template-package-manifest-hash.json`
- `metadata/source-annotation-worklist-manifest-hash.json`
- `metadata/annotation-schema-hash.json`
- `metadata/annotation-guidelines-hash.json`

Every annotation record must follow
[`evals/empirical/annotation-schema.yaml`](../evals/empirical/annotation-schema.yaml)
and must map to exactly one label template by `run_id`. If an annotation also
includes `annotation_template_id`, that value must match the source template.

## Validation Checks

`scripts/score-empirical-annotation-intake.ps1` checks:

- every label template has at least one completed annotation;
- every annotation maps to a known label template and annotation work item;
- `task_id`, `condition`, and `annotation_guideline_version` match the source
  template;
- every required `*_label` value is one of the allowed schema values;
- no unexpected `*_label` field is present;
- `confidence` is numeric and within `0..1`;
- `label_timestamp_utc` parses as a timestamp;
- rationale spans include message index, start/end offsets, and a note;
- rationale message indexes stay inside `transcript_message_count`;
- duplicate `run_id + annotator_type + annotator_id` records are rejected;
- metadata hashes match the source template package, source worklist,
  annotation schema, and annotation guidelines;
- non-JSON files, credential-like content, and forbidden aggregate/result fields
  are rejected.

The scorer supports `-RequireHuman` and `-RequireLlmJudge` when a specific
package must include at least one human or LLM-judge annotation per template.

## Commands

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-intake.ps1 -SelfTest
```

For a real completed-label package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-intake.ps1 `
  -AnnotationRoot dist/empirical-annotation-intake `
  -TemplatePackageRoot dist/empirical-label-template-package `
  -WorklistRoot dist/empirical-annotation-worklist `
  -RequireHuman
```

## Current Nonclaims

- no real human labels are included in this repository;
- no real LLM-judge labels are included in this repository;
- no rule-based labels are included in this repository;
- no human/LLM-judge agreement has been measured;
- no aggregate metrics, confidence intervals, or statistical results are
  reported;
- no annotator-quality, judge-validity, empirical-effectiveness, paper-ready, or
  production-ready claim is supported by the self-test.
