# V1 implementation and acceptance checklist

Updated 2026-10-22. This tracks the unchanged [V1 contract](../sepcs/kindle-margin-design.md).
The local service workflows and application wiring are implemented. Full V1 acceptance is **not yet established**:
physical-device and release gates remain, and computer-use timeouts prevent the required end-to-end keyboard and
accessibility review. Those UI validation gaps are not relabeled as hardware or release work.

## Requirement traceability

| Criteria | Local implementation and evidence | External or unavailable evidence |
| --- | --- | --- |
| DEV-01 | Launch enumeration, Disk Arbitration/IOKit notifications, model/firmware profiles, mounted browsing | Physical mounted Kindle discovery/readability |
| DEV-02 | Pinned dynamic libmtp, dedicated serial C queue, opaque objects, list/read/write/delete, fake-MTP contract/recovery tests | Physical standard Kindle model/firmware and USB behavior |
| DEV-03 | Unknown devices read-only; Scribe/Fire excluded; explicit capability explanation; empty verified profile list | Physical identity/probe validation |
| DEV-04 | Session invalidation, notification generation checks, busy leases, streaming cooperative cancellation, reconnect UI | Physical busy/disconnect/reconnect timing |
| CLP-01 | UTF-8/BOM UTF-16; English/Chinese types; location/page; original timestamp plus explicit missing/unparsed/local components without invented timezone | Broader real-world fixtures remain useful but are not substituted for existing fixture evidence |
| CLP-02 | Snapshot hashes, versioned fingerprints, incremental source association, conservative incomplete identities and possible-duplicate inspection | None for exercised local cases |
| CLP-03 | Immutable snapshots, raw diagnostics, inspection and conservative reparse retaining overrides | None for exercised local cases |
| CLP-04 | Body/tag/visibility/book overrides, original restoration, metadata correction, regrouping and association evidence | End-to-end input review noted below |
| MD-01 | Shared preview/export renderer, escaping, ordering, explicit book metadata, safe names, conflict copies and previous-file recovery copies | End-to-end chooser/preview interaction |
| MD-02 | File coordination, same-directory temporary writes, hash recheck, failure/cancellation checks, explicit cleanup | Non-cooperating editor races retain a recovery copy rather than assuming all editors coordinate |
| BOOK-01 | Content inspection, frozen plans, staged source hash, actual object return, read-back verification, verified standalone backup | Physical copy/open/indexing behavior |
| BOOK-02 | Converter capability/version/architecture persistence; frozen hash/format/parameters; real synthetic TXT/EPUB conversion and container checks | Physical AZW3 opening/layout |
| BOOK-03 | Optional converter; process/output/time limits; task-owned child cancellation; partial cache removal; original preservation; cache controls | Clean-Mac converter setup is a release check |
| BOOK-04 | Name suffix replanning, execution-time conflict/free-space/source checks, exclusive writes, existing backups preserved | Physical storage reporting |
| BOOK-05 | Exact .sdr association discovery, explicit per-file confirmation, default verified backup, pre-delete recheck, partial-outcome reconciliation without replay | Physical deletion and backup recovery |
| DICT-01 | Bounded JSON/CSV validation, indexed exact/forms/multiple senses, FTS, NaturalLanguage fallback and local entry creation | None for exercised local cases |
| DICT-02 | Durable overrides; original inspection; identity/deletion conflicts; keep-local resolution; priority; merged export; recoverable removal; language identity guard | End-to-end editor/restore input review |
| DICT-03 | Catalog-only HTTPS, host/credential/redirect policy, bounded concurrency, size/hash/schema/identity validation, transactional install; mock disconnection/cancellation/redirect and rollback tests | Licensed real catalog and content redistribution approval |
| DICT-04 | MOBI dictionary identity/language/index inspection, compatible direct-install workflow and default-selection instructions | Distributable usable samples and physical default-dictionary lookup |
| JOB-01 | Unique requests; immutable target/plan; stage events; restart recovery; hash reconciliation; active/unresolved-write guard; reliable identity matching across discovery IDs; cancellation waits for owned processes | Physical interruption matrix; native quit-dialog input review |
| OFF-01 | Local annotations/export/lookup/conversion have no network dependency; network-denied integration run documented below | Native input review remains separate |
| UI-01–06 | Five-page shell, per-window state, conditional tools, compact layout, draft guards, semantic controls, global device status, immutable job targets, native rendering/model checks | See [UI validation](ui-redesign-validation.md) for specific interactive keyboard, accessibility, chooser and lifecycle gaps |

## Local verification

The executable assertion suite uses isolated SQLite libraries, virtual device directories, fake MTP objects, mock
URLSession requests, synthetic books and a synthetic child-process converter. It never opens or writes a physical
Kindle. Command Line Tools on this Mac do not include XCTest; `KindleMarginChecks` is the standalone check runner.

Final frozen-source verification passed on arm64/macOS 14.8.4 (23J319), Swift 5.10:

