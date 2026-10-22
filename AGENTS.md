# Repository instructions

## Repository language

- Use English for repository-authored content: documentation, specifications, agent instructions, code identifiers,
  comments, logs, error messages, and default user-facing copy.
- Use other languages only where multilingual behavior requires them, such as localized resources, dictionary entries,
  language-specific parsing fixtures, and original book or annotation content. Preserve user data verbatim.
- Write both product and technical specifications in English. Imported skill conventions must not override this rule.
- Conversation replies may follow the user's language; this does not change the repository language.
- Keep the existing design baseline in English. Preserve its requirements when editing or translating examples; do not
  silently change product decisions.

## Project evidence and contracts

- Kindle Margin is currently a design-stage project for a native macOS Kindle companion. The existing baseline is
  [kindle-margin-design.md](sepcs/kindle-margin-design.md). Read relevant sections before designing or implementing
  affected behavior; do not confuse proposed capabilities with verified implementation.
- Preserve the existing `sepcs/` path until an explicit migration is part of the task. Do not create a competing copy
  of the same design under `specs/`.
- Inspect actual source files, manifests, configuration, and available checks before choosing implementation commands.
  Do not invent a build system, dependency version, test command, or successful device validation.
- Preserve unrelated user work. Inspect Git status and diffs when Git is available; do not assume this directory has
  been initialized as a Git repository.

## Specification workflow

Repository-local workflows are available under `.agents/skills/`. Read the relevant skill when it matches the task:

- [spec-creator](.agents/skills/spec-creator/SKILL.md): create or refine a specification.
- [run-spec](.agents/skills/run-spec/SKILL.md): implement or comprehensively validate an existing specification.
- [patch-spec](.agents/skills/patch-spec/SKILL.md): apply bounded follow-up corrections.
- [question](.agents/skills/question/SKILL.md): explicitly requested read-only discussion.
- [grill-me](.agents/skills/grill-me/SKILL.md) and [grilling](.agents/skills/grilling/SKILL.md): requested design interviews.
- [grill-with-docs](.agents/skills/grill-with-docs/SKILL.md): interviews with authorized documentation, using
  [domain-modeling](.agents/skills/domain-modeling/SKILL.md) for glossary terms and architectural decisions.

- Spec authoring, initial implementation, and bounded follow-up corrections are distinct tasks. A request to write a
  spec does not authorize implementing it.
- Search for an existing contract before creating another. For a new standalone feature spec, use
  `specs/YYYYMMDD-<feature>/TECH.md`, dated in the user's timezone. Add `PRODUCT.md` only when a separate behavioral
  contract adds value. Keep existing spec paths stable unless migration is requested.
- Base specs on confirmed user decisions and repository evidence. Separate current behavior, proposed behavior,
  assumptions, and unresolved decisions. Include observable acceptance criteria and proportionate validation.
- When both documents exist, `PRODUCT.md` defines behavior and `TECH.md` explains implementation and validation.
  Keep them consistent and avoid empty template sections or invented APIs.
- Before initial implementation, read the full selected contract and derive an acceptance checklist. Resolve material
  contradictions before affected work while continuing independent authorized work.
- For bounded follow-up feedback, inspect the current implementation and relevant contract sections, apply the
  correction, and run focused checks. Broaden validation when requested or justified by concrete regression risk.
- Do not rewrite a contract merely to make incomplete code appear compliant. Changes to the contract require user
  intent to refine that contract; existing authorization remains valid without repeated confirmation.

## Questions and design interviews

- Inspect discoverable facts before asking the user. Do not repeat settled decisions or block routine implementation
  choices behind unnecessary questions.
- Ask when an unresolved decision materially affects scope, architecture, security, compatibility, or an expensive
  reversal. State the concrete decision, recommend an option, and explain the relevant tradeoff.
- When the user requests a design interview, ask one material question at a time and wait for its answer. Resolve
  dependencies between decisions in order; confirm shared understanding before implementing the interviewed design.
- An explicitly requested read-only discussion must not modify files, Git state, dependencies, project records, or
  external systems. Do not turn discussion into a persisted spec or task without authorization.
- Record glossary terms or architectural decisions only when documentation is requested or included in the authorized
  workflow. Do not create documentation scaffolding for ordinary questions.

## Validation and delivery

- Use checks that actually exist and match the affected behavior. Documentation-only edits need content, link, and
  formatting checks rather than application builds.
- Distinguish local checks from physical-device verification and release readiness. Report unavailable checks and
  remaining acceptance gaps accurately.
- Creating or editing local files does not authorize pushing, publishing, deploying, or releasing.

## Temporary services and browser automation

- Record each task-created service's owning task, working directory, process ID, port, and terminal session.
- Unless the user asks to retain it, stop each task-created temporary service and its children after validation and
  before the final response. Attempt graceful termination first with a bounded wait; recheck identity and ownership
  before forced termination.
- Verify that processes exited and ports were released. Preserve pre-existing, shared, and other-task services,
  including Codex and MCP infrastructure. Never use broad process-kill commands.
- Track task-created browser tabs, windows, sessions, and automation workers separately from pre-existing resources.
  Close them through supported cleanup APIs unless the user requests retention or they are the intended deliverable.
- Stop task-owned recording, tracing, and automation workers. Preserve user browser state and shared infrastructure;
  when ownership is uncertain, leave the resource intact and report the uncertainty.
- Verify browser cleanup with available listings or process checks. A tool reset is not proof of cleanup. Report
  unsupported or failed cleanup accurately.
- State cleanup status in the final response. For retained resources, explain why they remain and how to stop them.
