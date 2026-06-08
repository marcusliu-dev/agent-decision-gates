# Agent Decision Gates

<!-- claim_ceiling: empirical_pilot_execution_runner_present_and_self_tested -->

Evidence-first decision gates for AI agents: independent challenge reviews,
human checkpoints, and verification before high-risk actions.

This repository packages both a public decision-gate reference and a reusable
`$consult` skill for teams that want stronger decision discipline around
AI-agent workflows. It is designed for moments when a model or execution lane
is about to make an expensive decision: publish, ship, claim completion,
expand scope, accept risk, or act on ambiguous evidence.

## Why This Exists

Many agent workflows fail in the same way:

- execution silently narrows the real goal;
- one green check gets stretched into a broader readiness claim;
- a draft artifact gets mistaken for proof of completion;
- no one clearly owns the final risky decision.

This repo packages a simple alternative:

1. Frame the real decision question.
2. Gather the smallest sufficient evidence.
3. Run a primary analysis.
4. Run an independent challenge pass.
5. Make a bounded adjudication and record what remains blocked.

## Who This Is For

- teams running AI agents against real repositories or operations workflows;
- developers building human-in-the-loop controls for agentic systems;
- researchers who want explicit decision and verification boundaries;
- anyone who needs claims to stay narrower than the evidence.

## What You Get

- an installable or directly reusable [`$consult` skill package](skills/consult/SKILL.md);
- a machine-readable skill config in
  [`skills/consult/agents/openai.yaml`](skills/consult/agents/openai.yaml);
- public eval fixtures under [`evals/consult/`](evals/consult/);
- a short [glossary](docs/glossary.md) for the core terms;
- a runtime-neutral [core protocol](docs/core-protocol.md);
- [Codex adapter notes](docs/codex-adapter.md) for the packaged skill;
- a [threat model](docs/threat-model.md);
- a [roles and permissions matrix](docs/roles-and-permissions.md);
- [eval evidence guidance](docs/eval-evidence.md) and a deterministic fixture
  scorer in [`scripts/score-eval-fixtures.ps1`](scripts/score-eval-fixtures.ps1);
- a design-pattern [deep-dive report](docs/deep-dive-report.md) on claim
  ceilings for agentic workflows;
- an [empirical evaluation plan](docs/empirical-evaluation-plan.md), a public
  seed [task suite](evals/empirical/agent-decision-gates-task-suite.yaml), and
  a structural task-suite scorer in
  [`scripts/score-empirical-task-suite.ps1`](scripts/score-empirical-task-suite.ps1);
- a versioned [condition prompt pack](docs/condition-prompt-pack.md) and
  structural scorer in
  [`scripts/score-empirical-prompt-pack.ps1`](scripts/score-empirical-prompt-pack.ps1)
  for freezing future experimental condition instructions before any model/API
  eval run;
- an [empirical run-input package guide](docs/empirical-run-inputs.md), schema,
  builder, and scorer for materializing fixed task-condition-repeat inputs
  before any model/API eval execution;
- an [empirical execution preflight guide](docs/empirical-execution-preflight.md),
  schema, builder, and scorer for recording the pilot run selection, provider,
  model alias, runtime surface, and budget before any model/API eval execution;
- an [empirical mock execution package guide](docs/empirical-mock-execution-package.md),
  schema, builder, and scorer for exercising transcript and cost-latency package
  joins without real model/API eval execution;
- an [empirical pilot execution runner guide](docs/empirical-pilot-execution-runner.md),
  schema, builder, and scorer for routing selected pilot inputs through an
  explicitly allowed local runner script and validating transcript/cost-latency
  outputs before labels or metrics are claimed;
- an [experiment run packet](docs/experiment-run-packet.md), transcript and
  annotation schemas under [`evals/empirical/`](evals/empirical/), and a
  structural run-packet scorer in
  [`scripts/score-empirical-run-packet.ps1`](scripts/score-empirical-run-packet.ps1);
- [empirical annotation guidelines](docs/empirical-annotation-guidelines.md)
  for future human, LLM-judge, and rule-based labels;
