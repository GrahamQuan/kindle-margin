# Warp spec patterns

Use these observations as design guidance, not as a fixed template. The source reviewed on 2026-07-14 was
[Warp's public `specs/` directory](https://github.com/warpdotdev/warp/tree/master/specs).

## Representative features

| Feature                                                                   | Documents                | Useful pattern                                                                                                                                                                                                              |
| ------------------------------------------------------------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [APP-4365](https://github.com/warpdotdev/warp/tree/master/specs/APP-4365) | `PRODUCT.md` + `TECH.md` | A behavior-rich UI change uses explicit goals, non-goals, numbered observable behaviors, code-grounded design, end-to-end flow, targeted tests, risks, and a parallelization decision.                                      |
| [APP-3076](https://github.com/warpdotdev/warp/tree/master/specs/APP-3076) | `PRODUCT.md` + `TECH.md` | A detailed interaction feature expands product coverage around rendering, scrolling, selection, links, streaming, and fallback behavior; its tech spec reuses parser and UI primitives and separates implementation phases. |
| [APP-4319](https://github.com/warpdotdev/warp/tree/master/specs/APP-4319) | `TECH.md`                | A behavior-preserving foundation uses problem, current state, goals, non-goals, proposed changes, tests, rollout and compatibility, risks, and definition of done without needing a separate product contract.              |
| [APP-4351](https://github.com/warpdotdev/warp/tree/master/specs/APP-4351) | `TECH.md`                | A deep internal architecture and protocol change records concrete types, messages, ownership, lifecycle, and migration details directly in the technical design.                                                            |
| [APP-4283](https://github.com/warpdotdev/warp/tree/master/specs/APP-4283) | `TECH.md`                | A simple product outcome with a substantial implementation uses a state-machine diagram, concrete integration changes, manual validation, and follow-ups without a separate product document.                               |

## Durable lessons

1. `TECH.md` is the constant; `PRODUCT.md` is conditional.
2. Product visibility alone does not determine the document set. Add `PRODUCT.md` when an independent behavioral
   contract improves clarity or agreement.
3. Headings vary. Consistent substance matters more than a universal template.
4. Product specs focus on the problem, scope, observable behavior, edge cases, and acceptance.
5. Technical specs begin with the actual codebase, name concrete integration points, and make the implementation path
   reviewable.
6. Strong specs explicitly constrain scope with non-goals and identify what remains unchanged.
7. End-to-end flows, diagrams, rollout plans, implementation phases, compatibility notes, follow-ups, definitions of
   done, and parallelization sections appear when they clarify the feature, not as empty ceremony.
8. Validation is specific: tests cover invariants and repository commands are named when known.
9. Reuse is visible in the design. Existing parsers, UI primitives, models, event paths, and tests are preferred when
   they already express the needed behavior.
10. A spec must distinguish current facts from proposed changes.

## Do not copy blindly

Do not copy Warp ticket identifiers, Rust-specific conventions, section order, file paths, feature-flag practices, or
terminology into another repository. Derive the spec from the target repository's own instructions, code, architecture,
and delivery process.
