# Kindle Margin UI Redesign

Status: **implementation in progress**, 2026-10-22. The user approved the supplied reference image as the visual
direction and authorized implementation and native UI validation. This specification refines sections 4.1–4.6 of the
[V1 design baseline](kindle-margin-design.md#4-dashboard-ui-and-ux); it does not change the V1 feature scope. The baseline remains authoritative for shared product and architecture requirements; this
document defines the proposed UI refinement.

## Problem and pre-redesign evidence

At the initial review, [`WorkspaceView`](../Features/Workspace.swift) combined a page heading, an in-content toolbar, annotation
list, always-editable selected text, and several equally prominent action buttons. Dictionary import configuration,
lookup, package management, and editing share one page. These are source-code observations, not findings from a
completed visual or usability test. The user reports that the current UI looks old and is not user friendly.

The repository contains a SwiftUI implementation; the observations below describe the pre-redesign source.
This review covers its presentation source and the proposed redesign; it does not establish runtime usability,
visual quality, device readiness, or completion of the baseline.

| Source observation | User impact | Proposed refinement |
| --- | --- | --- |
| `annotations` shows a `TextEditor` immediately and places Save, Hide, Restore, Preview, and Export in one row. | Reading and changing data have similar visual weight. | Explicit reading/editing states and state-specific action hierarchy (RUI-01/02). |
| `showHidden` controls collection filtering, the Settings export toggle, and preview/export inputs. | A browsing choice changes exported content unexpectedly. | Independent browsing and export options, with visible export scope (RUI-02). |
| `annotationToolbar` falls back to horizontal scrolling; dictionary controls and sheets have fixed arrangements or dimensions. | Essential actions can move out of view in small windows or with long text. | Reflow controls, constrain sheet size, and scroll sheet content (RUI-03). |
| One Boolean focus binding targets annotation search; page and tools changes set it regardless of destination. | Focus restoration has no appropriate target on other pages. | Destination-specific focus and command behavior (RUI-06). |
| `message` is presented through a generic alert; device status is hardcoded as Disconnected. | Feedback lacks operation context, and connection status cannot establish capability. | Scoped feedback and truthful availability states (RUI-05). |

Review basis: [AvdLee SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill) guidance on macOS views,
layout, and focus, plus [SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill) guidance on design,
resizability, and accessibility. Apply their platform-relevant principles within the repository's macOS 14 and
Swift tools 5.10 baseline; iOS-only sizing rules and newer SDK assumptions are not requirements for this project.

The redesign should make three things immediately apparent: where the user is, what content they are working with,
and the next useful action. Reading should feel spacious; managing files and dictionaries should feel predictable.
The design should retain native macOS navigation and controls without adding a metrics dashboard or decorative cards
around every field. Existing local workflows must remain available without a connected Kindle.

## Visual direction and proposed measurements

Follow the user-supplied desktop content-manager reference: a soft blue/lilac/blush window background, a low-contrast
sidebar, generous aligned headings and filters, and one opaque rounded main content surface. Use a dark primary
action in light appearance and an accessible light counterpart in dark appearance. The reference establishes visual
hierarchy, not its blog-specific content or duplicate New Post actions. Preserve reading/editing separation and all
draft safeguards. Measurements remain adjustable during native visual review.

| Element | Proposed treatment |
| --- | --- |
| Navigation | Native sidebar selection, SF Symbols with text labels, comfortable row padding; Settings anchored at the bottom |
| Surfaces | White main surface over a pale blue/lilac/blush shell in light appearance; neutral dark surface over a muted tinted shell in dark appearance; subtle row separators |
| Accent | High-contrast neutral primary buttons, restrained system selection, and semantic warning/error colors with text or icons |
| Typography | Semantic system text styles for headings, controls, and metadata; initial visual targets of 24–28 pt for page headings, 13–15 pt for interface text, and 17–20 pt for excerpts are review references, not fixed font requirements; optional system serif treatment for excerpts only |
| Spacing | A 4 pt spacing scale; typically 8 pt within control groups, 16 pt between related groups, and 24–32 pt content margins |
| Reading measure | Target roughly 60–80 characters per line where space permits; long passages wrap and remain selectable |
| Corners and depth | Native control shapes; restrained 8–12 pt corners only on surfaces that need grouping; avoid stacked floating panels |
| Motion | Short, nonessential transitions for disclosure and selection; honor Reduce Motion and never delay actions for animation |
| Materials | Subtle native sidebar/toolbar materials where supported; keep reading and editing surfaces opaque enough for reliable contrast |

Support light/dark appearance, Increase Contrast, and Reduce Transparency. Normal text should achieve at least 4.5:1
contrast and essential control boundaries/focus indicators 3:1 against adjacent surfaces. Do not rely on color alone
for selection, hidden content, edited content, errors, or device status. Keep macOS 14 compatibility; newer visual
effects are optional enhancements, never prerequisites for the redesign.

Centralize semantic roles for surfaces, primary/secondary text, selection, focus, spacing, and reading typography.
Use system selection and focus styling where possible; do not force decorative background colors onto controls or reduce metadata
contrast through arbitrary opacity. Keep the same hierarchy in dark appearance instead of merely inverting colors.
Do not add Liquid Glass as part of this proposal. Keep text selectable, allow source-language scripts to use suitable
font fallbacks, and treat reading measure as an approximate comfort target rather than a character-count constraint
for CJK or mixed-script text. Validate enlarged text on macOS without assuming iOS Dynamic Type behavior.

## RUI-01: Window, navigation, and action hierarchy

- Retain the five navigation destinations and the conditional right tools panel defined in the V1 design baseline. Use one adaptive content header for the page title, search, and primary action as in the reference, with native
  window controls for navigation and contextual tools.
  Do not duplicate the same action in multiple permanent toolbar rows.
- Keep device status in a stable shell location, available even when navigation is collapsed. Show a short status
  label and expose its explanation without making a warning dominate local reading workflows.
- Give each page one visually emphasized primary action appropriate to its current state. Use ordinary toolbar
  buttons for supporting actions and labeled menus for infrequent actions. Icon-only controls need accessible names
  and help text; primary import, edit, and save actions must not require discovering a context menu.
- Preserve page-local search, filters, selection, scroll position, and unsaved drafts during navigation. Returning
  from a detail view restores the previous collection position rather than jumping to the beginning.

Action emphasis follows the task state; do not invent a prominent action on pages that only need navigation.

| State | Emphasized action | Supporting actions |
| --- | --- | --- |
| Empty annotation archive | Import My Clippings… | Explanation of the local-file workflow |
| Annotation collection | Import My Clippings… | Search, type/visibility filters, import diagnostics |
| Annotation reading | Edit | Back, Preview Markdown, Export book…, secondary menu |
| Annotation editing | Save correction | Cancel; keep conflicting restore/hide actions out of the active editor |
| Dictionary lookup with installed packages | Look up | Import dictionary…, Installed dictionaries |
| Dictionary entry editing | Save definition | Cancel |
| Tasks and Settings | No forced primary action | Contextual actions beside their affected job or setting |

Show brief guidance when it explains a decision or next step; avoid permanent introductory paragraphs on every
populated page. Keep filters beside the collection they affect, separate from the single page action header.

## RUI-02: Annotations, reading, and editing

1. On first use, show “Your reading, collected” with a short explanation of My Clippings and a prominent
   “Import My Clippings…” action. Explain that a local file works without connecting a Kindle. Do not show an empty
   editor, empty inspector, or fabricated sample library as real user content.
2. After import, show a book-grouped annotation collection. Group by stable book identity, never by title alone.
   Preserve full source descriptions; show no invented author, cover art, or reading progress. Search book descriptions
   and annotation text from a clearly labeled field. Provide type filters and a discoverable “Show hidden” option.
3. Collection rows prioritize the excerpt, then annotation type and location. Show book identity at the group header,
   plus textual “Edited locally” or “Hidden” indicators where applicable. Avoid repeating a large book title in every
   row. A bookmark with no text has an explicit bookmark label and any available location.
4. Opening an annotation (pointer activation or Return on the keyboard-selected row) shows its reading surface within the center workspace, replacing the collection rather
   than adding a permanent fourth column. Show “Back to annotations,” book context, the complete selectable excerpt,
   and an explicit “Edit” action. Returning to the collection preserves search, filters, selection, and scroll position.
5. Entering Edit reveals the correction editor, “Save correction,” and “Cancel.” Explain once near the editor that
   changes stay local and the original is preserved. Keep the book context visible while editing. Cancel discards only
   the current unsaved correction; confirm if it would discard changed text. Saving does not exit edit mode or clear
   the draft until persistence succeeds; failure retains text and offers another save attempt.
6. Keep unsaved drafts if the user changes pages or selects another annotation. A returning draft must be visible
   with an “Unsaved changes” indicator and an accessible way to resume editing. Closing the window or quitting with
   drafts requires Save, Discard, or Cancel; a failed save must prevent that close/quit from silently discarding text.
7. “Export book…” and “Preview Markdown” are available from the selected book/annotation context without opening the
   inspector. Their scope must name the book and clearly state that export includes the book's eligible annotations,
   not merely the selected excerpt. Retain current export options and conflict protection.
8. Put Hide/Unhide and Restore Original in a labeled secondary menu and, where useful, the inspector. Restoring must
   explain what local changes will be removed before applying it if corrections or a draft exist. Hiding the current
   item returns to the collection when hidden items are filtered out; do not discard an unrelated draft.
9. A zero-result search shows “No matching annotations,” the active filters, and a “Clear filters” action that resets
   search, type, and visibility filters to defaults. Distinguish this state from an empty archive. Import diagnostics
   remain discoverable; after partial import, show the available import counts and a “Review skipped records” action.
10. Keep “Show hidden” (collection visibility) separate from “Include hidden annotations” (export/preview scope).
    Changing either must not change the other. Preview and export must use the same explicitly presented options,
    including local tags. Show the book name and whether hidden annotations are included before export; unsaved
    corrections are not exported. If that book has drafts, explain that saved content will be used and provide a way
    to return to editing. Never silently save drafts as a side effect of export.
11. Compare a draft with its saved value to determine whether it is changed; entering and leaving Edit without
    changes must not produce a discard prompt. After a successful save, return to reading with nonmodal confirmation.
    Prevent duplicate save submissions while preserving the draft on failure. If a save allows further typing, its
    completion must not erase edits made after submission. Apply the same rule to dictionary definitions.

## RUI-03: Contextual tools and resizing

Keep the right panel for original text, provenance, metadata, and secondary actions. Provide a heading and a labeled
close control. An annotation without useful context must not reserve empty panel space. Never make reading, saving,
searching, or exporting depend on the inspector being open.

Use approximately 200–220 pt for navigation and 280–320 pt for the inspector as initial layout targets. Target a
comfortable default window around 1120 × 760 pt while continuing to support a compact 660 × 480 pt window. Collapse
tools before reducing the center below a usable reading width; expose them through a dismissible sheet at compact
sizes. Then collapse navigation if necessary, preserving its accessible toggle. Toolbar actions may move into labeled
overflow menus; search and the primary action remain discoverable. Do not horizontally scroll the application shell.

Remember explicit tools-panel collapse per page during the session. Automatic collapse due to window size must not
overwrite that preference. Close stale sheets on page or selection removal, and restore keyboard focus to a surviving
control. Long book titles, translated source content, and large text must wrap or truncate with full text accessible.

Determine fit from the current window's available content width, including sidebar, inspector, and margins, rather
than the physical display or an iOS size-class assumption. At compact width, reflow filters below search or place
them in a labeled Filters menu showing active state; do not require horizontal scrolling to reach primary controls.
Use native macOS control sizing and keyboard focus rather than applying an iOS 44 pt touch-target rule wholesale.

Sheets for tools, diagnostics, import metadata, and Markdown preview must fit the available window/screen area.
Allow long content to scroll vertically with dismissal and confirmation controls reachable. Resizing must not create
two copies of the same tools view, lose drafts, or repeatedly reopen an inspector the user closed. A lookup result,
annotation excerpt, or editor must not be reduced to a fixed-height sliver merely to keep all secondary controls visible.

## RUI-04: Dictionaries

Make word lookup the primary workspace with a prominent labeled search field and clear source attribution in results.
Separate package management into an “Installed dictionaries” disclosure or sheet, retaining priority ordering, conflict
counts, and merged JSON export. Keep “Import dictionary…” visible; collect CSV name and language metadata in its import
flow before submission rather than permanently placing those fields above lookup results. JSON continues to use its
own metadata.

Show distinct states for no installed dictionaries, no query yet, lookup in progress, no matches, and lookup failure.
Do not present stale results as matches for a newer query. Display complete definitions in the selected-entry reading
surface and enter editing explicitly; apply the same draft, save-failure, cancel, and restore safeguards as annotations.
Keep package/source identity visible when identical headwords come from multiple dictionaries. Downloads and Kindle
dictionary installation remain subject to their existing availability and verification gates.

## RUI-05: Device Library, Tasks, and Settings

| Page | Proposed presentation and interaction |
| --- | --- |
| Device Library | A calm disconnected/unavailable state explains why browsing is unavailable and links to working local annotation import or converter settings. Do not imply that plugging in a device enables an integration that is not implemented. When device orchestration exists, use the file list and conditional details from baseline section 4.2. |
| Tasks | Readable rows show operation, stage, textual state, and an appropriate cancel action. Group active work before completed history. Show measurable progress only when supplied by the job model. Expand failure details with a concrete next step; offer Retry only where a safe retry operation exists. |
| Settings | Group controls by Export, Conversion, Privacy, and About/Compatibility. Explain the selected converter's state beside its controls. Keep technical diagnostics in a disclosure, and surface errors beside the affected setting. |

Loading indicators belong to the affected area, retain useful prior content, and avoid shifting toolbar geometry.
Errors must retain the user's input. Success feedback should be nonmodal where acknowledgment is unnecessary; retain
explicit confirmations for data loss, replacement, and device operations required by the V1 design baseline.

Name the failed operation in feedback, retain its recovery action until resolved or dismissed, and keep technical
details available through disclosure. Reserve alerts for decisions needing immediate acknowledgment. Background
work must not block unrelated reading or dictionary lookup; disable only actions that conflict with actual work.
When a connection capability is unavailable in the build, explain it in the affected page rather than presenting
implementation terminology as the main user instruction. Distinguish this from a supported device simply being unplugged.

## RUI-06: Keyboard, focus, and accessible feedback

- Keep native selection, focus rings, and text editing behavior. Arrow keys move collection selection without
  navigating away; Return opens the selected item. Pointer activation opens the reading surface as in RUI-02.
  Selection and opening a detail must be distinct presentation events so keyboard browsing remains possible.
- Command-F focuses search on the active searchable page. Command-S saves only the active changed editor;
  Command-comma opens the existing Settings destination. Expose commands in the app menu and disable them when
  inapplicable. Do not override ordinary copy, paste, undo, or text-selection commands.
- Entering Edit places focus in the editor. Back restores focus and scroll position to the originating row; if that
  row no longer exists, use the next valid row or the collection's empty-state action. Closing a sheet or inspector
  returns focus to its trigger when it still exists, otherwise to a relevant control on the current page.
- Escape dismisses a nonediting sheet. In an editor or import form with changed input, it follows the same cancel
  and discard rules as the visible Cancel button. Escape never silently discards a draft or starts an operation.
- VoiceOver exposes each row's content summary, type, location, and selected/edited/hidden state without separately
  reading decorative symbols. Controls have meaningful labels; fields remain identifiable after their placeholder
  disappears. Announce meaningful save, failure, and task-completion changes without stealing focus or repeatedly
  announcing progress updates. Help text supplements visible labels rather than replacing them.

## Technical approach for later implementation

- Refactor presentation in [`Features/Workspace.swift`](../Features/Workspace.swift), retaining `WorkspaceModel` as the
  observable entry point. Extract page views and reusable typography, spacing, and surface styles as needed; exact
  filenames are implementation choices. Use native SwiftUI navigation, toolbar, list, sheet, and focus facilities.
- Reuse `LibraryService`, `JobCoordinator`, existing import/export callbacks, and the override persistence model.
  Keep file panels and application termination handling in [`App/KindleMarginApp.swift`](../App/KindleMarginApp.swift).
  Extend close/quit coordination to account for UI drafts as well as running jobs. Do not add file or device I/O to views.
- Add explicit presentation state for collection/detail navigation, edit mode, import configuration, query/result
  identity, and per-page scroll restoration. Key drafts and selection by stable IDs. Restore actions must coordinate
  with drafts; filter changes must not silently delete them. Persisted library schemas need no redesign for this work.
- Use [`Package.swift`](../Package.swift)'s existing macOS 14 baseline. No third-party UI framework, dependency upgrade,
  remote artwork service, telemetry, or backend change is required. Treat capability availability as real application
  state, not something a visually enabled control establishes.
- Keep appearance tokens semantic with separate accessible light/dark values. Evaluate native newer-system styling
  during implementation; do not hardcode a new OS requirement to obtain a visual effect.
- Keep per-window navigation, focus, and presentation ownership explicit: the app currently uses `WindowGroup` with
  a shared model. One window's sheet dismissal or page transition must not redirect another window's focus. Coordinate
  shared drafts and close/quit decisions without silently overwriting edits from another window.
- Use separate presentation values for collection visibility and export inclusion. Replace the single search-focus
  Boolean with appropriate page/editor targets. Prefer semantic `Button`, `Label`, `List`, `Form`, and native toolbar
  controls; do not simulate buttons with tap gestures. Keep one authoritative tools context for panel/sheet forms.
- Preserve stable view identity across resizing; keep drafts and navigation above replaced layout branches. Build
  self-contained previews from synthetic data without live device, network, or persistent user-library dependencies.
  Do not infer a performance regression from file size alone; measure before adding caching or other optimizations.

## Redesign acceptance and validation

These checks supplement baseline criteria UI-01 through UI-06, not replace them. They are proposed acceptance gates, not completed tests.

| ID | Scenario and passing condition |
| --- | --- |
| RUI-A01 | With an empty local library and no device, a user can find and start My Clippings import from the initial screen without visiting Settings. |
| RUI-A02 | With multiple books including identical titles, groups remain distinct by identity; search and type filters find the expected records; zero results offer a working reset. |
| RUI-A03 | Select, read, edit, save, cancel, hide, restore, preview, and export are reachable without the inspector. Save failure retains the draft; export scope names the correct book. |
| RUI-A04 | Switching pages, selecting other items, and returning preserves valid drafts and collection position. Close/quit with changed drafts prompts; Cancel stays in the app and failed saves retain text. |
| RUI-A05 | At 660 × 480, 900 × 640, and 1440 × 900 pt, no controls overlap or clip; tools collapse before the reading area becomes unusable, remain reachable when relevant, and disappear when irrelevant. |
| RUI-A06 | Keyboard-only navigation reaches search, import, collection, detail, edit, save, and back. Escape dismisses a sheet without losing drafts; focus returns predictably. VoiceOver announces control names, selection, edit state, and device/job status. |
| RUI-A07 | Light/dark, Increase Contrast, Reduce Transparency, and Reduce Motion remain legible and operable. Verify contrast and long-content layouts; selection and errors remain understandable without color. |
| RUI-A08 | Dictionary import collects CSV metadata before submission; lookup states distinguish empty/no match/failure and never mislabel stale results. Editing and restoring retain the correct dictionary/entry identity. |
| RUI-A09 | Tasks show actual stages and supported actions. Unavailable device/download features remain accurately explained; UI changes do not alter job targets or enable unverified writes. |
| RUI-A10 | Changing Show hidden leaves export inclusion unchanged, and vice versa. Preview and export agree on book and options; drafts are never silently saved or exported. |
| RUI-A11 | Arrow keys retain the collection while moving selection; Return opens detail. Command-F, Command-S, Command-comma, Back, and Escape follow RUI-06 without interfering with native text editing. |
| RUI-A12 | Entering and leaving an unchanged editor needs no discard prompt. Successful save returns to reading; repeated submission does not duplicate work; edits made during an allowed in-flight save remain intact. |
| RUI-A13 | Long diagnostics, Markdown, dictionary definitions, and import forms fit compact windows with reachable actions. Resizing while a sheet or draft is open retains one context and the user's input. |
| RUI-A14 | With two windows, focus and sheet actions remain local to the initiating window; shared draft edits and close/quit handling do not silently lose changes. |

During implementation, run `swift build` and `swift run KindleMarginChecks` using the cache setup documented in
[`README.md`](../README.md). Existing checks verify underlying workflows; they do not establish visual correctness.
Add focused state-transition checks for draft retention, filter/selection behavior, and responsive panel preferences
where the test harness permits. Perform native UI review with an isolated temporary library using synthetic short and
long annotations, bookmarks, duplicate book titles, hidden items, multiple dictionary sources, and failed jobs. Record
actual observations for keyboard, resizing, appearance, and accessibility; keep untested items explicitly unverified.

Capture comparable before/after views using the same fixture data, window size, and appearance. At minimum, inspect
the empty archive, populated collection, long excerpt, changed editor, save failure, dictionary lookup, and tools-open
states in light and dark appearance. Combine compact width with long mixed-script content and enlarged text, then
check Increase Contrast, Reduce Transparency, and Reduce Motion. Verify selection and focus in active and inactive
windows. Record measured contrast and visible clipping/overflow rather than accepting a screenshot as proof of
keyboard access or draft safety. Aesthetic approval remains separate from passing state-transition checks.

Validate the reference-inspired palette, typography, content hierarchy, and collection-to-reading transition in the
running native app. Record implementation and validation gaps honestly; automated model checks do not establish
visual or assistive-technology acceptance.

## Implementation evidence

Implementation and verification results are tracked in [UI redesign validation](../docs/ui-redesign-validation.md).
The reference-inspired presentation is implemented locally. Full acceptance remains open until the explicitly listed
interaction and accessibility checks have been completed; passing model checks does not waive those requirements.
