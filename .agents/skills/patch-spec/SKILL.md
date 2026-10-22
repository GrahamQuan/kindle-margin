---
name: patch-spec
description: >-
  Apply bounded follow-up corrections to an implemented spec in the active task. Excludes initial implementation,
  contract changes, release, and final comprehensive validation.
---

# Patch Spec

Patch an implementation that has already completed the repository's `run-spec` workflow without reopening that full
workflow for every feedback cycle.

## Default after initial run-spec

After `run-spec` has produced a concrete local implementation and completed its initial required checks, treat
subsequent bounded implementation feedback in the same task and active spec context as `patch-spec` work by default. The
user does not need to invoke this skill again for each correction.

This is a routing default, not a permanent mode. It ends when the active spec changes, the request is unrelated to that
implementation, or an escalation boundary below applies. An explicit `$run-spec` invocation overrides this default and
does not require a second confirmation.

## Confirm this is a follow-up patch

Proceed only when all of the following are true:

- A concrete implementation of the target spec already exists locally or in the current branch history.
- The user supplied a bounded correction, bug, UI adjustment, or behavior change.
- The change remains inside the existing product and technical contract.
- Focused verification can provide proportionate confidence while iteration continues.

Resolve the target spec from the request or current task context. Ask for the spec only when multiple candidates are
plausible and selecting one would materially change the patch.

Route away from this skill when:

- The spec has not yet been implemented: use `run-spec`.
- The request changes product scope, acceptance criteria, architecture, package ownership, public compatibility,
  security, migration, release, or rollout behavior: use `spec-creator` before further implementation.
- The patch has grown beyond a bounded medium change: prepare to ask permission to use `run-spec` to re-establish and
  verify the complete contract.
- The user requests final comprehensive spec validation: use `run-spec` in validation mode.

## Ask before escalating to run-spec

When this skill determines that an unrequested automatic switch to `run-spec` is necessary, stop before expanding the
workflow. Read any additional spec sections needed to diagnose the boundary and make the proposed expansion concrete. Do
not broaden implementation scope or start the comprehensive validation matrix before that expansion is authorized.

Tell the user:

- the concrete reason `patch-spec` is no longer sufficient;
- the target spec that `run-spec` would use; and
- the additional implementation or validation scope the switch would authorize.

Ask for permission to switch. Start `run-spec` only after an explicit affirmative response such as `yes`, `continue`,
`approved`, or another unambiguous confirmation in the user's language. Do not treat silence, an unrelated reply, or an
ambiguous response as approval.

If the user declines, do not switch and do not continue the out-of-scope portion. The assistant may offer a smaller
option that remains inside `patch-spec`, or report the blocked work. When the user already invoked `$run-spec`,
requested final comprehensive spec validation, or authorized the same expanded scope earlier in the session, do not
request that authorization again.

## Work from the current implementation

1. Read every applicable `AGENTS.md` for the files likely to change.
2. Inspect the branch, working tree, current diff, relevant implementation, and focused tests. Preserve unrelated and
   pre-existing user changes. When the user has already authorized continuing with the same unchanged dirty workspace,
   do not ask again.
3. Treat the user's concrete follow-up request as the patch acceptance criteria. Treat current code as the
   implementation baseline and the existing spec as a guardrail.
4. Read only the spec sections needed to clarify the affected behavior or boundary. Do not restart `run-spec`, rebuild
   its complete acceptance checklist, or reread the complete spec by default.
5. Make the smallest coherent change that resolves the feedback. Avoid unrelated cleanup, restructuring, dependency
   replacement, documentation expansion, or release work.
6. Add or update focused tests that demonstrate the corrected behavior.

Do not modify the target spec. A task-scoped spec remains a historical contract unless the user explicitly asks to
refine that exact spec, in which case route the work to `spec-creator`.

## External actions

Do not publish, version, tag, push, deploy, release, or roll out unless separately and explicitly authorized.

## Verify proportionately

1. Run the narrowest focused tests for the changed behavior while iterating.
2. Run a targeted typecheck, lint, build when the affected surface makes it necessary.
3. Do not automatically run repository-wide checks, the complete end-to-end suite, or the
   original spec's full definition-of-done matrix.
4. Run broader checks when the user explicitly requests them or when the patch creates a concrete cross-package or
   integration regression risk. Explain that reason before broadening verification.

Report the patch outcome, focused checks and results, checks intentionally deferred, and whether a final `run-spec`
validation pass remains recommended.
