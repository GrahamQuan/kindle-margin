# UI redesign validation

Date: 2026-10-22. Contract: [Kindle Margin UI Redesign](../sepcs/kindle-margin-ui-redesign.md).
Status: implemented locally; comprehensive UI acceptance remains open.

## Implementation

- Reference-inspired blue/lilac/blush shell, native sidebar with bottom Settings, neutral primary action, rounded opaque
  main content surface, dark appearance, and compact navigation collapse.
- Window-local navigation, search, selection, reading/editing mode and focus commands in `WorkspacePresentation`;
  shared stable-ID annotation and dictionary drafts in `WorkspaceModel`.
- Book-grouped collection, explicit read/edit transitions, saved-only export scope, independent hidden-item export
  inclusion, retained snapshots/reparse, tags, regrouping, book metadata, dictionary management and device actions.
- Save guards preserve drafts on failure and retain edits made after submission. Changed drafts participate in
  window-close/quit decisions. Menu commands target the focused window. Existing running-job quit protection remains.
- Dictionary import metadata is collected in its flow; lookup distinguishes idle/loading/no results/failure and rejects
  stale responses. Existing dictionary conflict and recovery controls remain available in management.

## Executed checks and evidence

`swift build --disable-sandbox` builds the application and acceptance executable using the cache environment from
README. The extra flag disables SwiftPM's build sandbox; native execution also needs normal macOS IPC permissions.
The first restricted run failed in NSFileCoordinator before reaching UI checks and was rerun with those permissions.

Both final builds (with and without MTP support) passed after source freeze. The build without MTP passed
all 90 core acceptance assertions. The focused native UI run passed 48 assertions and produced 45 screenshots.
The coordinated final frozen-source run passed all 142 assertions with networking denied, including core workflows,
real Calibre conversion, native UI, device identity guards, and scroll restoration. Final native scrolling measured
34.9 ms. Its log is `/tmp/kindle-margin-offline-final.log`, with 45 screenshots in `/tmp/kindle-margin-final-ui`.

The native harness can be run independently:

```sh
KINDLE_MARGIN_UI_ONLY=1 KINDLE_MARGIN_UI_OUTPUT=/tmp/kindle-redesign-ui .build/debug/KindleMarginChecks
```

It creates an isolated temporary SQLite library and fake device, renders real NSWindow/NSHostingView content, and
closes its window and removes its temporary library at completion. It does not read user books or write a real Kindle.

- Model checks cover unchanged versus dirty drafts, successful annotation/tag save, failed annotation save retaining
  text and releasing its save lock, dictionary save, independent browse/export flags, per-window navigation, existing
  selection retention, persisted panel preference, device-selection invalidation, and reliable device identity blocking
  unresolved writes after a session identifier changes. Completed jobs release that guard.
- The 10,000-annotation filter check retains its 100 ms limit. Native 10,000-row scroll layout retains its 200 ms limit;
  final focused runs measured about 35–37 ms. A temporary all-pages-mounted implementation regressed to 770 ms and
  was replaced with active-page layout plus scene-local native scroll memory. A native page-switch assertion confirms
  restoration from 400 pt to 400 pt, awaiting attachment for at most two seconds. These are local microbenchmarks,
  not a frame-rate guarantee.
- Native screenshots cover all five pages at 660 x 480, 900 x 640, and 1440 x 900 content sizes, in light and dark
  appearance, plus annotation reading/editing/no results and dictionary results/reading. The 45 captures also cover
  an empty archive, long mixed-script content at compact width, tools, and high-contrast dark appearance.
- Screenshot review found and corrected compressed sidebar titles and a missing automatic compact-sidebar collapse.
  Screenshots and logs live under `/tmp/kindle-redesign-ui` and `/tmp/kindle-redesign-ui-checks.log`.
- Native key-view traversal asserts that first responder is an NSView. This does not establish every shortcut or
  end-to-end keyboard workflow.

## Continuation review on 2026-10-22

A fresh `run-spec` review preserved the existing visual direction and found additional interaction defects:

- Saved dictionary definitions updated the open entry but left cached result rows stale. Returning to a result could
  reopen the pre-save definition. Saved text and edited/original status now propagate to the window's cached results
  and selected entry, including when the dictionary page is mounted again. Restore updates the same cache.
- Dictionary result selection is now independent from opening a reading surface; Return opens the selected result.
- Sheet presentation records its trigger and page before opening. Dismissal requests focus on that trigger or a
  surviving page control; editing requests focus after the editor mounts. Real-input focus behavior remains unverified.
- Annotation text selection is now window-local, so selected-word lookup cannot reuse another window's text selection.
- Async previews reject completion after their initiating context has disappeared. Export scope content scrolls.
- Disabled primary buttons have a distinct appearance. New operation feedback requests an accessibility announcement
  from the active window only; actual VoiceOver output remains unverified.

