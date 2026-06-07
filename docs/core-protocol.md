# Core Protocol

This is the runtime-neutral decision-gate pattern behind the public `$consult`
skill.

## Minimal Flow

1. State the exact decision question.
2. List the evidence needed to answer that question.
3. Read the smallest live source map that can settle the question.
4. Separate verified facts from assumptions.
5. Run a primary analysis.
6. Run a counter-review that challenges the primary analysis and parent
   framing.
7. Adjudicate the disagreement.
8. Record the action allowed now, the action still blocked, and the claim
   ceiling.

## Required Outputs

A useful decision gate should identify:

- the decision question;
- evidence checked;
- evidence not checked;
- primary finding;
- counter-review finding;
- parent adjudication;
- human checkpoints still required;
- current claim ceiling;
- next safe action.

## Fail-Closed Rule

Return `not_ready`, `needs_human_checkpoint`, or a narrower next action when:

- the source map is missing a material source;
- independent review is unavailable and material;
- a human-only decision is being inferred from local evidence;
- a verifier proves only a narrow surface but the proposed claim is broader;
- a draft artifact is being treated as release evidence.

## Portability Rule

The pattern does not require a specific model, provider, or agent runtime. If a
runtime cannot provide independent spawned reviewers, record that limitation
and do not claim independent approval.
