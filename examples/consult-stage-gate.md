# Fictional Example: Stage Gate Consult

## Scenario

A team is building a public operations-review playbook. After finishing a local
doc skeleton, the team wants to know whether it may start drafting public-facing
guidance.

The real decision question is not "did files get created?" It is:

> Is the current authorization sufficient to allow bounded public doc drafting,
> and if so, what still remains blocked?

## Evidence Checked

- the current stage tracker;
- the exact human authorization block;
- the requested writable surfaces;
- the current repository tree;
- the current safety verifier output.

## Primary Pass

The primary reviewer checks whether the authorization explicitly covers:

- the path being reused;
- the exact writable files;
- the content boundary;
- the verification boundary;
- the stop rule for any additional surface.

If every required field is answered and all higher-risk actions remain deferred,
the primary pass may recommend moving forward with bounded drafting only.

## Independent Challenge Pass

The independent challenge pass tests whether the same authorization accidentally
permits any of the following:

- release or publication work;
- remote or CI setup;
- final license work;
- executable code or script expansion;
- broadening the granted surface list by implication.

If any of those are still ambiguous, the challenge pass should fail closed and
send the workflow back for a human checkpoint.

## Bounded Adjudication

If both passes agree the grant is sufficient, the final adjudication should say
something like:

> Stage 3 drafting is authorized only for the exact granted doc surfaces. The
> workflow may draft those files now, but may not create new surfaces, edit
> runtime scripts meaningfully, initialize git, configure remotes, choose a
> final license, or publish anything.

## Why This Example Matters

This example shows the main discipline of the pattern:

- a stage artifact is not proof of broader readiness;
- independent challenge improves decision quality;
- a human checkpoint stays human-only;
- the workflow advances only inside the granted envelope;
- the final claim stays narrower than the total ambition.