`swift build --disable-sandbox` passed. The required `swift run --skip-build --disable-sandbox KindleMarginChecks`,
with `KINDLE_MARGIN_UI_CHECKS=1`, passed all 143 assertions. Logs are in `/tmp/kindle-ui-continuation-build.log` and
`/tmp/kindle-ui-continuation-checks.log`; screenshots are in `/tmp/kindle-ui-continuation-evidence`.
The final presentation build also passed all 53 native/UI assertions after the focus refinements, with 45 captures
in `/tmp/kindle-ui-continuation-final` and log `/tmp/kindle-ui-continuation-final.log`. Native scrolling measured 37.0 ms.
Five new checks cover selection versus opening, saved-result synchronization, restored original status, deterministic
in-flight edits with duplicate submission, and injected dictionary persistence failure. These exercise actual
persistence through a controlled repository gate; they do not simulate physical keyboard input or closing dialogs.

The native automation app connection was retried against the rebuilt isolated app and timed out after approximately
53 seconds, before any UI action could be performed. This remains a concrete local interaction-validation blocker.

## Remaining acceptance gates

### Native automation diagnosis on 2026-10-22

- CUA inventory completed in approximately 6 seconds. Connecting to the pre-existing Finder app also timed out,
  including a retry with a 60-second execution limit. The failure is not confined to Kindle Margin.
- macOS TCC logs for the native helper returned `authValue=2` and `error=(null)` for Accessibility and ScreenCapture
  checks. No permission reset was attempted.
- The shared `SkyComputerUseService` (PID 39036) and Codex (PID 38669) repeatedly reconnected to `replayd` (PID 46408).
  ReplayKit logged `XPC_ERROR_CONNECTION_INTERRUPTED`, `connection INTERRUPTED`, and capture-stop errors.
  This implicates the shared capture path but does not prove the underlying cause.
- CUA reset its execution kernel after timeouts; this did not restore app connections. No documented helper-restart
  operation is available through the exposed tool. Restarting the desktop app is the next recovery attempt and has
  not yet been performed or verified.
- No actual keyboard, close-dialog, or VoiceOver acceptance is claimed. Resume with a Finder connection smoke check,
  then launch a fresh isolated Kindle Margin build and complete the real-input gates below.
- This diagnostic pass created no preview services or browser resources. Shared Codex, capture services, and the
  pre-existing Finder process were preserved.

Comparable pre-redesign screenshots using this same fixture were not captured. Native screenshot review covers the
implemented result; it does not establish before/after parity or aesthetic approval.

The computer-use app connection timed out by both app path and bundle identifier, although inventory recognized the
isolated validation app. No mouse actions or shortcut sequences were successfully driven through that tool.

| Contract | Remaining evidence |
| --- | --- |
| RUI-A01/A03/A08 | End-to-end file chooser, preview/export, dictionary import, restore and cancel actions via real input. Model persistence and rendered states are covered separately. |
| RUI-A04/A12/A14 | Actual close/quit Save All, Discard, Cancel and save-failure dialogs; simultaneous two-window editing/closing; input arriving during an in-flight save. |
| RUI-A05/A13 | Interactive resize while sheets are open; full long-title/import-form matrix; exact selection/focus restoration after dismissal. |
| RUI-A06/A11 | Real arrow/Return/Escape/Command-F/Command-S/Command-comma sequences, VoiceOver announcements and Voice Control names. |
| RUI-A07 | Measured contrast for every text/control state, enlarged-text review, active/inactive window comparison, and actual Reduce Transparency/Reduce Motion settings. High-contrast appearance capture is not a substitute for this matrix. |

These are local UI acceptance gates, not physical-device or release gates. Do not mark the redesign fully accepted
until they pass. No deployment target, dependency, or physical-device compatibility promise was changed.

## Temporary resource ownership

The isolated live app used `/tmp/KindleMarginUI.app` and `/tmp/kindle-redesign-live-library` (PID 5886, terminal session
10549, repository working directory, no listening port). It was gracefully terminated with SIGTERM; the terminal
reported exit 143. CUA did not create browser tabs or sessions. The focused native test process exited with status 0
and closed its window. A process check found no task-owned preview or check process; the separately coordinated
core task subsequently completed its final combined validation and confirmed cleanup of its test/converter processes.
No development server or listening port was started.

The continuation preview used `/tmp/KindleMarginUIContinuation.app`, temporary library
`/tmp/kindle-ui-continuation-library`, PID 10360, terminal session 99455, and the repository working directory.
It had no listening port. SIGTERM completed with exit 143 after the automation timeout. No browser resources were
created or changed. Acceptance harness processes own finite windows and close them before exiting.

The final native harness (PID 10903, session 46920, repository working directory, no port) exited with status 0.