- an [empirical evidence-package guide](docs/empirical-evidence-package.md),
  evidence-package schema, and a synthetic self-test validator in
  [`scripts/score-empirical-evidence-package.ps1`](scripts/score-empirical-evidence-package.ps1);
- an [empirical results-analysis guide](docs/empirical-results-analysis.md),
  results-summary schema, and a synthetic self-test aggregator in
  [`scripts/score-empirical-results.ps1`](scripts/score-empirical-results.ps1);
- an [empirical agreement-checks guide](docs/empirical-agreement-checks.md),
  agreement-summary schema, and a synthetic self-test checker in
  [`scripts/score-empirical-agreement.ps1`](scripts/score-empirical-agreement.ps1);
- a [synthetic empirical dry-run package guide](docs/empirical-dry-run-package.md)
  and builder in
  [`scripts/build-empirical-dry-run-package.ps1`](scripts/build-empirical-dry-run-package.ps1)
  for exercising the package validator, results aggregator, and agreement
  checker without model/API eval execution;
- a reusable [consult protocol](docs/consult-protocol.md);
- [human checkpoint rules](docs/human-checkpoints.md) for high-risk actions;
- [verification guidance](docs/verification-and-safety.md) for keeping claims
  aligned with evidence;
- a fictional [stage-gate example](examples/consult-stage-gate.md);
- a lightweight public-surface integrity verifier in
  [`scripts/verify-public-safety.ps1`](scripts/verify-public-safety.ps1);
- a small [tracker](TRACKER.md) and [release record](docs/release-readiness.md)
  for keeping state honest.

## Quick Start

If your Codex runtime has the `skill-installer` skill, ask Codex:

```text
$skill-installer install the consult skill from github repo marcusliu-dev/agent-decision-gates path skills/consult
```

If you are installing manually from a local clone, copy the skill directory into
your Codex skills directory.

PowerShell:

```powershell
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$SkillTarget = Join-Path $CodexHome "skills\consult"
New-Item -ItemType Directory -Force -Path $SkillTarget | Out-Null
Copy-Item -Recurse -Force "skills\consult\*" $SkillTarget
```

macOS/Linux shell:

```sh
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills/consult"
cp -R skills/consult/. "${CODEX_HOME:-$HOME/.codex}/skills/consult/"
```

After installation, restart Codex and invoke the skill explicitly with
`$consult`.

If you want to adapt the underlying pattern:

1. Write down the exact decision question.
2. Separate verified facts from assumptions.
3. Read only the smallest live surfaces that can answer the question.
4. Run a primary pass and an independent challenge pass.
5. Record what is allowed now, what is still blocked, and the exact claim
   ceiling supported by the evidence.

For decision-bearing consults, the reference workflow prefers independent
spawned agents at the strongest model and highest reasoning effort your runtime
supports. In the example workflow here, that means `gpt-5.5` with `xhigh`
when available. If your runtime cannot supply that route, record what actually
ran and fail closed when independence materially matters. Inline self-challenge
can document uncertainty, but it cannot approve a decision-bearing step that
requires independent review.

## Repository Guide

- Start with [`skills/consult/SKILL.md`](skills/consult/SKILL.md) if you want
  the installable skill artifact.
- Start with [docs/core-protocol.md](docs/core-protocol.md) if you want the
  runtime-neutral pattern.
- Read [docs/codex-adapter.md](docs/codex-adapter.md) if you are installing
  the packaged Codex skill.
- Use [docs/glossary.md](docs/glossary.md) for terminology.
- Start with [docs/consult-protocol.md](docs/consult-protocol.md) for the
  original compact protocol guide.
- Then read [docs/human-checkpoints.md](docs/human-checkpoints.md).
- Check [docs/threat-model.md](docs/threat-model.md) and
  [docs/roles-and-permissions.md](docs/roles-and-permissions.md) before
  adapting the pattern to higher-risk workflows.
- Use [docs/eval-evidence.md](docs/eval-evidence.md) if you want to inspect
  the public fixture evidence surface.
- Read [docs/deep-dive-report.md](docs/deep-dive-report.md) for the
  design-pattern rationale and research-evidence boundary.
