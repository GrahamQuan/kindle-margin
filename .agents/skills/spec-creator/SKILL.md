---
name: spec-creator
description: >-
  Create or refine a feature spec under specs/ when requested. Produces TECH.md and optional PRODUCT.md; excludes
  implementation and ordinary analysis.
---

# Spec Creator

Create evidence-based product and technical specifications inspired by Warp's public spec practice. Design for the
repository in front of you; do not impose Warp's implementation or a rigid document template.

Read [references/warp-spec-patterns.md](references/warp-spec-patterns.md) before drafting.

## Start with shared understanding

Use the current request, confirmed decisions, and repository evidence to establish the contract. When those inputs are
sufficient, draft directly. When the user asks for an interview or unresolved product/design choices need one, use
`grill-with-docs`; ask one material question at a time and recommend an answer.

Do not ask the user for discoverable facts or repeat decisions already settled in the session. Routine implementation
choices can remain design assumptions. Ask before choosing an unresolved change to scope, architecture, compatibility,
security, or rollout. If the user opts out of grilling, continue drafting with assumptions clearly labeled.

The existing combined baseline is `sepcs/kindle-margin-design.md`. Preserve its path and requirements; do not create a
competing copy under `specs/`. New standalone features use the layout below.

Create glossary entries or ADRs only when requested or authorized by the documentation workflow; do not use them as
feature-spec scratch space. A request to create or refine a spec authorizes drafting that spec, not its implementation.

Use a **proposed** pre-implementation spec by default. Support an in-progress or as-built spec only when the user
explicitly requests it. In those modes, distinguish verified implemented behavior from remaining proposals; never
describe proposed code as already present.

## Establish repository truth

Locate the repository root, then gather evidence in this order:

1. The current user goal and confirmed decisions define the intended outcome.
2. Read every applicable `AGENTS.md` from the repository root to the files likely to change; treat those instructions as
   constraints.
3. Inspect relevant code, tests, manifests, configuration, history when useful, and existing specs. Treat executable
   files as the source of truth for current behavior and versions.
4. If `docs/system-design/index.md` exists, read it and only the design documents relevant to the feature. Use them to
   understand intended boundaries, security, delivery, migration, and release behavior.
5. Use external examples, including Warp, as inspiration rather than repository truth.

Surface contradictions between sources instead of silently choosing. Reference concrete files, modules, symbols, tests,
and configuration for significant technical claims. Use line numbers only when they materially help. Label assumptions
and do not invent APIs, files, commands, dependencies, or architecture.

Prefer the smallest design that fits existing structures. Reuse proven code, components, types, utilities, tests, and
extension points when appropriate. Let the model decide routine implementation details. Return to the user when a choice
materially changes product scope, crosses an architectural boundary, is expensive to reverse, or introduces meaningful
security, compatibility, dependency, operational, or rollout risk.

## Choose the document set

For a new standalone feature spec, create `TECH.md`. Preserve an existing combined design document when refining it;
do not split or migrate it unless requested.

Also create `PRODUCT.md` when an independent product contract adds value, such as when behavior is substantial,
ambiguous, design-sensitive, rich in edge cases, or needs separate acceptance criteria. A user-visible result does not
automatically require `PRODUCT.md`; use tech-only when product intent is simple and already settled. Respect an explicit
user override.

When both files exist:

- Write `PRODUCT.md` first and treat it as the authoritative behavioral contract.
- Keep implementation details out of `PRODUCT.md`.
- Make `TECH.md` implement and validate the product contract without redefining it.
- Number product behaviors when traceability would help, and connect technical design and tests to those behaviors.

## Create the spec directory

Write specs under:

```text
<repository-root>/specs/YYYYMMDD-<kebab-case-feature>/
```

Use the creation date in the user's timezone in `YYYYMMDD` form and a short descriptive feature phrase. Keep the directory name stable
during later edits. Search existing specs first and update the established spec instead of creating a duplicate.

For new standalone feature specs, create only:

```text
TECH.md
PRODUCT.md  # only when warranted
```

unless applicable repository instructions require additional documentation files.

## Write the product contract

Write `PRODUCT.md` and `TECH.md` in English, including headings, requirements, scenarios, and acceptance criteria.
Preserve canonical identifiers, commands, paths, and product names. Use other languages only for necessary localized
resources, language-specific examples, or original user content, as permitted by the root `AGENTS.md`.
Conversation and interview replies may follow the user's language without changing the repository document language.

Adapt headings to the feature while covering the substance that matters:

- concise summary and the user or business problem;
- goals and explicit non-goals;
- observable behavior, user experience, and acceptance criteria;
- loading, empty, failure, retry, cancellation, permission, and lifecycle states when relevant;
- interactions with existing behavior and backward compatibility;
- designs, links, terminology, rollout constraints, and open assumptions when relevant.

Describe outcomes, not code. Prefer concrete scenarios and testable language over aspirations. Omit irrelevant sections
rather than producing empty boilerplate.

## Write the technical design

Adapt headings to the feature while covering the substance that matters:

- current state and repository evidence;
- proposed design and why it fits existing boundaries;
- affected files, modules, symbols, APIs, data models, and integration points;
- end-to-end data, event, or control flow when useful;
- reuse of existing structures and the minimum necessary new surface;
- focused automated tests, repository validation commands, and manual validation where it adds value;
- risks and mitigations;
- compatibility, migration, rollout, rollback, security, documentation updates, release metadata, phases, follow-ups,
  definition of done, and parallelization only when relevant.

Use proposal tense in the default mode. Make test coverage trace observable requirements rather than merely listing
files. Follow applicable `AGENTS.md` checks and documentation rules. If the design changes architecture, migration,
release, or security behavior, include the corresponding system-design document update in the implementation work.

Do not implement the feature while creating its spec unless the user separately asks for implementation.

## Validate and hand off

Before finishing:

1. Recheck every repository reference and validation command.
2. Confirm `TECH.md` matches `PRODUCT.md` when both exist.
3. Confirm goals, non-goals, edge cases, failure behavior, and tests agree.
4. Remove empty sections, duplicated prose, speculative abstractions, and claims unsupported by evidence.
5. Review the diff and preserve unrelated work.

Report the created or updated spec directory, whether the result is tech-only or product-plus-tech, and any remaining
assumptions or decisions. Do not begin implementation automatically.
