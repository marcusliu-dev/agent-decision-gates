# Experiment Run Packet

<!-- claim_ceiling: empirical_run_packet_schema_present_and_structurally_scored -->

Status: Structural run-packet specification for future empirical experiments.
This document defines the artifacts that must exist before model/API evaluation
runs. It does not execute model/API evals, report results, or claim paper
readiness. No private repository material may be required for public
reproduction.

## Purpose

The empirical evaluation plan defines what should be measured. The run packet
defines what must be frozen before measurement starts. This prevents a later
paper claim from resting on mutable prompts, ambiguous task versions, missing
transcripts, unlabeled outputs, or unrecorded cost and latency. The run packet
itself cannot claim paper readiness.

## Required Public Packet

The current structural run packet contains:

- [`experiment-run-manifest.yaml`](../evals/empirical/experiment-run-manifest.yaml)
  for the planned conditions, artifact requirements, and stop gates;
- [`transcript-schema.yaml`](../evals/empirical/transcript-schema.yaml) for raw
  run transcript shape;
- [`annotation-schema.yaml`](../evals/empirical/annotation-schema.yaml) for
  human and judge labels;
- [`empirical-annotation-guidelines.md`](empirical-annotation-guidelines.md) for
  the future label rubric and agreement route;
- [`condition-prompt-pack.yaml`](../evals/empirical/condition-prompt-pack.yaml)
  and [`condition-prompt-pack.md`](condition-prompt-pack.md) for the frozen
  condition prompt surface;
- [`run-input-schema.yaml`](../evals/empirical/run-input-schema.yaml),
  [`empirical-run-inputs.md`](empirical-run-inputs.md),
  [`build-empirical-run-inputs.ps1`](../scripts/build-empirical-run-inputs.ps1),
  and [`score-empirical-run-inputs.ps1`](../scripts/score-empirical-run-inputs.ps1)
  for materializing and checking pre-execution run-input records;
- [`execution-preflight-schema.yaml`](../evals/empirical/execution-preflight-schema.yaml),
  [`empirical-execution-preflight.md`](empirical-execution-preflight.md),
  [`build-empirical-execution-preflight.ps1`](../scripts/build-empirical-execution-preflight.ps1),
  and [`score-empirical-execution-preflight.ps1`](../scripts/score-empirical-execution-preflight.ps1)
  for recording pilot run-input selection, provider, model alias, runtime
  surface, budget, and source hashes before any model/API eval execution;
- [`mock-execution-package-schema.yaml`](../evals/empirical/mock-execution-package-schema.yaml),
  [`empirical-mock-execution-package.md`](empirical-mock-execution-package.md),
  [`build-empirical-mock-execution-package.ps1`](../scripts/build-empirical-mock-execution-package.ps1),
  and [`score-empirical-mock-execution-package.ps1`](../scripts/score-empirical-mock-execution-package.ps1)
  for exercising synthetic transcript and cost-latency package joins before
  any model/API eval execution;
- [`runner-response-schema.yaml`](../evals/empirical/runner-response-schema.yaml),
  [`empirical-runner-contract.md`](empirical-runner-contract.md),
  and [`score-empirical-runner-response.ps1`](../scripts/score-empirical-runner-response.ps1)
  for validating one local/private runner response before it is wrapped into
  a pilot transcript and cost-latency record;
- [`pilot-execution-package-schema.yaml`](../evals/empirical/pilot-execution-package-schema.yaml),
  [`empirical-pilot-execution-runner.md`](empirical-pilot-execution-runner.md),
  [`build-empirical-pilot-execution-package.ps1`](../scripts/build-empirical-pilot-execution-package.ps1),
  and [`score-empirical-pilot-execution-package.ps1`](../scripts/score-empirical-pilot-execution-package.ps1)
  for executing selected pilot inputs through an explicitly allowed local
  runner script and validating the resulting transcript/cost-latency package
  before annotation or metric claims;
