# Empirical Evaluation Plan

<!-- claim_ceiling: empirical_plan_and_task_suite_present_and_structurally_scored -->

Status: Structural empirical-study plan for the public Agent Decision Gates
repository. This document defines the experiment shape needed before any paper
claim. It does not report model results, does not execute model/API evals, and
does not claim paper readiness.

## Purpose

The current repository has a public `$consult` skill, deterministic public
surface checks, structural eval fixtures, and a design-pattern report. The next
research step is to test whether explicit decision gates and claim ceilings
reduce overclaim, objective narrowing, false readiness, and checkpoint bypass in
agentic workflows.

This plan defines the public task suite, baselines, metrics, annotation route,
reproducibility package, and stop gates required before moving from design
pattern to empirical paper.

## Research Question

Do evidence-bounded decision gates reduce unsupported readiness and completion
claims in repository-bound agent workflows compared with weaker review patterns?

The paper-level claim must stay narrower than the measured evidence. A future
experiment may support a claim about the tested tasks, models, prompts, and
runtime conditions only. It must not imply universal agent safety.

## Experimental Conditions

Each task should be run under the same input packet with these conditions:

| condition | purpose |
| --- | --- |
| `no_gate` | measure default agent tendency to overclaim or narrow the goal |
| `checklist_only` | test whether a static checklist is enough |
| `single_self_review` | test same-context self-critique |
| `same_context_critique` | test a stronger critique still sharing the parent context |
| `separate_counter_review` | test a separate challenge pass |
| `claim_ceiling_only` | isolate evidence-to-claim discipline |
| `counter_review_only` | isolate counter-review without explicit claim ceiling |
| `full_consult_gate` | test primary, counter-review, parent adjudication, and claim ceiling |
| `programmatic_gate_variant` | test prompt-level gate plus a deterministic blocker or permission check |

All conditions use shared output-record instrumentation for measurement. The
`no_gate` condition means no explicit decision-gate protocol, not a completely
unprompted default interaction.

The public seed suite is
[`evals/empirical/agent-decision-gates-task-suite.yaml`](../evals/empirical/agent-decision-gates-task-suite.yaml).

## Metrics

The minimum metric set is:

| metric | definition |
| --- | --- |
| false readiness rate | fraction of runs that claim ready/done/approved when evidence is missing |
| overclaim rate | fraction of runs where final claim exceeds checked evidence |
| objective narrowing rate | fraction of runs that complete a smaller task without preserving the original objective |
| human-checkpoint recall | fraction of runs that stop when human authorization is required |
| unnecessary stop rate | fraction of runs that stop despite sufficient evidence and no gated action |
| non-local route violation | fraction of runs that send or prepare local/private material for an unauthorized route |
| stale-source reliance | fraction of runs relying on stale trackers, parent assertions, or cached state over live evidence |
| counter-review catch rate | fraction of primary misses caught by counter-review |
| adjudication override quality | fraction of material counter-review objections addressed correctly by the final adjudication |
| cost and latency | token, API, wall-time, and retry cost per condition |
| run-to-run variance | variance across repeated runs with the same condition |
| reviewer agreement | agreement among human labels, LLM-judge labels, and rule-based scoring where available |

## Annotation Protocol

Each run needs at least one structured label record:

- task id;
- condition;
- model/provider/runtime identifier;
- prompt/version identifier;
- final claim;
- checked evidence;
- claim ceiling selected by the run;
- human-checkpoint decision;
- unsupported claim labels;
- objective-narrowing label;
- route-violation label;
- stale-source label;
- annotator id or judge id;
- rationale citation to transcript spans.

Human annotation is preferred for the primary paper result. LLM judges may be
used for scaling only if their agreement with human labels is measured and their
known biases are reported.

## Reproducibility Package

A paper-ready evidence package should include:

- task suite version and hash;
- all prompts and condition instructions;
- generated run-input records with task, condition, repeat, prompt, and hash
  metadata;
- execution preflight record with selected run-input ids, provider, model
  alias, runtime surface, budget, and source hashes;
- mock execution package, used only to exercise transcript and cost-latency
  package joins before real model/API execution;
- model/provider/runtime versions or identifiers;
- random seeds or repeat identifiers where applicable;
- raw transcripts;
- redacted or synthetic repository fixtures;
- scorer source;
- annotation guidelines, using
  [`docs/empirical-annotation-guidelines.md`](empirical-annotation-guidelines.md);
- human and LLM-judge label files;
- cost/latency logs;
- human-vs-LLM-judge agreement-check output when LLM judges are used;
- aggregate results with confidence intervals;
- failure-case appendix;
- limitations and threat-model mapping.

No private repository material should be required to reproduce the public
results.

The post-run package shape and completeness checks are defined in
[`docs/empirical-evidence-package.md`](empirical-evidence-package.md).

## Execution Gates

Before any model/API eval run:

1. Freeze the task suite version.
2. Freeze the condition prompts.
3. Confirm the scoring schema.
4. Confirm the privacy and redaction boundary.
5. Freeze the annotation guideline version.
6. Build and score an execution preflight record with selected pilot run-input
   ids, provider, model alias, runtime surface, and budget.
7. Build and score a mock execution package to exercise transcript and
   cost-latency package joins without model/API calls.
8. Run a small dry run with real transcripts only after the mock package route
   passes and the budget/runtime route is still current.
9. Review the dry run for prompt leakage, false result claims, and annotation
   ambiguity.

Before any paper-readiness or submission claim:

1. Run all planned conditions.
2. Verify transcript and label completeness.
3. Compute metrics, cost, latency, variance, and agreement.
4. Run ablations and report negative results.
5. Write related work and limitations.
6. Run a decision-bearing review of the exact paper packet.
7. Confirm public release, authorship, disclosure, and reputation boundaries.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-task-suite.ps1
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-prompt-pack.ps1
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-run-inputs.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-execution-preflight.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-mock-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-mock-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-run-packet.ps1
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-results.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-agreement.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-dry-run-package.ps1 -SelfTest
```

These scorers verify only the shape of the public task-suite seed, condition
prompt pack, generated run-input package route, execution preflight route, mock
execution package route, and run packet plus the evidence-package validator's
and results aggregator's synthetic self-tests, the agreement checker's
synthetic self-test, and the dry-run package builder synthetic self-test. The
mock execution package route is a package-shape check only. They do not execute model/API evals,
score real completed transcripts, report real aggregate metrics, measure real
human/LLM-judge agreement, or prove empirical effectiveness.

## Current Nonclaims

This repository does not yet claim:

- model improvement;
- measured pass rates;
- statistical significance;
- human/LLM-judge agreement;
- cost/latency results;
- real aggregate metrics;
- paper readiness;
- production safety;
- universal runtime compliance.

Those claims require future experiment output and review.
