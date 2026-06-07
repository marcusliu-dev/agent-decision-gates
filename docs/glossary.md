# Glossary

This glossary defines the terms used by Agent Decision Gates and the public
`$consult` skill.

## Core Terms

- **Adjudication:** The parent decision step that accepts, rejects, or narrows
  primary and counter-review findings.
- **Claim ceiling:** The strongest claim current evidence can support. A file
  may make a narrower claim than the tracker, but not a broader one.
- **Counter-review:** A separate challenge pass that looks for stale evidence,
  parent framing bias, missing sources, overclaim, and unsafe next actions.
- **Decision-bearing consult:** A consult whose result decides whether work may
  advance. It needs independent review when the decision is consequential.
- **Evidence scope:** The files, commands, readbacks, or public current facts
  that actually support a claim.
- **Execution lane:** The actor that edits, runs commands, or prepares
  artifacts. It should not silently become the decision authority.
- **Human checkpoint:** An explicit human decision for high-risk actions such as
  public release, legal/reputation acceptance, destructive operations, or scope
  expansion.
- **Independent challenge:** A review path that is separate enough to challenge
  parent assumptions. If independence is unavailable and material, fail closed.
- **Parent framing:** The assumptions introduced by the active thread or
  task owner. Counter-review must challenge it instead of inheriting it.
- **Readiness claim:** Any statement that something is ready, complete,
  approved, safe, releaseable, or fit for a broader route.
- **Source map:** The smallest set of sources that must be read to answer the
  decision question.
- **Stop gate:** A condition that requires `not_ready`,
  `needs_human_checkpoint`, or a narrower next action.
