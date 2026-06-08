# Empirical Human Annotation Handoff

<!-- claim_ceiling: empirical_human_annotation_handoff_builder_present_and_self_tested -->

Status: Structural human-handoff route for future annotation. This surface
turns label templates into human-facing draft JSON records and transcript
readouts. It does not create completed human labels, validate filled human
labels, measure human/LLM-judge agreement, compute aggregate metrics, prove
judge validity, prove empirical effectiveness, or claim paper readiness.

## Purpose

The label-template package is intentionally machine-oriented. A human
annotator still needs a readable packet that pairs each unfilled JSON draft
with the task prompt, model final answer, label fields, and source context.

The human-annotation handoff builder creates one unfilled draft and one
Markdown readout per label template. The drafts are designed for humans to
fill later, but the handoff package itself must remain unlabeled. Once a human
fills labels, those completed records move into an annotation-intake package
and are validated by
[`score-empirical-annotation-intake.ps1`](../scripts/score-empirical-annotation-intake.ps1)
with `-RequireHuman`.

The handoff package is not an annotation intake package.

## Package Contract

Each `annotation-drafts/*.json` record contains:

- draft, template, work-item, run, task, condition, and repeat identifiers;
- annotation guideline version;
- `annotator_type` set to `human`;
- unfilled annotator id and timestamp placeholders;
- required label fields set to the fill placeholder;
- an unfilled rationale-span placeholder;
- an unfilled confidence placeholder;
- `claim_boundary` set to `human_annotation_draft_unfilled_no_label_claim`;
- source redaction status copied from the annotation work item.

Each `transcript-readouts/*.md` record contains a human-readable task prompt,
model final answer, matching draft path, and label-field reminder. The readout
is convenience material only; the JSON draft remains the fillable record.

The scorer rejects missing drafts, missing readouts, completed label values in
drafts, non-placeholder annotator or timestamp fields, mismatched template or
work-item fields, missing or duplicate draft joins, metadata hash tampering,
forbidden aggregate/result fields, credentials, private paths, and unexpected
package files.

## Structural Verification

Run after producing a pilot execution package, annotation worklist, and
label-template package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-human-annotation-handoff.ps1 -PilotPackageRoot dist/empirical-pilot-execution-package -WorklistRoot dist/empirical-annotation-worklist -TemplatePackageRoot dist/empirical-label-template-package -OutputRoot dist/empirical-human-annotation-handoff -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-human-annotation-handoff.ps1 -PilotPackageRoot dist/empirical-pilot-execution-package -WorklistRoot dist/empirical-annotation-worklist -TemplatePackageRoot dist/empirical-label-template-package -HandoffRoot dist/empirical-human-annotation-handoff
```

For self-tests without persistent generated files, model/API calls, completed
labels, agreement metrics, or external services, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-human-annotation-handoff.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-human-annotation-handoff.ps1 -SelfTest
```

The self-tests build a temporary local fixture pilot package, derive an
annotation worklist, derive label templates, generate a 9-draft human handoff,
validate one draft and one readout per template, reject completed label values,
reject metadata hash tampering, reject sensitive package text, and reject
`-Force` overwrite attempts over non-generated files, then remove temporary
files.

## After Humans Fill Labels

Do not treat this handoff package as an annotation intake package. After human
annotators fill copies of the drafts, place the completed JSON records in an
annotation-intake package and validate that package:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-intake.ps1 -AnnotationRoot dist/empirical-human-annotation-intake -TemplatePackageRoot dist/empirical-label-template-package -WorklistRoot dist/empirical-annotation-worklist -RequireHuman
```

Only after completed human records pass annotation-intake validation should an
evidence package or agreement check be assembled.

## Current Nonclaims

This repository does not yet claim:

- completed human annotations;
- human/LLM-judge agreement;
- annotator quality;
- judge validity;
- aggregate metrics;
- statistical results;
- empirical effectiveness;
- paper readiness;
- production safety.
