# Related Work And Limitations

<!-- claim_ceiling: related_work_and_limitations_present_and_ci_verified -->

Status: Related-work and limitations map for the public Agent Decision Gates
paper path. This document positions the current design-pattern package against
nearby research areas and records what must still be tested before any empirical
paper claim. It does not report model/API results, human labels, agreement
measurements, statistical significance, production safety, or paper readiness.

## Purpose

The public package should not be framed as "multi-agent review is new." That
space is already crowded. The more defensible contribution is narrower:

```text
evidence-bounded claim governance for agentic workflows
```

In this framing, the important question is whether claim ceilings and
decision-bearing gates reduce unsupported readiness, overclaim, objective
narrowing, stale-source reliance, and human-checkpoint bypass in repository-bound
agent workflows.

## Positioning

| area | representative work | relationship to this repository |
| --- | --- | --- |
| Self-feedback and iterative refinement | [Self-Refine](https://arxiv.org/abs/2303.17651), [Reflexion](https://arxiv.org/abs/2303.11366) | These methods use feedback or reflection to improve an answer or future attempt. Agent Decision Gates instead bounds the claim that may be made from checked evidence. |
| Multi-sample and debate methods | [Self-Consistency](https://arxiv.org/abs/2203.11171), [AI Safety via Debate](https://arxiv.org/abs/1805.00899), [Multiagent Debate](https://arxiv.org/abs/2305.14325) | Debate and sampling seek better answers or judgments from multiple paths. This project uses counter-review as one input to an adjudicated claim ceiling, not as proof that the final answer is correct. |
| Process supervision and verification | [Let's Verify Step by Step](https://arxiv.org/abs/2305.20050) | Process supervision evaluates intermediate reasoning. This repo records a lighter workflow-control pattern and deterministic public-surface checks, not a trained reward model or proof of step correctness. |
| Tool-using and repository-bound agents | [ReAct](https://arxiv.org/abs/2210.03629), [Toolformer](https://arxiv.org/abs/2302.04761), [SWE-agent](https://arxiv.org/abs/2405.15793) | These works improve an agent's ability to act with tools or software environments. Agent Decision Gates addresses the decision boundary before claims, pushes, releases, or authority expansion. |
| Model alignment and rule-following | [Constitutional AI](https://arxiv.org/abs/2212.08073) | Constitutional AI uses principles and AI feedback in model behavior. This repository is a local workflow pattern; it does not train or align a model. |
| LLM-as-judge evaluation | [Judging LLM-as-a-Judge](https://arxiv.org/abs/2306.05685) | LLM judges can help scale review, but their agreement and bias must be measured. This repo treats LLM-judge labels as insufficient for paper claims unless compared with human or comparable reviewer labels. |
| Self-correction limitations | [Large Language Models Cannot Self-Correct Reasoning Yet](https://arxiv.org/abs/2310.01798) | This motivates the fail-closed stance: same-context critique or unsupported self-correction should not be treated as independent decision evidence. |

## Claimed Distinction

The current distinction is not that the package invented critique, debate,
self-review, or agent tooling. The claimed distinction is a workflow discipline:

- every decision-bearing answer must map checked evidence to the narrowest
  supported claim;
- counter-review challenges framing, stale sources, route leakage, and overclaim
  before parent adjudication;
- deterministic checks support only the narrow structural claim they encode;
- human checkpoints remain human-owned when the next action changes public,
  legal, destructive, financial, privacy, or authority boundaries;
- missing independence, missing labels, or missing metrics must reduce the claim
  ceiling instead of being hidden by confident wording.

This distinction is still a hypothesis for empirical study. It becomes stronger
only if measured against baselines and ablations.

## Limits Of The Current Evidence

The current public repository can support only a bounded artifact claim:

- public skill and documentation surfaces exist;
- deterministic public-surface verification and scorer self-tests exist;
- eval fixtures and empirical schemas are structurally checked;
- a local ignored pilot and preliminary LLM-judge-only route exist as pipeline
  smoke evidence, not public paper evidence;
- public CI runs deterministic checks, not model/API experiments.

The current evidence does not support:

- reduced false readiness rate;
- reduced overclaim rate;
- reduced objective narrowing rate;
- improved human-checkpoint recall;
- real human/LLM agreement;
- judge validity;
- statistically powered aggregate metrics;
- production safety;
- peer-reviewed paper readiness.

## Methodological Risks

The paper path must handle these risks directly:

- same-provider or same-model reviewers can share correlated blind spots;
- same-context self-critique is weaker than a separate review path;
- parent adjudication can still inherit the parent thread's framing bias;
- deterministic verifiers check only encoded rules and can miss semantic
  overclaim;
- prompt-level STOP conditions are governance rules, not hard enforcement;
- LLM judges can be useful but may have position, verbosity, style, and
  self-preference biases;
- small pilots can validate the pipeline without supporting general effects;
- synthetic or redacted repository tasks may not represent live production
  workflows;
- public evidence packages must avoid private-source export and credential
  leakage;
- cost, latency, retries, and failed runs must be reported rather than filtered
  out.

## Evidence Needed Before A Paper Claim

Before this project is described as an empirical paper contribution, it needs:

1. A frozen public task suite with hashes.
2. Frozen condition prompts and run-input records.
3. Baselines and ablations covering no gate, checklist-only, self-review,
   same-context critique, separate counter-review, claim ceiling only,
   counter-review only, full consult gate, and programmatic gate variants.
4. Repeated runs with model/provider/runtime identifiers.
5. Raw transcripts and cost/latency telemetry.
6. Human labels or comparable reviewer labels for the core metrics.
7. LLM-judge labels only with measured agreement and bias discussion.
8. Aggregate metrics with confidence intervals or clearly bounded descriptive
   statistics.
9. Failure-case analysis and negative results.
10. A limitations section that keeps claims scoped to the tested tasks, models,
    prompts, and runtime conditions.

Until that package exists, this repository should be described as a public
design-pattern package with structural verifier, CI, and experiment scaffolding,
not as a proven agent-safety framework.