- [`empirical-pilot-run-chain.md`](empirical-pilot-run-chain.md) and
  [`build-empirical-pilot-run-chain.ps1`](../scripts/build-empirical-pilot-run-chain.ps1)
  for running the first-pilot chain from run inputs through execution
  preflight, explicitly allowed local-runner execution, pilot package scoring,
  annotation worklist generation, and label-template generation before
  completed labels, agreement measurements, aggregate metrics, or paper
  readiness are claimed;
- [`pilot-execution-readiness-schema.yaml`](../evals/empirical/pilot-execution-readiness-schema.yaml),
  [`empirical-pilot-execution-readiness.md`](empirical-pilot-execution-readiness.md),
  and [`check-empirical-pilot-execution-readiness.ps1`](../scripts/check-empirical-pilot-execution-readiness.ps1)
  for the pre-run pilot execution readiness gate that checks run inputs,
  execution preflight, private runner path, runner label, and required
  environment variable presence without executing the runner;
- [`annotation-worklist-schema.yaml`](../evals/empirical/annotation-worklist-schema.yaml),
  [`empirical-annotation-worklist.md`](empirical-annotation-worklist.md),
  [`build-empirical-annotation-worklist.ps1`](../scripts/build-empirical-annotation-worklist.ps1),
  and [`score-empirical-annotation-worklist.ps1`](../scripts/score-empirical-annotation-worklist.ps1)
  for deriving unlabeled future-labeling work items from pilot transcripts
  before human labels, LLM-judge labels, agreement measurements, or aggregate
  metrics are claimed;
- [`label-template-package-schema.yaml`](../evals/empirical/label-template-package-schema.yaml),
  [`empirical-label-template-package.md`](empirical-label-template-package.md),
  [`build-empirical-label-template-package.ps1`](../scripts/build-empirical-label-template-package.ps1),
  and [`score-empirical-label-template-package.ps1`](../scripts/score-empirical-label-template-package.ps1)
  for deriving fillable placeholder templates from annotation work items before
  completed labels, agreement measurements, or aggregate metrics are claimed;
- [`annotation-intake-schema.yaml`](../evals/empirical/annotation-intake-schema.yaml),
  [`empirical-annotation-intake.md`](empirical-annotation-intake.md),
  and [`score-empirical-annotation-intake.ps1`](../scripts/score-empirical-annotation-intake.ps1)
  for validating future completed annotation records against label templates,
  work items, schema, and guideline hashes before agreement or aggregate
  metrics are claimed;
- [`empirical-evidence-package-builder.md`](empirical-evidence-package-builder.md)
  and [`build-empirical-evidence-package.ps1`](../scripts/build-empirical-evidence-package.ps1)
  for assembling future pilot transcripts, cost/latency records, and completed
  annotation records into an evidence package before validation, agreement
  checks, or aggregate metrics are claimed; this evidence package builder is
  an assembly route, not a result route;
- [`evidence-package-schema.yaml`](../evals/empirical/evidence-package-schema.yaml)
  for post-run package completeness and join requirements;
- [`agreement-summary-schema.yaml`](../evals/empirical/agreement-summary-schema.yaml)
  for future human-vs-LLM-judge agreement summaries;
- [`empirical-dry-run-package.md`](empirical-dry-run-package.md) and
  [`build-empirical-dry-run-package.ps1`](../scripts/build-empirical-dry-run-package.ps1)
  for a synthetic end-to-end package exercise before any real model/API run;
- [`score-empirical-run-packet.ps1`](../scripts/score-empirical-run-packet.ps1)
  and [`score-empirical-prompt-pack.ps1`](../scripts/score-empirical-prompt-pack.ps1)
  for deterministic structural checks.

These files define the shape of a future experiment. They intentionally contain
no model outputs, pass rates, statistical results, or paper-ready conclusions.

## Freeze Requirements

Before running model/API evals, freeze:

1. task-suite version and hash;
2. condition prompts and prompt versions;
3. execution preflight record with selected run-input ids, model/provider/runtime
   identifiers, source hashes, and budget;
4. repeat count and randomization strategy;
5. transcript schema;
6. annotation schema;
7. annotation guideline version;
8. cost/latency log fields;
9. scorer version;
10. redaction and synthetic-fixture boundary;
11. budget and stop conditions.

Any change after the freeze creates a new experiment version.

## Artifact Contract