- MTP-enabled and no-MTP builds both succeeded. Both application binaries are arm64; the MTP binary dynamically links
  the pinned development libmtp. Expected CLT XCTest-path and restricted user-cache warnings do not prevent the builds.
- The no-MTP executable passed all 90 core assertions (`/tmp/kindle-margin-no-mtp-checks.log`).
- The MTP executable passed **142 assertions** with networking denied, including real Calibre TXT/EPUB conversion,
  100,000-entry dictionary lookup, failure/recovery checks and the native UI harness
  (`/tmp/kindle-margin-offline-final.log`, exit 0).
- Exact dictionary lookup measured **0.000280916 seconds** (0.28 ms). Native 10,000-row scroll layout measured
  **0.0349165 seconds** (35 ms), below the unchanged 200 ms check; filtering passed its 100 ms check. These are local
  microbenchmarks, not distribution-wide latency or frame-rate guarantees.
- The new native page-switch test verified restoration of the same 400-point scroll offset. Model checks verified
  that an unresolved reliable device identity blocks writes even when its discovery ID changes, and reconciliation
  releases that guard.
- All **45 native screenshots** were produced under `/tmp/kindle-margin-final-ui`. Native rendering and model checks
  passed; the real-input/accessibility gaps below remain explicitly unverified.
- `Scripts/package-development.sh` produced `/tmp/KindleMargin-V1-Verified.app`. Its executable matches the final
  build; its plist and catalog/profile resource placement were checked. This is a development wrapper with local
  dependency paths, not a signed release.
- Shell syntax, resource JSON and documentation links passed local checks.

Native UI checks render actual NSWindow/NSHostingView views at 660, 900 and 1440 point widths in light/dark appearances,
with empty, reading, editing, search, long mixed-script and high-contrast fixtures. The 10,000-row scroll test retains
its 200 ms threshold. Screenshot/model checks do not prove actual keyboard shortcuts or VoiceOver behavior.

Commands (development paths are specific to this machine):

```sh
KINDLE_MARGIN_MTP_PREFIX=/tmp/kindle-margin-dependencies/install \
CLANG_MODULE_CACHE_PATH=/tmp/kindle-margin-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/kindle-margin-swift-cache \
swift build --disable-sandbox --scratch-path /tmp/kindle-margin-build

KINDLE_MARGIN_UI_CHECKS=1 KINDLE_MARGIN_UI_OUTPUT=/tmp/kindle-margin-final-ui \
KINDLE_MARGIN_PERFORMANCE=1 \
KINDLE_MARGIN_TEST_CONVERTER=/Applications/calibre.app/Contents/MacOS/ebook-convert \
KINDLE_MARGIN_TEST_EPUB=/tmp/kindle-margin-synthetic.epub \
/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
/tmp/kindle-margin-build/debug/KindleMarginChecks

KINDLE_MARGIN_UI_ONLY=1 /tmp/kindle-margin-build/debug/KindleMarginChecks
```

Omit the MTP prefix and use `/tmp/kindle-margin-no-mtp-build` to check the optional-dependency build. SwiftPM's
`--disable-sandbox` only disables its nested build sandbox. Native tests need normal macOS file-coordination IPC;
a restrictive filesystem-only runner failed in NSFileCoordinator and was rerun with that access. The offline test
separately denies network operations to the test process and its converter children.

## Remaining gates

- Physical standard Kindle acceptance for both transports: identity, firmware, directories, busy/disconnect/cancel,
  transfer/read-back, opening/indexing, deletion/backup and dictionary lookup. Populate verified profiles only from
  recorded evidence. No physical Kindle was available; the bundled profile list remains empty.
- Licensed download catalog and usable dictionary samples. The bundled catalog remains empty; local dictionary
  import and mock transport tests work independently.
- Distribution: libusb pin/build, dependency license/source obligations, embedded architecture-compatible dylibs,
  signing, notarization, installation and USB access on a clean Mac. Intel support remains uncommitted.
- Local interactive UI acceptance blocked by the computer-use connection: exact gaps and rendered evidence are
  recorded in [UI validation](ui-redesign-validation.md). Do not claim only hardware/release gates remain while these
  checks are unavailable.

No release, publishing, deployment, push, or signing was performed. This directory is not a Git repository.

## Task resource cleanup

The final isolated preview used `/tmp/KindleMargin-V1-Final.app`, library `/tmp/kindle-margin-v1-final-library`, PID 7513,
terminal session 41770, repository working directory, no listening port. SIGTERM completed with exit 143. Earlier
previews from this task were also stopped. The coordinated UI task records its own preview cleanup in its evidence.
The final full suite (terminal session 72060) exited 0; finite test harnesses close their native windows and remove their temporary libraries. No browser tab or server was
created. A final process inventory confirmed no remaining KindleMargin preview/check runner, build, or converter process. No listening ports were allocated. Build products, screenshots and dependency prefixes remain as development artifacts, not running services.
