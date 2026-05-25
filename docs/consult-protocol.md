# Consult Protocol

## When To Use Consult

Use a consult pattern when a task has material ambiguity, meaningful downside,
or a high cost of acting on a bad assumption. Typical triggers include:

- broad goals that could be narrowed by mistake;
- readiness or completion claims;
- scope changes that might expand a prior grant;
- risky judgment calls that need an explicit challenge pass;
- stage-boundary decisions in a larger workflow.

This repository also ships an installable `$consult` skill package at
[`skills/consult/`](../skills/consult/) for runtimes that support local skills.

## Core Flow

The base flow is:

1. Frame the actual decision question.
2. Separate verified facts from assumptions.
3. Gather the smallest sufficient evidence.
4. Run a primary analysis.
5. Run an independent challenge pass.
6. Make a bounded final adjudication.
7. Record the result, the remaining stop gates, and the current claim ceiling.

## Decision-Bearing Consults

Some consults are informational. Others decide whether work may continue.
For decision-bearing consults:

- use independent primary and challenge passes;
- prefer the strongest available model and highest reasoning effort;
- if your runtime exposes explicit overrides, use them and record the actual
  runtime values;
- if independence or the intended runtime route is unavailable, fail closed and
  do not use the consult as authorization to advance.

In the reference workflow here, the preferred route is independent spawned
agents on `gpt-5.5` with `xhigh` reasoning when that combination is available.
If it is unavailable, record what actually ran and treat that as a bounded
evidence limitation rather than pretending the stronger route happened.

The installed `$consult` skill in this repository keeps that same preference:
independent Step 1 and Step 2 spawned lanes should use `gpt-5.5` with `xhigh`
reasoning when your runtime supports that route, and should record actual
fallback runtime values when it does not.

## What Good Output Looks Like

A useful consult result should answer:

- What question was being decided?
- What evidence was checked?
- What remains uncertain?
- What action is allowed now?
- What action is still blocked?
- What claim ceiling does the evidence actually support?

## What Consult Is Good For

- checking whether execution is narrowing the real goal;
- challenging weak assumptions and stale state;
- testing whether a next stage is still best practice;
- distinguishing evidence from opinion;
- deciding whether a human checkpoint is required;
- keeping a tracker honest at stage boundaries.

## What Consult Is Not

Consult is not:

- a substitute for human authorization;
- proof by authority;
- a reason to skip verification;
- a workaround for missing grants;
- a way to turn a local draft into a release claim.

Installing the skill is not the same as authorizing publication, legal-risk
acceptance, destructive actions, or other human-only decisions.

## Common Failure Modes

- treating draft artifacts as proof of completion;
- skipping the independent challenge pass;
- relying on stale tracker text;
- broadening scope without explicit approval;
- treating one green verifier as proof of a broader claim;
- hiding uncertainty instead of carrying a narrower claim ceiling.