Every future executed run should produce:

- one raw transcript record;
- one cost/latency record;
- one model/runtime metadata record;
- explicit runner-reported `input_tokens`, `output_tokens`, `api_cost_usd`,
  and `retry_count` before pilot package wrapping;
- at least one label record;
- the annotation guideline version used for each label record;
- links from label rationale fields to transcript spans;
- a run id that joins transcript, labels, cost, and metadata.

Aggregate results should be computed only after transcript and label completeness
are verified.

## Stop Gates

Stop before execution if:

- private repository material is required for reproduction;
- task prompts or condition prompts are not frozen;
- the condition_prompt_pack_available stop gate is not satisfied;
- the run_input_builder_available stop gate is not satisfied;
- the execution_preflight_available stop gate is not satisfied;
- the mock_execution_package_builder_available stop gate is not satisfied;
- the runner response contract is needed but the runner_response_contract_available stop gate is not satisfied;
- the pilot execution runner route is needed but the pilot_execution_runner_available stop gate is not satisfied;
- the first-pilot chain is needed but the pilot_run_chain_builder_available stop gate is not satisfied;
- pilot execution readiness is needed but the pilot_execution_readiness_checker_available stop gate is not satisfied;
- required environment variables are not checked before execution;
- the annotation worklist route is needed but the annotation_worklist_builder_available stop gate is not satisfied;
- the label-template package route is needed but the label_template_package_builder_available stop gate is not satisfied;
- completed annotations need intake validation but the annotation_intake_validator_available stop gate is not satisfied;
- an evidence package needs assembly but the evidence_package_builder_available stop gate is not satisfied;
- budget is not recorded;
- transcript fields are missing;
- annotation guideline version is missing;
- the dry_run_package_builder_available stop gate is not satisfied;
- annotation labels cannot cite transcript spans;
- the route would imply paper readiness before measured results exist;
- any artifact asks for result fields before runs are complete.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-prompt-pack.ps1
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-run-inputs.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-run-inputs.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-execution-preflight.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-execution-preflight.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-mock-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-mock-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-runner-response.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-pilot-execution-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-pilot-run-chain.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/check-empirical-pilot-execution-readiness.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-annotation-worklist.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-worklist.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-label-template-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-label-template-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-annotation-intake.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-evidence-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-run-packet.ps1
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-agreement.ps1 -SelfTest
powershell -ExecutionPolicy Bypass -File scripts/build-empirical-dry-run-package.ps1 -SelfTest
```

Those commands check only the packet structure, run-input builder/scorer
self-tests, execution preflight builder/scorer self-tests, evidence-package
validator self-test, agreement-checker self-test, the synthetic mock execution
package builder/scorer self-tests, the runner response contract scorer
self-test, the pilot execution runner package builder/scorer self-tests, the
pilot run chain builder self-test, the pilot execution readiness checker
self-test, the
annotation worklist builder/scorer self-tests, the label-template package
builder/scorer self-tests, the annotation-intake scorer self-test, the
evidence-package builder self-test, and the synthetic
dry-run package builder self-test. This
includes the synthetic dry-run package builder self-test.
The synthetic mock execution package and synthetic
dry-run package builder self-test are not real experiment outputs. The runner
response scorer self-test validates fixture response JSON only and does not call
hosted model APIs. The pilot execution runner self-test uses a temporary local
fixture runner and does not call hosted model APIs. The pilot run chain self-test
also uses a temporary local fixture runner and prepares downstream unlabeled
work items and placeholder templates only. The annotation worklist self-tests produce unlabeled
work items only. The label-template package self-tests produce placeholders
only. The annotation-intake scorer self-test uses synthetic completed-label
fixtures only. The evidence-package builder self-test assembles synthetic
source packages only. They do not score real annotated completed transcripts,
measure real agreement, or prove empirical effectiveness.
The synthetic mock execution package remains a package-shape exercise only.

## Current Nonclaims

This packet does not prove:

- model/API eval execution;
- validated real runner responses;
- human or LLM-judge annotation labels;
- false-readiness or overclaim rates;
- cost/latency measurements;
- human/LLM-judge agreement;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
