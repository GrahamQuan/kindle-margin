---
name: run-spec
description: >-
  Implement, continue, or comprehensively validate an existing repository spec contract. Excludes spec authoring and bounded
  follow-up patches handled by patch-spec.
---

# Run Spec

Implement an existing repository spec as a focused, verifiable change. Treat Goal mode as the execution mode and this
skill as the implementation workflow; do not create or activate a goal unless the user explicitly asks for one.

## Establish the contract

1. Resolve the requested spec file or directory from the request or repository instructions. New feature specs live
   under `specs/`; the existing combined baseline is `sepcs/kindle-margin-design.md`. Preserve its path. If multiple specs are
   plausible and choosing one would materially change the work, ask the user to identify the target.
2. Read every applicable `AGENTS.md` from the repository root to the files likely to change.
3. Read the target `PRODUCT.md` first when present, then read `TECH.md` completely. For the existing combined baseline,
   read the full document as both the product and technical contract. If the required design is missing, route creation
   or refinement to `spec-creator` instead of inventing it.
4. Treat `PRODUCT.md` as the behavioral contract and `TECH.md` as its technical implementation and validation design.
   Treat the repository as the source of truth for current state and the spec as the source of truth for the intended
   outcome.
5. Inspect the relevant code, tests, manifests, configuration, documentation, and current diff before editing. Preserve
   unrelated user changes.

## Check readiness

- Implement a proposed, ready, or in-progress spec when the user explicitly requests implementation and no material
  decision remains unresolved.
- For a spec marked implemented or implemented locally, verify it and fix in-scope gaps instead of recreating it.
- For a superseded spec, stop unless the user explicitly overrides that status.
- Surface contradictions between the spec, current code, applicable instructions, and product behavior. Stop for a user
  decision when resolving a contradiction would materially change product scope, architecture, compatibility, security,
  dependencies, rollout, or release behavior.
- Do not modify the spec merely to make an incomplete implementation appear compliant.

Invoking this skill authorizes normal in-workspace implementation described by the selected spec. It does not authorize
publishing, releasing, versioning, tagging, pushing, deploying, modifying external repositories, or completing external
approval and rollout steps.

## Implement the spec

1. Build an acceptance checklist from the spec's goals, non-goals, observable behaviors, acceptance criteria, and
   definition of done.
2. Make the smallest coherent change that satisfies the checklist and existing repository boundaries. Follow current
   structures and public APIs before introducing new ones.
3. Add or update focused tests that trace the observable requirements. Use any additional skills explicitly required by
   applicable repository instructions.
4. Keep external gates separate from local implementation. Add local release metadata such as a Changeset only when the
   spec or repository instructions require it, but do not perform a release.
5. Re-read the relevant spec sections after implementation and compare them with the actual diff.

## Verify completion

1. Run focused checks while iterating, then run every applicable validation command required by the spec and
   `AGENTS.md`.
2. Review the final diff for regressions, unsupported claims, unrelated cleanup, missing documentation, and violations
   of non-goals.
3. Mark the work complete only when every in-scope acceptance criterion is implemented and verified. Treat failed or
   unavailable required checks, unresolved decisions, and required external actions as explicit blockers or remaining
   gates rather than silently lowering the completion standard.
4. Report the implemented outcome, acceptance evidence, validation commands and results, remaining unverified items, and
   external approval or rollout gates.

## Hand off subsequent feedback

After this workflow has produced a concrete local implementation and completed its initial required checks for the
active spec, route subsequent bounded implementation feedback in the same task to `patch-spec` by default. Do not
rebuild the complete acceptance checklist or rerun the full validation matrix for every small-to-medium correction.

Re-enter `run-spec` when the user explicitly invokes it or clearly requests final comprehensive validation. If
`patch-spec` determines that an automatic return to `run-spec` is necessary, it must first explain the escalation,
identify the target spec and expanded scope, and ask the user for permission. Existing explicit authorization in the
session is sufficient; ask only for a scope expansion not already authorized. Silence or an ambiguous reply is not
approval.

This handoff does not mark unresolved blockers complete or reduce the final spec validation standard.

## Use with Goal mode

Prefer an explicit invocation such as:

```text
/goal Use $run-spec to implement and verify specs/YYYYMMDD-feature-name/TECH.md.
```

When already running under Goal mode, use the selected spec's in-scope acceptance criteria and required checks as the
completion criteria. When invoked outside Goal mode, execute the same workflow in the current task without silently
starting a separate goal.
