# Human Checkpoints

## Principle

Some decisions should remain human-only even when the workflow uses consult.
Consult can improve the quality of a decision. It should not erase ownership of
high-risk decisions.

## Typical Human-Only Decisions

- publication or release;
- legal, confidentiality, or reputation-risk acceptance;
- remote creation or push;
- final license choice;
- disclosure of private or sensitive material;
- destructive overwrite, merge, or deletion decisions;
- any request that expands a previously granted surface.

## Stage-Specific Grants

Good checkpoint practice uses exact, stage-specific grants rather than vague
approval. A narrow grant should say:

- which path or repository surface is in scope;
- which exact files may be written;
- which actions remain forbidden;
- which verification route matches the current stage;
- which new condition should force the workflow to stop and re-checkpoint.

## Why Checkpoints Matter

Human checkpoints prevent a document or tool workflow from silently expanding
into a release, disclosure, or infrastructure workflow. They also keep a
useful distinction between:

- local route/quality decisions that consult can challenge; and
- ownership/risk decisions that a human still has to accept explicitly.

## Good Checkpoint Practice

- ask for exact fields, not vague approval;
- keep the grant narrow and stage-specific;
- record the grant in a durable location;
- stop when a required field is missing;
- reopen a checkpoint if a new decision or extra surface appears;
- refuse to treat a prior grant as permission for a broader stage.