- Read [docs/empirical-evaluation-plan.md](docs/empirical-evaluation-plan.md)
  for the future paper experiment design and current no-results boundary.
- Read [docs/condition-prompt-pack.md](docs/condition-prompt-pack.md) for the
  frozen condition instructions required before any future model/API eval run.
- Read [docs/empirical-run-inputs.md](docs/empirical-run-inputs.md) for the
  pre-execution run-input records that future model/API evals should consume.
- Read [docs/empirical-execution-preflight.md](docs/empirical-execution-preflight.md)
  for the pre-execution pilot-selection, runtime, and budget gate required
  before any future model/API eval run.
- Read [docs/empirical-mock-execution-package.md](docs/empirical-mock-execution-package.md)
  for the synthetic transcript/cost-latency package route that exercises the
  execution artifact contract before real model/API eval runs.
- Read [docs/empirical-pilot-execution-runner.md](docs/empirical-pilot-execution-runner.md)
  for the explicit local-runner route that can produce pilot transcript and
  cost-latency packages without storing credentials or private runner code in
  this public repository.
- Read [docs/experiment-run-packet.md](docs/experiment-run-packet.md) for the
  frozen-artifact contract required before any future model/API eval run.
- Read [docs/empirical-annotation-guidelines.md](docs/empirical-annotation-guidelines.md)
  for the future annotation rubric and agreement route.
- Read [docs/empirical-evidence-package.md](docs/empirical-evidence-package.md)
  for the post-run package completeness checks required before result analysis.
- Read [docs/empirical-results-analysis.md](docs/empirical-results-analysis.md)
  for the bounded metric aggregation route that remains synthetic-only today.
- Read [docs/empirical-agreement-checks.md](docs/empirical-agreement-checks.md)
  for the future human-vs-LLM-judge agreement route that remains synthetic-only
  today.
- Read [docs/empirical-dry-run-package.md](docs/empirical-dry-run-package.md)
  for the synthetic end-to-end package route that remains non-empirical today.
- Use [docs/verification-and-safety.md](docs/verification-and-safety.md) to
  match claims to evidence.
- Read [examples/consult-stage-gate.md](examples/consult-stage-gate.md) for a
  compact worked example.
- See [docs/provenance.md](docs/provenance.md) for authorship and source
  boundaries.

## Design Principles

- Evidence first.
- Execution and decision authority are separate concerns.
- Human-only gates stay explicit for high-risk actions.
- Independence matters when the decision is consequential.
- A narrow verifier can support only a narrow claim.

## Project Status

This is a published public repository with a reusable `$consult` skill package,
public eval fixtures, documentation, a design-pattern report, an empirical
evaluation plan, experiment run-packet schemas, an evidence-package validator,
a results aggregator, empirical annotation guidelines, an agreement checker, a
synthetic dry-run package builder, a versioned condition prompt pack, and
deterministic structural scorers under `MIT`, plus a pre-execution run-input
package builder for fixed task-condition-repeat records and an execution
preflight builder for recording the pilot selection, provider, model alias,
runtime surface, and budget before execution, plus a mock execution package
builder for transcript/cost-latency package joins, plus a pilot execution
runner package builder for explicitly allowed local runner scripts. The current
ceiling is no higher than `empirical_pilot_execution_runner_present_and_self_tested`. The
verifiers and scorers do not prove production safety, empirical effectiveness,
paper readiness, executed model/API evals, real transcripts, real labels, real
human/LLM-judge agreement, real aggregate metrics, or universal runtime
correctness. The dry-run package is synthetic evidence-shape exercise only. The
condition prompt pack freezes planned instructions only. The run-input builder
materializes pre-execution inputs only. The execution preflight records a future
pilot run gate only. The mock execution package is synthetic package-shape
evidence only. The pilot execution runner self-test uses a local fixture runner
and does not by itself establish real empirical results. The repository
intentionally does not ship CI, deployment automation, application
source scaffolding, model/API eval results, or a broader framework/runtime
product surface.

If this pattern is useful in your own agent workflows, adapt it, improve it,
and make the decision boundaries explicit in your own systems.
