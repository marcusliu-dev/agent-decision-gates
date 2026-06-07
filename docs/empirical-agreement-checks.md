# Empirical Agreement Checks

<!-- claim_ceiling: empirical_agreement_checker_present_and_self_tested -->

Status: Synthetic-self-tested human-vs-LLM-judge agreement route for future
empirical evidence packages. This document defines how future human and
LLM-judge annotations can be compared before any judge-dependent result claim.
It does not execute model/API evals, include real transcripts, include real
labels, measure real agreement, prove judge validity, or claim paper readiness.

## Purpose

The empirical results analyzer can compute aggregate metrics from validated
annotation records. Paper-level claims also need a defensible reliability route
when LLM-judge labels are used. The agreement checker is that narrow route: it
compares human annotations with LLM-judge annotations for the same run and label
fields, reports exact label agreement, and records the bias limitations that
must remain visible in any future interpretation.

Use this guide with:

- [`empirical-annotation-guidelines.md`](empirical-annotation-guidelines.md);
- [`annotation-schema.yaml`](../evals/empirical/annotation-schema.yaml);
- [`agreement-summary-schema.yaml`](../evals/empirical/agreement-summary-schema.yaml);
- [`empirical-evidence-package.md`](empirical-evidence-package.md).

## Checker

Run the synthetic self-test with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-agreement.ps1 -SelfTest
```

That command creates temporary synthetic evidence packages, validates them with
[`score-empirical-evidence-package.ps1`](../scripts/score-empirical-evidence-package.ps1),
computes a human-vs-LLM-judge exact-label agreement summary, verifies expected
synthetic agreement values, rejects an invalid package before agreement
analysis, rejects missing human/LLM pairs when a pair is required, rejects low
agreement when a threshold is required, confirms the output does not expose the
temporary package path, and removes the temporary files.

For a future real evidence package, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-agreement.ps1 -PackageRoot path\to\evidence-package -RequireHumanLlmPairs -MinimumAgreementRate 0.8
```

The threshold is a study-design choice, not a universal standard. The checker
only enforces the threshold passed to it.

## Agreement Semantics

The checker compares only human annotations against LLM-judge annotations for
the same `run_id`. It does not compare human-vs-human, LLM-vs-LLM, or
rule-based labels. Rule-based annotations may still be useful as deterministic
checks, but they are not evidence of human/LLM-judge agreement.

The current checker reports:

- a content-derived `package_id` instead of a raw local package path;
- compared run count;
- human-vs-LLM exact-label agreement rate;
- human-vs-LLM label comparisons and matches;
- human, LLM-judge, and rule-based annotation counts;
- an unavailable-reason field when no comparable human/LLM pairs exist;
- known judge-bias limitations that future reports must carry forward.

Labels marked `not_applicable` or `insufficient_evidence` by either annotator
are excluded from exact-label agreement comparisons for that field.

## Bias Limitations

Any future judge-dependent claim must report at least these limitations:

- verbosity bias;
- position bias;
- self-enhancement bias;
- correlated model failure;
- rubric drift;
- missing or weak human ground truth.

The checker can make those limitations structurally visible. It cannot prove
that an LLM judge is unbiased or valid for a domain.

## Stop Conditions

Stop before using agreement numbers for a result or paper claim when:

- the evidence-package validator fails;
- human annotations are absent and the claim depends on human ground truth;
- LLM-judge annotations are absent and the claim depends on judge scaling;
- no human/LLM annotation pair exists for the same run;
- agreement is below the pre-declared study threshold;
- disagreements are silently overwritten instead of preserved;
- known judge-bias limitations are omitted;
- agreement is computed only from synthetic self-test data;
- the route is described as proving empirical effectiveness or paper readiness.

## Current Nonclaims

This checker does not prove:

- model/API eval execution;
- real transcripts;
- real human labels;
- real LLM-judge labels;
- human/LLM-judge agreement on real labels;
- LLM-judge validity;
- real aggregate metrics;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
