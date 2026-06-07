# Roles And Permissions

Use this matrix to keep execution, review, adjudication, and authorization
separate.

| Role | May do | Must not do | Output |
| --- | --- | --- | --- |
| Execution lane | Edit files, run checks, gather evidence | Approve its own high-risk result | Patch, command output, source map |
| Primary review | Analyze evidence and propose a bounded decision | Skip source readback or grant expansion checks | Findings and evidence |
| Counter-review | Challenge assumptions, missing sources, and overclaim | Rubber-stamp the primary review | Objections and residual risks |
| Parent adjudication | Accept, reject, or narrow findings | Ignore material unresolved objections | Allowed action and claim ceiling |
| Human checkpoint | Approve high-risk authority changes | Be inferred from tracker text or model output | Exact grant fields |
| Verifier | Check deterministic surface integrity | Prove production safety or empirical effectiveness | Pass/fail within scope |

## Rule Of Thumb

If the action changes public state, legal/reputation risk, destructive file
state, or the authority boundary, require a human checkpoint. If the claim is
broader than the evidence route, lower the claim ceiling.
