# Empirical Label Template Package

<!-- claim_ceiling: empirical_label_template_package_builder_present_and_self_tested -->

Status: Structural label-template route for future annotation. This surface
turns annotation work items into fillable annotation templates and checks their
source links. It does not create human labels, run LLM-judge labeling, measure
agreement, compute aggregate metrics, prove empirical effectiveness, or claim
paper readiness.

## Purpose

The annotation worklist records one work item per pilot transcript. A future
annotator still needs a stable template that names the required rubric fields,
ties the label form back to a specific work item, and records source hashes.

The label-template builder creates one template per work item. The template
contains only placeholders for the required label fields and rationale spans.
Completed annotation records are still governed by
[`annotation-schema.yaml`](../evals/empirical/annotation-schema.yaml) and must
be validated later as part of an evidence package.

## Package Contract

Each `annotation-templates/*.json` record contains:

- template and source work-item identifiers;
- run, task, condition, and repeat metadata copied from the work item;
- annotation guideline version;
- required label field names copied from the work item;
- label placeholders set to `__unlabeled__`;
- rationale span placeholder requirements;
- the source transcript span identifier;
- redaction status.

The scorer rejects missing templates, templates that do not match their source
work items, duplicate templates, non-placeholder label values, injected
annotation records, aggregate metrics, paper-readiness fields, source hash
tampering, non-JSON sensitive files, and credentials or private paths.

## Structural Verification

Run after producing an annotation worklist:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-label-template-package.ps1 -WorklistRoot dist/empirical-annotation-worklist -OutputRoot dist/empirical-label-template-package -Force
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-label-template-package.ps1 -WorklistRoot dist/empirical-annotation-worklist -TemplatePackageRoot dist/empirical-label-template-package
```

For self-tests without persistent generated files, model/API calls, real
labels, or external services, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-label-template-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-label-template-package.ps1 -SelfTest
```

The self-tests build a temporary local fixture pilot package, derive an
annotation worklist, derive label templates, validate one template per work
item, reject non-placeholder label values, mismatched work-item fields,
duplicate templates, metadata hash tampering, non-JSON sensitive files, and
`-Force` overwrite attempts over non-generated files, then remove temporary
files.

## Current Nonclaims

This repository does not yet claim:

- completed human annotations;
- completed LLM-judge annotations;
- completed rule-based labels;
- agreement measurements;
- aggregate metrics;
- statistical results;
- empirical effectiveness;
- paper readiness;
- production safety;
- annotator quality or judge validity.
