# Claim Ceilings For Agentic Workflows

<!-- claim_ceiling: public_consult_skill_package_present_and_verifier_backed -->

Status: Design-pattern report for the current public `Agent Decision Gates`
repository surface. This report explains the pattern and its boundaries. It is
not an empirical paper, production safety proof, or runtime compliance claim.

## Summary

AI agents often fail less by doing nothing and more by claiming too much from
too little evidence. A run may create a draft and call the whole goal done, pass
one verifier and imply release readiness, or accept an old tracker as current
proof. These are decision failures, not just answer-quality failures.

Agent Decision Gates is a lightweight pattern for keeping consequential claims
bounded by the evidence that was actually checked. The central discipline is the
claim ceiling:

```text
claim made now <= evidence checked now
```

The pattern combines a framed decision question, a source map, primary review,
counter-review, parent adjudication, human checkpoints, and deterministic
verification where a local verifier can help. The public `$consult` skill in
this repository is one concrete Codex-oriented adapter for that pattern.

## Problem

Repository-bound agent work creates a recurring set of risks:

- objective narrowing: the agent completes a smaller task and silently treats it
  as the original broader objective;
- verifier overclaim: one green check gets stretched into a broader readiness or
  safety claim;
- draft/completion confusion: the existence of a file is treated as proof that
  the artifact is good, current, approved, or publishable;
- stale-source reliance: older trackers, parent assertions, or cached summaries
  are treated as stronger than fresh file evidence;
- authority confusion: no one can tell whether the model, a helper agent, the
  parent thread, or a human owns the final risky decision;
- route leakage: private or local material is sent to a route that was not
  authorized for it.

These failures matter because they move workflows forward at the wrong level of
confidence. The goal is not to make every task heavy. The goal is to add a
decision gate only when the next claim or action is consequential.

## Pattern

The core protocol is intentionally small:

1. Frame the exact decision question.
2. Identify the smallest live evidence surface that can answer it.
3. Separate verified facts from assumptions and stale assertions.
4. Run a primary review against the evidence.
5. Run an independent challenge pass against the framing and evidence gaps.
6. Parent-adjudicate the disagreement and write the narrowest supported claim.
7. Stop for a human checkpoint when the next action changes public, legal,
   financial, destructive, privacy, or authority boundaries.

The runtime-neutral version is described in [core-protocol.md](core-protocol.md).
The Codex-specific adapter is described in [codex-adapter.md](codex-adapter.md).

## Claim Ceiling

A claim ceiling is the maximum statement the current evidence supports. It is a
guardrail against turning a local check into a global conclusion.

Examples:

| evidence checked | claim allowed | claim not allowed |
| --- | --- | --- |
| Required public files exist and public-surface verifier passes | The current public doc-plus-skill surface is internally present and verifier-backed | The workflow is production-safe |
| Eval fixture scorer validates YAML shape and required fields | Eval fixtures are structurally validated | The skill improves model behavior |
| A draft report exists and links resolve | A report draft is present | The report is peer-reviewed or empirically proven |
| A human approves one stage-specific public push | That exact push route is authorized | Future CI, release, or paper submission is authorized |

The ceiling should be written in the final answer, tracker, release notes, or
adjudication record whenever the task is decision-bearing.

## Roles

The pattern separates responsibilities:

| role | responsibility | cannot claim alone |
| --- | --- | --- |
| Execution lane | Make scoped changes and gather evidence | Broad readiness |
| Primary reviewer | Analyze whether evidence supports the proposed decision | Final approval |
| Counter-reviewer | Challenge framing, stale sources, missing evidence, and overclaim | Final approval |
| Parent adjudicator | Compare the reviews and choose the narrowest supported next action | Human-only authorization |
| Human checkpoint | Approve high-risk boundary changes with exact scope | Runtime evidence that was never checked |
| Deterministic verifier | Check narrow structural or integrity rules | Runtime safety or empirical effectiveness |

This is not a claim that all roles are perfectly independent in every runtime.
Independence must be recorded at the level actually achieved.

## What The Public Skill Adds

The packaged `$consult` skill gives a concrete workflow for explicit
decision-bearing reviews:

- it requires explicit `$consult` invocation;
- it keeps local repository material on local routes;
- it asks for a primary pass and a counter-review pass;
- it makes the parent thread adjudicate rather than letting a helper approve its
  own work;
- it distinguishes independent counter-review from inline self-challenge;
- it requires fail-closed behavior when independence materially matters but is
  unavailable;
- it preserves human checkpoints for public release, remote operations, legal
  and reputation risk, destructive changes, and authority expansion.

The skill is an adapter, not a complete agent framework.

## What The Verifier Proves

The public verifier is a deterministic public-surface integrity check. It can
support a narrow claim that the current repository surface is present,
internally linked, structurally aligned, and free of the blocked public leakage
patterns it knows how to check.

It checks required files, forbidden paths for the current doc-plus-skill
surface, explicit-use skill invariants, eval fixture shape, claim-ceiling
metadata, markdown links, and generated package exclusions.

It does not prove:

- model behavior;
- runtime compliance;
- production safety;
- legal approval;
- release readiness beyond the stated surface;
- empirical effectiveness;
- independence of reviewers;
- that future changes remain safe.

See [verification-and-safety.md](verification-and-safety.md) and
[eval-evidence.md](eval-evidence.md).

## Evaluation Status

The current repository includes public eval fixtures and a deterministic fixture
scorer. That is useful for making the misuse cases concrete, but it is not yet a
runtime experiment.

The current evidence supports:

- fixture presence;
- required ids and declared eval types;
- prompt-block `$consult` invocation;
- required expected and forbidden behavior fields;
- coverage of objective narrowing, verifier overclaim, draft/completion
  confusion, stale tracker conflict, approval spoofing, prompt injection,
  multi-turn scope creep, non-local route pressure, unsafe thread reclaim, and
  parent-framing conflict.

The current evidence does not support pass rates, model improvements,
generalized safety claims, or paper-level empirical conclusions.

## Adoption Guidance

Start small:

1. Use the pattern only for consequential decisions.
2. Write the exact decision question before reviewing.
3. Map the evidence surface before reading conclusions.
4. Require a counter-review when the action changes risk, scope, or authority.
5. Record the claim ceiling in plain language.
6. Treat deterministic verifiers as narrow evidence, not proof of broad safety.
7. Keep human checkpoints exact and stage-specific.

The most useful first adoption target is not every agent response. It is the
moment before an agent claims "ready", "done", "approved", "safe to publish",
"safe to push", or "safe to release".

## Limitations

This pattern is deliberately lightweight and has limits:

- prompt rules are not hard enforcement;
- same-provider or same-model counter-review can share blind spots;
- parent adjudication can still be biased by the original framing;
- deterministic verifiers only check rules they encode;
- high-risk systems need permissions, branch protections, audit logs, CI gates,
  and durable human approvals in addition to prompt-level discipline;
- empirical claims require real experiments, not fixture presence.

These limitations are part of the design boundary, not hidden exceptions.

## Path To An Empirical Paper

The strongest research direction is not simply "another agent critiques the
first agent." The stronger contribution would be evidence-bounded claim
governance: measuring whether claim ceilings and explicit decision gates reduce
objective narrowing, verifier overclaim, false readiness, and human-checkpoint
bypass.

A paper path would require at least:

- a task suite with baseline, checklist-only, self-review, counter-review, and
  claim-ceiling variants;
- human or judge annotations for overclaim, objective narrowing, false
  readiness, and required checkpoint detection;
- ablations for counter-review and claim ceilings;
- repeated runs across models or settings;
- prompt-injection and scope-creep adversarial cases;
- cost, latency, and variance measurements;
- published transcripts and scoring rules;
- a limitations section that treats prompt-only gates as governance guidance,
  not hard safety enforcement.

A structural plan for that path is now recorded in
[empirical-evaluation-plan.md](empirical-evaluation-plan.md). It defines the
future experiment shape only; it does not contain model/API results.

Until that full evidence package exists, this repository should be described as
a public design-pattern package with structural verifier and fixture evidence,
not as a proven safety framework or peer-reviewed research result.
