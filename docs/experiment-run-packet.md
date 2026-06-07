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
- [`evidence-package-schema.yaml`](../evals/empirical/evidence-package-schema.yaml)
  for post-run package completeness and join requirements;
- [`score-empirical-run-packet.ps1`](../scripts/score-empirical-run-packet.ps1)
  for deterministic structural checks.

These files define the shape of a future experiment. They intentionally contain
no model outputs, pass rates, statistical results, or paper-ready conclusions.

## Freeze Requirements

Before running model/API evals, freeze:

1. task-suite version and hash;
2. condition prompts and prompt versions;
3. model/provider/runtime identifiers;
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
- budget is not recorded;
- transcript fields are missing;
- annotation guideline version is missing;
- annotation labels cannot cite transcript spans;
- the route would imply paper readiness before measured results exist;
- any artifact asks for result fields before runs are complete.

## Structural Verification

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-run-packet.ps1
powershell -ExecutionPolicy Bypass -File scripts/score-empirical-evidence-package.ps1 -SelfTest
```

Those commands check only the packet structure and evidence-package validator
self-test. They do not run models, call APIs, score real completed transcripts,
or prove empirical effectiveness.

## Current Nonclaims

This packet does not prove:

- model/API eval execution;
- false-readiness or overclaim rates;
- cost/latency measurements;
- human/LLM-judge agreement;
- statistical significance;
- empirical effectiveness;
- paper readiness;
- production safety.
