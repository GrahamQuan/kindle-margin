# Kindle Margin V1 Requirements and Code Architecture

- Display name: **Kindle Margin**
- Repository: `kindle-margin`
- App target / Swift module: `KindleMargin`
- Document version: 1.0
- Updated: 2026-10-22
- Status: local workflows implemented and automated checks passing; interactive UI acceptance, physical-device validation and release gates tracked in docs/acceptance.md
- Platform: native macOS desktop application built with SwiftUI

In this document, "must" identifies a V1 acceptance requirement; "recommended" identifies an adjustable implementation
choice; and "requires validation" means technical validation is required before claiming support. Implementation must
not present design goals as existing capabilities.

## 1. Product positioning and goals

Kindle Margin is a Kindle companion centered on local processing. Users connect a standard Kindle over USB, archive
reading annotations as Markdown, manage books on the device, and use importable, editable offline dictionaries to
support English reading.

V1 must support four user workflows:

1. Connect a Kindle → read My Clippings → organize annotations → export Markdown.
2. Drop in books → assess device compatibility → convert locally if necessary → transfer to Kindle.
3. Browse device books → choose backup or deletion → verify the outcome.
4. Import or download dictionaries → look up words offline → edit local entries; separately install ready-made Kindle
   device dictionaries.

By default, no Amazon account is required and no books, annotations, or dictionary entries are uploaded. Except for
user-initiated dictionary downloads, core workflows do not depend on a network connection.

## 2. V1 scope

### 2.1 Included capabilities

| Area | Required V1 capabilities |
| --- | --- |
| Desktop application | Native SwiftUI window, sidebar navigation, job progress, settings, and readable errors |
| Standard Kindle connection | Mounted-volume and MTP modes; discover devices already connected at launch; connection and disconnection notifications |
| Annotation archiving | Import My Clippings manually or from a device; retain original snapshots; incremental import and deduplication |
| Annotation organization | Display highlights, text notes, and bookmarks; search and filter by book; local corrections, hiding, and association changes |
| Markdown | Preview and export by book; preserve original text, locations, and parseable timestamps; avoid overwriting user edits |
| Device library | Enumerate accessible books, import, back up, and delete; distinguish device files from local files |
| Conversion | Determine direct transfer, required conversion, or unavailability; convert supported files with local Calibre |
| App dictionaries | JSON/CSV import, entry editing, offline lookup, inflection indexes, and multiple-dictionary priorities |
| Dictionary downloads | Download supported packages from a product-configured catalog; validate before installation; work offline after installation |
| Kindle dictionaries | Install existing files with verified compatibility; prompt users to select a default dictionary on Kindle |
| Job management | Show stages, cancellation, failure reasons, and available retries; reconcile outcomes after disconnection |

### 2.2 Exclusions

- Kindle Scribe, including Scribe handwritten notes, ink, and handwriting OCR.
- Kindle Fire tablets and Kindle mobile or desktop reading apps.
- Amazon account login, cloud libraries, Send to Kindle, and cross-device cloud synchronization.
- Whole-book conversion to Markdown; V1 Markdown is generated from annotations and text notes.
- DRM removal or format conversion of protected content.
- Modification of Kindle internal databases or system settings; reading-progress and collection management.
- Compiling app-edited entries into Kindle dictionaries; in-place editing of device dictionaries.
- Scanned-PDF OCR, complex PDF reflow, and KFX conversion plugin management.
- Bidirectional editing or deletion synchronization of device annotations.
- Built-in online translation, cloud LLM analysis, browser extensions, or mobile applications.

### 2.3 Compatibility commitments

"Standard Kindle" defines product scope, not support for every untested model and firmware. Maintain a compatibility
table covering model, firmware, connection protocol, and supported operations. Before release, validate at least one
standard Kindle in mounted-volume mode and one standard Kindle in MTP mode.

Excluding Scribe does not remove the need for MTP: newer standard Kindles may also use it. For a recognized Scribe,
show "This device is not supported in V1" and do not enter book-write workflows. Unidentified devices may expose
diagnostics and redetection, but writes are disabled by default. A volume name of "Kindle" alone does not establish
identity.

## 3. Technical and delivery decisions

| Area | V1 design choice | Notes |
| --- | --- | --- |
| Minimum OS | macOS 14+ | Confirmed 2026-10-22; Apple Silicon initially, Intel support uncommitted |
| UI | SwiftUI, with AppKit where needed | Bridge to AppKit for file selection, saving, and system interactions |
| State | Observable `@MainActor` ViewModels | Views do not perform file, USB, database, or conversion work |
| Concurrency | Swift Concurrency plus dedicated blocking-I/O queues | Keep blocking libmtp calls off the main thread and cooperative thread pool |
| Local storage | SQLite plus filesystem directories | Store relationships, indexes, and job logs in the database; do not store large files as BLOBs |
| Device connection | Disk Arbitration, USB discovery, and a libmtp adapter | Pin and validate dependency versions and device support |
| Conversion | The user's local Calibre `ebook-convert` | V1 does not bundle full Calibre or require a separate Python installation |
| English analysis | NaturalLanguage plus dictionary-provided inflections | Lemmatization failure must not block exact lookup |
| Networking | `URLSession` | Only dictionary catalogs and user-initiated dictionary downloads |
| Distribution | Signed and notarized App/DMG distributed directly, recommended | V1 does not target the Mac App Store; validate USB permissions, helpers, and signing |

Annotation export, device browsing, direct transfer, and lookup must remain available when no converter is configured.
Do not require Calibre installation at startup.

Apple Silicon is the recommended primary validation platform for V1. If an Intel package is provided, independently
validate architecture compatibility for the app, USB dependencies, and converter. Code signing does not imply
successful notarization.

## 4. Dashboard UI and UX

### 4.1 Main window and visual direction

Use a dashboard-style application shell with three regions: navigation tabs on the left, the active page's main
content in the center, and an optional contextual tools panel on the right. The center is the primary workspace;
the right panel is not a mandatory detail column. Do not add a metrics overview page merely to resemble a dashboard.

- Left: persistent, vertically arranged tabs with icons and text labels for Annotations, Device Library, Dictionaries,
  Tasks, and Settings. Show a clear selected state; keep Settings at the bottom of the navigation area.
- Center: a page heading, a compact toolbar for relevant search, filters, and primary actions, followed by the page's
  content. Use tables or lists for collections, a reading or editing surface for selected content, and forms for settings.
- Right: contextual metadata, options, or secondary actions for the active page or selection. Show this panel only when
  it provides useful content or actions. When none exist, remove the panel and its divider entirely and give the space
  back to the center; do not render an empty column or placeholder inspector.
- Use restrained surfaces, subtle separators, consistent spacing, readable typography, and one accent color for
  selection and primary actions. Support light and dark appearance. Avoid decorative cards around every control,
  redundant statistics, and competing primary actions.
- Keep global device selection and connection status in a consistent shell location. Use explicit states: Disconnected,
  Connecting, Available, Read-only, Busy, and Connection failed. With multiple devices, let the user select the active
  one. Each queued job remains bound to its original target device when the visible device changes.

### 4.2 Page composition

| Navigation tab | Center workspace | Optional right tools panel |
| --- | --- | --- |
| Annotations | Book grouping, search, type filters, annotation reading and local editing, Markdown preview | Selected annotation metadata, original-content inspection and restore actions, or export options |
| Device Library | Current device files, formats, sizes, available capacity, import and transfer planning | Selected file details and applicable backup or delete actions |
| Dictionaries | Installed dictionaries, priority ordering, offline lookup, entry editing, download catalog and device dictionary installation | Selected entry provenance or dictionary details and applicable options |
| Tasks | Queued, running, cancelled, failed, and completed jobs with progress | Selected job stages, diagnostics, and available cancel or retry actions |
| Settings | Export rules, converter location, cache management, and diagnostics settings | Hidden by default; show only when a specific setting has useful contextual controls |

The table describes possible panel content, not a requirement to display every item at once. Primary workflows must
remain discoverable from the center toolbar or content even when the right panel is closed. Selecting a detail view
must not create a permanent fourth column; keep reading and editing in the center and supporting tools on the right.

### 4.3 Navigation and panel behavior

- Switching tabs changes the center page and recomputes the right panel from that page's context. Never show stale
  actions or selection details from the previous page.
- Preserve useful page-local search, filters, selection, and scroll position when returning to a tab, provided the
  underlying data still exists. Switching tabs must not cancel background jobs or silently discard unsaved edits.
- If a selection disappears, clear its contextual actions immediately. Hide the panel if no page-level tools remain.
- Provide a labeled control to close or reopen the right panel when contextual tools exist. Remember the user's
  collapsed preference per page; selection changes must not repeatedly force it open.
- As the window narrows, collapse the right panel before sacrificing the center's usable reading or editing area.
  Expose its available tools through a labeled button opening a dismissible panel or sheet. When no tools exist, hide
  that button too. At still narrower widths, allow the navigation sidebar to collapse behind an accessible toggle.
- Exact widths and spacing are implementation choices to validate during UI review. Avoid clipped controls, overlapping
  columns, or horizontal scrolling of the entire application shell.
- Support keyboard navigation, visible focus, accessible control names, and non-color indicators of selection and
  status. When a panel closes or its selected item disappears, return focus to a relevant surviving control.

### 4.4 Loading, empty, offline, and error states

- Keep loading, empty, and failure states inside the affected center page or panel, with a clear next action where one
  exists. Do not replace the entire shell for a page-specific error or move content as a progress indicator appears.
- Without a device, keep local My Clippings import, archived annotations, Markdown export, offline dictionary lookup,
  and configured local conversion available. Device-dependent actions must explain why they are unavailable.
- Without a network connection, retain installed dictionaries; a download failure must not disrupt lookup.
- If another MTP application occupies the device, suggest closing the relevant transfer application and retrying.
  Do not terminate other processes on the user's behalf.
- Distinguish no device, unreadable file, missing My Clippings, and empty file states.

### 4.5 Write interactions

Before book import, show the files, target device, target format, conversion requirements, and naming conflicts.
Conversion starts only after the user confirms the plan.

Before deletion, show the specific books, associated files, and backup options. Deleting a device file and deleting a
local copy must be separate actions. Confirmation is bound to the file identity and connection session; never replay
it blindly after reconnection. Destructive actions in a right panel follow the same confirmation rules.

### 4.6 Presentation boundaries

The application shell owns the active tab, page-local navigation state, and panel visibility. Each feature supplies
its center content and only the contextual tools applicable to its current selection and capabilities. The shell must
not infer device write permissions from the presence of an action button; feature actions use the existing capability
and session checks. UI layout changes do not alter job ownership, device I/O scheduling, or persistence boundaries.

### 4.7 Proposed UI redesign

See the [UI redesign specification](kindle-margin-ui-redesign.md) for the proposed visual direction, interaction
refinements, technical approach, and acceptance criteria. It is implemented locally with interaction and accessibility
acceptance still open; see [UI validation evidence](../docs/ui-redesign-validation.md). It preserves the V1 scope.

## 5. Device connection and file access

### 5.1 Discovery and sessions

`DeviceDiscovery` discovers candidate devices; `DeviceSession` owns handshakes, identity, capabilities, and connection
lifecycle. Neither reads annotation content nor modifies books.

Discovery flow:

1. Enumerate mounted volumes and USB candidates at launch.
2. Subscribe to disk and USB connection/disconnection events and handle duplicate notifications.
3. Establish identity using USB identifiers, protocol, and device responses, not display names.
4. Confirm the device is within standard Kindle support scope and establish a connection session.
5. Probe storage, accessible directories, read/write permissions, and available capacity.
6. Produce a capability set; unknown capabilities remain unknown rather than being inferred as supported.

Prefer reliable device serial information for long-term identity. Without a stable identifier, mark the identity as
temporary and never merge it automatically with historical devices. Exclude serial numbers from default diagnostics.

Generate a new `sessionID` for each connection. Disconnection invalidates that session's file references and pending
writes. Reconnection requires rescanning objects; never reuse old MTP object IDs.

### 5.2 Two transport adapters

| Adapter | Operation model | Constraints |
| --- | --- | --- |
| `MountedVolumeTransport` | File operations relative to the volume root | Validate actual file locations; prevent escaping the device root and unsafe symbolic links |
| `MTPTransport` | Storage IDs, object IDs, and object metadata | Do not assume POSIX paths, random writes, atomic rename, or a trash facility |

Expose opaque file references and list, download, upload, and delete operations through one interface. Upload returns
the actual created object; business logic must not construct underlying object IDs.

The following protocol is a sketch. Implementation may adjust type details while preserving path and object-ID
encapsulation:

```swift
struct DeviceFileRef: Hashable, Sendable {
    let deviceID: DeviceID
    let sessionID: UUID
    let locator: OpaqueDeviceLocator
}

protocol DeviceTransport: Sendable {
    func list(in directory: DeviceFileRef) async throws -> [DeviceEntry]
    func download(_ file: DeviceFileRef, to destination: URL) async throws
    func upload(_ source: URL, into directory: DeviceFileRef,
                name: String) async throws -> DeviceFileRef
    func delete(_ file: DeviceFileRef) async throws
}
```

### 5.3 Capability model

`DeviceCapabilities` describes at least reading, writing, deletion, available-space reporting, renaming, verifiable
file transfer, and verified ebook formats. Capabilities, model information, and runtime probes jointly determine the
import plan.

Serialize I/O for each device through one queue. An actor alone does not guarantee mutual exclusion for a whole
operation across `await` boundaries; use explicit operation scheduling or leases. Different devices may have
independent job queues.

Run the MTP C API on a controlled, dedicated execution queue. Implement cancellation through supported API callbacks
or checks between operations; never forcibly close an in-use device handle from another thread.

## 6. My Clippings import, organization, and Markdown

### 6.1 Input and flow

Accept `My Clippings.txt` from the device or a user-selected local copy. Locate device directories through the adapter.
If the file cannot be found, allow manual selection; do not infer missing content from a book database.

```text
Download from device or copy a local file
  → Immutable local snapshot
  → Encoding detection and record splitting
  → Language-specific metadata parsing
  → Structured records and parsing diagnostics
  → Incremental merge
  → Organization by book
  → Markdown preview and export
```

V1 must fully cover Chinese and English metadata samples. Preserve other languages verbatim and mark them as
unsupported for now; do not discard data or create apparently valid records with incorrect dates.

### 6.2 Parsing requirements

- Support UTF-8, BOMs, and LF/CRLF; handle recognizable UTF-16. Prompt when encoding is uncertain instead of silently
  replacing characters.
- Parse record boundaries and metadata structure; do not process the whole file with one large regular expression.
- Identify highlights, notes, and bookmarks; retain bookmarks without body text.
- Store locations and page numbers separately, allowing missing values or ranges; never convert one into the other.
- Preserve the original timestamp string and parsing status. Do not fabricate a UTC instant when the source lacks a
  timezone.
- Preserve the full book description when parentheses in the title or ambiguous author boundaries prevent reliable
  separation.
- Send incomplete final records, truncated content, and unrecognized records to a diagnostics list with the original
  text available for inspection.
- Report counts of new, existing, and unparsed records.
- Store the complete original snapshot and parser version to support later reparsing.

### 6.3 Deduplication and book association

Reuse snapshot records when file SHA-256 hashes match. Use versioned annotation fingerprints incorporating normalized
book description, record type, location/page, original timestamp, and body. Normalization removes only line-ending
and surrounding-whitespace differences known to have no semantic effect.

Retain identical text when its location, timestamp, or record type differs. Multiple snapshots link to the same
annotation through a source-association table. When missing fields make identity unreliable, retain records and mark
possible duplicates instead of merging destructively.

Represent book identity with a local UUID, never the title as a unique key. My Clippings book descriptions may not
reliably match device files. Automatic associations must record their evidence and confidence, and users must be able
to split or adjust groups.

My Clippings is not an authoritative synchronization database for current device annotations. Missing records in
later snapshots do not delete local history; local annotation edits are not written back to the device.

### 6.4 Local editing

Original annotations are immutable. Store body corrections, tags, hidden state, and book-association changes in a
separate override layer. The detail interface must allow users to inspect the original and revert local changes.

Associate a note with a highlight only when book, location, and other evidence are sufficient. Adjacency alone does
not establish an association. Show unconfirmed notes independently.

### 6.5 Markdown export

Default to one UTF-8 file per book using standard Markdown. Use a safe title and a short local-book-ID suffix in the
filename to avoid collisions. Sort by location by default; retain stable import order for records without locations.

Export the title, author when reliable, highlight text, text notes, bookmark locations, and available locations, page
numbers, and original timestamps. Omit missing fields instead of inventing values. Let users choose whether to include
local tags and hidden records; exclude hidden records by default.

```markdown
# Example Book

Author: Example Author

## Highlights

> Text highlighted while reading.

- Location: 245–248
- Annotation time: 2026-10-22 09:30 (source does not specify a timezone)

## Notes

This approach can be used for daily reading.

## Bookmarks

- Location: 520
```

Preview and export must use the same renderer. Handle Markdown special characters, multiline quotations, and reserved
filename characters correctly.

The export manifest stores the destination file and the hash of the last generated content. On re-export, update
unmodified destinations; if user edits are detected, create a conflict copy or require an explicit overwrite choice.
Write to a temporary file in the destination directory before publishing the result. Cancellation or failure must not
damage an existing file. V1 does not provide arbitrary scripts or a complex template language.

## 7. Device library and format conversion

### 7.1 Library model

Distinguish these concepts:

- `LibraryBook`: a logical book used for annotation grouping and user metadata.
- `BookFile`: a specific local or device file, including format, size, source, and identity information.
- `BookArtifact`: a converted file with its input hash, converter version, and parameters.
- `BookAssociation`: an association between logical books and files; not necessarily one-to-one.

Show device files promptly, then read titles and authors on demand. Fall back to filenames when metadata reading
fails. The library is a view of accessible device content, not a claim to represent the complete Amazon cloud library.

### 7.2 Format planning

`ImportPlanner` uses file signatures and structure, target-device capabilities, converter capabilities, and protection
status to produce one of three outcomes:

```swift
enum ImportDecision {
    case directTransfer(TransferPlan)
    case conversionRequired([ConversionPlan])
    case unavailable(ImportFailureReason)
}
```

| File category | V1 policy |
| --- | --- |
| AZW3, PDF, TXT, MOBI, or other formats verified on the target model | Allow direct transfer after structure and readability checks; maintain support per model |
| Unprotected EPUB | Offer conversion to AZW3, then transfer to a device with verified AZW3 support |
| DOCX, HTML, RTF | Offer AZW3 conversion when the local converter confirms support for that input |
| Scanned PDF | Transfer directly according to device capabilities; no automatic OCR or guaranteed reflow |
| KFX or unknown compound formats | No V1 conversion commitment; enable only independently verified direct-transfer workflows |
| Protected, damaged, or unparseable content | Explain each reason separately; never suggest changing an extension makes it usable |

Treat offline USB formats separately from Send to Kindle cloud input formats. Extensions are not sufficient evidence,
and renaming is not conversion. An extension alone cannot establish whether protected content is readable on a device.

### 7.3 Converter adapter

V1 uses `CalibreConversionEngine`. Users select and validate a local `ebook-convert` from Settings. Record its version,
architecture, and capabilities; do not automatically execute a same-named program from an untrusted path or environment
variable.

Launch using a `Process` executable URL and argument array, never a constructed shell command. Use absolute paths and
a separate working directory for each job, bound execution time and log size, handle cancellation, and wait for the
child process to exit.

Conversion plans freeze input identity, output format, parameters, and converter version. Revalidate input before
execution and replan if it has changed. Cache keys include the input content hash, converter version, and all effective
parameters.

Successful process exit is only the first check. Also verify that the output exists, is nonempty, has the expected
format, and has readable basic structure. Perform manual device-reading acceptance where needed; successful conversion
on a Mac does not guarantee identical Kindle layout.

### 7.4 Transfer and deletion

Before transfer, check the target session, write permission, available space, and naming conflicts. Do not overwrite
same-named files by default; prefer a safe conflict suffix. Replacement requires an explicit choice and a backup.

After upload, query the actual object and size. Read the file back and compute its content hash before marking the
transfer fully complete; V1 prioritizes integrity. If the device cannot support full verification, report verification
failure or an unverified result rather than "verified successfully."

"Transfer complete" means the file has been written and verified, not that Kindle has finished library indexing or
that opening the book has been validated.

Deletion plans list the main file and confirmed associated files such as `.sdr` content. Do not automatically delete
uncertain associations or use fuzzy filename prefixes to delete directories. Create a local backup by default; users
may explicitly skip it. A failed backup must not be presented as recoverable.

Mounted-volume mode may use same-volume temporary files and renaming when their availability is confirmed. MTP mode
must not depend on atomic rename. Replacement must retain the original or a verified backup, log each stage, and enter
reconciliation after failure. If safe replacement is unavailable, use a new filename instead.

## 8. Dictionary system

### 8.1 Separate dictionary types

| Type | Purpose | V1 editability |
| --- | --- | --- |
| App lookup dictionary | Look up English words from annotations on the Mac | Add, edit, and hide entries |
| Kindle device dictionary | On-device lookup while reading on Kindle | Install existing compatible files without modifying internal indexes |

Both types share download-job and file-validation infrastructure, but have different formats, installers, and
compatibility rules. Copying an app JSON dictionary to Kindle does not make it a usable device dictionary.

### 8.2 App dictionary input formats

V1 must provide JSON and UTF-8 CSV templates. JSON supports the complete field set. CSV is a flat import format with
columns `headword,definition,partOfSpeech,example,forms`; `headword` and `definition` are required, and `forms` uses `|`
as a separator. Users enter the CSV dictionary name and languages in the import interface.

Recommended JSON package structure (the Chinese definition is intentional multilingual dictionary data):

```json
{
  "schemaVersion": 1,
  "id": "example-en-zh",
  "version": "1.0.0",
  "name": "Example English-Chinese Dictionary",
  "sourceLanguage": "en",
  "targetLanguage": "zh-Hans",
  "license": "User-owned entries",
  "entries": [
    {
      "id": "run-verb-1",
      "headword": "run",
      "partOfSpeech": "verb",
      "definition": "跑；运行",
      "example": "I run every morning.",
      "forms": ["runs", "ran", "running"]
    }
  ]
}
```

Allow multiple senses and parts of speech for the same word; the headword is not an entry's unique ID. Report the exact
row or entry for field-validation failures. Import through a temporary database or transaction so failure does not
leave a partially installed dictionary. Treat definitions as plain text; do not execute HTML or scripts in them.

### 8.3 Lookup and English analysis

Support lookup from a selected annotation word and from a query field. V1 does not automatically turn a whole book
into a vocabulary list.

Lookup order: exact original-text match → Unicode and case-normalized match → explicit dictionary inflection match →
candidate matches after NaturalLanguage lemmatization. Preserve multiple candidates and their sources instead of
forcing a single allegedly correct meaning.

Use database indexes for exact lookup and inflections. Use FTS for definition and entry search, not as a substitute
for morphological semantics. Exact lookup remains available when NaturalLanguage is unsupported or cannot identify a
word.

Return results from multiple dictionaries in user-defined priority order, with user-created or edited entries first.
Details identify the source dictionary and whether the entry was edited by the user.

### 8.4 Editing and updates

Base packages are read-only. Store additions, replacements, and hidden entries in `EntryOverride`. Support inspecting
the original entry, undoing edits, and exporting merged JSON.

Install updates as complete new versions before switching the active version. Use stable entry IDs to migrate
overrides. Preserve entries deleted upstream or with changed identities as unresolved conflicts; never silently lose
user edits. When deleting a dictionary, explain whether edit records will also be deleted and retain recoverable data
by default.

### 8.5 Download catalog and installation

V1 uses a product-configured HTTPS dictionary catalog and does not execute installers from arbitrary addresses. The
catalog manifest includes at least package ID, version, dictionary type, languages, size, SHA-256, download URL, source,
and licensing information.

```text
User selects a download
  → Check network and available space
  → Download a temporary file
  → Validate size and SHA-256
  → Validate schema or device-dictionary format
  → Install transactionally
  → Update the local catalog
```

Hashes verify integrity, not source trust. Follow only allowed HTTPS redirects; packages must not contain executable
code. V1 should prioritize direct JSON or compatible dictionary-file downloads and need not support arbitrary archives.

On disconnection, cancellation, or validation failure, delete this download's temporary files and retain the previous
version. Do not check for updates in the background by default. Before release, identify at least one real dictionary
package licensed for distribution and an available catalog URL. Development tests use mock HTTP services and synthetic
entries.

### 8.6 Kindle dictionary installation

Accept existing, verified compatible dictionary files. Read source language, target language, and dictionary identity
when available. If these cannot be confirmed, explain that device lookup cannot be guaranteed; do not automatically
install an ordinary MOBI as a dictionary.

Reuse device-transfer workflows for installation, but do not replace system dictionaries or edit device system
databases. After installation, guide users to select the default dictionary in Kindle Settings. Maintain instructions
for verified models.

Automatic compilation of custom Kindle dictionaries is outside V1. It requires dedicated language metadata, lookup
indexes, and build tools; ordinary AZW3 conversion cannot substitute for it.

## 9. Code organization and dependency boundaries

Use feature-oriented MVVM, use-case services, and adapters. V1 remains a single desktop application without HTTP
services, distributed job systems, or dynamic code plugins.

```text
kindle-margin/
├── App/
│   ├── KindleMarginApp.swift
│   ├── AppContainer.swift
│   └── Navigation/
├── Features/
│   ├── Devices/
│   ├── Clippings/
│   ├── Library/
│   ├── Dictionaries/
│   ├── Tasks/
│   └── Settings/
├── Packages/
│   ├── KindleDomain/
│   ├── KindleApplication/
│   ├── KindleDevice/
│   ├── KindleClippings/
│   ├── KindleDictionary/
│   ├── KindleConversion/
│   └── KindlePersistence/
├── Resources/
│   ├── Localizations/
│   └── DictionaryCatalog/
├── Tests/
│   ├── Fixtures/
│   ├── Unit/
│   ├── Integration/
│   └── UI/
└── docs/
    ├── design.md
    └── compatibility.md
```

These `Packages` are logical modules. Initially, multiple targets in one local Swift Package may implement them,
avoiding premature separation into independent repositories.

| Module | Responsibilities | Prohibited dependencies or behavior |
| --- | --- | --- |
| `KindleDomain` | Value types, protocols, plans, capabilities, and errors | SwiftUI, USB, SQLite, and process execution |
| `KindleApplication` | Import, export, transfer, deletion, and other use cases; job orchestration | Direct libmtp calls or concrete database SQL |
| `KindleDevice` | Discovery, sessions, mounted-volume/MTP adapters, capability probes | Markdown, dictionary definitions, and UI state |
| `KindleClippings` | Snapshot parsing, fingerprints, association suggestions, Markdown rendering | Modifying Kindle files or making network requests |
| `KindleDictionary` | Dictionary parsing, lookup, override rules, catalog-download adapters | Modifying Kindle system settings |
| `KindleConversion` | Converter detection, argument planning, process execution, artifact validation | Operating the UI or automatically uploading to a device |
| `KindlePersistence` | Repositories, migrations, transactions, file storage | Business decisions and device discovery |
| `Features` | Views, ViewModels, user actions, and presentation | Direct file-path, USB, or SQL access |
| `App` | Dependency injection, lifecycle, windows | Concrete parsing and conversion business logic |

Dependency direction: UI → Application → Domain. Concrete adapters implement Domain ports and are assembled by App.
Prefer pure functions for parsers and renderers to simplify testing.

Primary use cases:

- `ConnectDevice`, `RefreshDeviceLibrary`.
- `ImportClippings`, `ReparseSnapshot`, `UpdateClippingOverride`, `ExportMarkdown`.
- `PlanBookImport`, `ExecuteBookImport`, `BackupBook`, `PlanDeletion`, `ExecuteDeletion`.
- `ImportDictionary`, `LookupWord`, `UpdateDictionaryEntry`, `DownloadDictionary`, `InstallDeviceDictionary`.

## 10. Data and file storage

### 10.1 Core entities

| Entity | Key fields |
| --- | --- |
| `DeviceRecord` | Local ID, reliable device identity, model, protocol, last verified capabilities |
| `ImportSnapshot` | Source, file hash, storage path, encoding, import time, parser version |
| `Clipping` | UUID, fingerprint version, book ID, type, body, location, page, original timestamp |
| `ClippingSource` | Annotation ID, snapshot ID, record ordinal, raw-fragment locator, parsing diagnostics |
| `ClippingOverride` | Annotation ID, local corrections, tags, hidden state, version |
| `LibraryBook` | UUID, original description, user title and author, association status |
| `BookFile` | Book association, local or device reference, format, size, file identity |
| `DictionaryPackage` | Package ID, version, languages, source, license, status |
| `DictionaryEntry` / `Inflection` | Stable entry ID, headword, definition, inflection mappings |
| `EntryOverride` | Package ID, entry ID, operation, user content, upstream base version |
| `JobRecord` | Job ID, request ID, type, state, plan snapshot, stage, error |
| `ExportManifest` | Destination file, generated-content hash, book ID, export-configuration version |

Use versioned migrations, transactions, and foreign-key constraints. Manage write transactions through one controlled
write channel and use safe parameter binding for queries. Retain a recoverable copy before upgrades; a migration
failure must never replace user data with a newly created empty database.

### 10.2 Local directories

Obtain Application Support and Caches locations through system APIs; do not hardcode user directories.

```text
Application Support/Kindle Margin/
├── library.sqlite
├── snapshots/                 # Immutable My Clippings originals
├── dictionaries/              # Installed dictionary originals and version information
├── backups/                   # Device-book backups retained by the user
└── manifests/                 # Export and recovery manifests

Caches/Kindle Margin/
├── conversions/               # Rebuildable conversion artifacts
├── downloads/                 # Temporary downloads
└── jobs/                      # Job working directories
```

Obtain user export directories through a file picker. Snapshots, user edits, and backups are persistent data and must
not be deleted by "Clear cache." Cache cleanup skips files referenced by running jobs.

## 11. Jobs, cancellation, and recovery

Use one `JobCoordinator`. Job plans are immutable, and job state is the UI's sole authoritative source.

```text
queued → preparing → running → verifying → completed
                       ↓           ↓
                   cancelling → cancelled
                       ↓           ↓
                     failed / needsReconciliation
```

Job stages identify reading, parsing, conversion, upload, download, or deletion. Show percentages only for measurable
byte or record counts; otherwise show a stage indicator rather than fabricated progress.

Key rules:

1. Repeated clicks with the same request ID must not create duplicate write jobs. Enforce this through both database
   uniqueness constraints and the coordinator.
2. Before queued execution, recheck the device session, source-file identity, and destination conflicts. Replan stale
   plans.
3. After device disconnection or process failure, writes with unknown outcomes enter `needsReconciliation`; do not
   immediately retry uploads or deletion.
4. Rescan and compare logs, objects, sizes, and hashes where needed before deciding whether an operation completed,
   failed, or requires user action.
5. Cancellation waits for operations or child processes to stop before cleaning temporary objects known to belong to
   the job. Do not delete device files with uncertain ownership.
6. V1 does not require byte-level resumable transfer. Cancellation, recovery, and retry outcomes must be accurate and
   explainable.
7. App restart does not automatically replay device writes. Safe operations such as purely local parsing may resume
   from persisted plans.
8. When quitting with active jobs, offer waiting or cancellation. Cleanup must not terminate other applications'
   Calibre or USB processes.

## 12. Errors, security, and privacy

Map structured error codes to user-facing messages, for example: `deviceDisconnected`, `deviceBusy`,
`unsupportedDevice`, `permissionDenied`, `insufficientSpace`, `sourceChanged`, `unsupportedFormat`, `protectedContent`,
`converterUnavailable`, `verificationFailed`, `parsePartialFailure`, and `dictionaryConflict`.

Errors include the stage, affected object, recoverability, and suggested action. Separate diagnostics from user-facing
messages. By default, do not log book text, annotation text, private dictionary content, serial numbers, or complete
personal paths.

Treat devices and imported files as untrusted input: limit metadata, file, and record sizes; constrain ebook-container
extraction sizes and paths; use controlled arguments for external processes; and never execute book or dictionary
scripts in local previews. Centralize thresholds and explain limit violations rather than freezing the UI.

Do not write system directories or modify Kindle system databases. Deletion, replacement, and cleanup use verified
identity and job ownership, never broad recursive deletion rules.

No telemetry or background content synchronization by default. Dictionary downloads send only information needed to
retrieve catalogs and packages. Diagnostic export is user-initiated and provides a redacted preview.

## 13. Acceptance criteria

| ID | Scenario | Passing condition |
| --- | --- | --- |
| DEV-01 | Mounted-volume Kindle connected before launch | Automatically discovered; supported directories are readable |
| DEV-02 | Connect a standard MTP Kindle | Files can be listed, read, written, and verified; physical model and firmware are recorded in the compatibility table |
| DEV-03 | Scribe or an unknown device | Not mistaken for a supported writable device; status is clearly shown |
| DEV-04 | Disconnect, reconnect, or device busy | UI stays responsive; old references expire; no duplicate writes; connection can be retried |
| CLP-01 | Chinese and English highlight, note, and bookmark samples | Correct types, locations, pages, and original text; missing timestamps are not fabricated |
| CLP-02 | Repeated import of identical and incremental files | Existing records are not duplicated; identical text at different locations or times is not incorrectly merged |
| CLP-03 | Damaged or incomplete records | Other records continue importing; originals and diagnostics remain inspectable |
| CLP-04 | Re-import after local edits | User edits remain; original content can be inspected and restored |
| MD-01 | Export and re-export by book | Stable content, correct special characters, no accidental overwrite of user edits |
| MD-02 | Export failure or cancellation | Existing Markdown remains intact; temporary-file cleanup has an explicit outcome |
| BOOK-01 | Direct transfer of a supported file | Read-back hash matches after writing; device indexing is not claimed complete |
| BOOK-02 | EPUB to AZW3 | Plan shown first; local output passes structural validation; test book opens on the target physical device |
| BOOK-03 | Missing Calibre or conversion failure | Original unchanged; no incomplete artifact uploaded; other features remain usable |
| BOOK-04 | Naming conflict, insufficient space, or changed source | Block or replan before writing; no silent overwrite |
| BOOK-05 | Delete a book and associated files | Scope is explicit; backup is recoverable; unrelated files are not deleted |
| DICT-01 | JSON/CSV import and lookup | Validation errors identify the correct location; exact, inflection, and multiple-sense lookup work |
| DICT-02 | Update a dictionary after editing entries | Overrides survive; identity conflicts are explicit |
| DICT-03 | Download disconnection, cancellation, or hash failure | Failed package is not installed; old dictionary remains usable; download can be retried after connectivity returns |
| DICT-04 | Install a compatible device dictionary | File verification completes; selecting it as default on the physical device enables target-language lookup |
| JOB-01 | Repeated clicks and crash recovery | No duplicate writes; unknown outcomes are reconciled before further action |
| OFF-01 | Fully offline | Installed resources support annotations, export, lookup, and local conversion |
| UI-01 | Navigate between dashboard tabs | Left navigation reflects the active tab; center content and contextual tools match that tab; no stale actions remain |
| UI-02 | Page or selection has no contextual tools | Right panel, divider, and tools toggle are absent; the center reclaims the space |
| UI-03 | Collapse and reopen contextual tools | Primary workflows remain accessible; explicit collapse persists per page; removing the selected item clears its actions |
| UI-04 | Resize the window | Right tools collapse first and remain reachable when applicable; navigation can collapse; center controls do not overlap or clip |
| UI-05 | Keyboard, appearance, and page state | Keyboard focus is visible and recovers after panel removal; controls have accessible names; light and dark states remain legible; tab switches preserve valid page state and unsaved edits |
| UI-06 | Device changes while a job is queued | Global status updates without changing the queued job's target; unavailable write actions explain their state |

## 14. Testing strategy and performance targets

### 14.1 Automation

- Unit tests: multilingual parsing, deduplication, book association, Markdown escaping, inflection lookup, import
  planning, and migrations.
- Adapter contract tests: run the same read/write, disconnection, and failure cases against virtual disk directories
  and fake MTP object storage.
- Integration tests: temporary SQLite, mock download services, local Calibre, and synthetic unprotected ebooks.
- UI validation: cover UI-01 through UI-06, disconnected and busy devices, conversion choices, deletion scope,
  dictionary editing, job cancellation, and export conflicts. Include manual keyboard, resizing, and light/dark appearance review.
- Crash-recovery tests: interrupt key stages such as after conversion, after upload, and before/after deletion;
  reconcile persistent logs with actual files.

Tests do not access users' Kindles or real books by default. Enable physical-device write tests separately, use clearly
marked test directories and synthetic files, and clean up only content created by those tests.

### 14.2 V1 performance targets

These targets require measurement. Record the test machine, OS, and data scale; do not present them as achieved results:

- Keep all device I/O, parsing, conversion, and heavy database work off the main thread.
- Keep list scrolling and filtering interactive after importing 10,000 annotations.
- Target common exact lookups within 100 ms for an indexed dictionary with 100,000 entries.
- For large libraries, display the first batch of files before progressively filling metadata; do not wait to download
  the whole library.
- Default conversion concurrency to 1 and transfer concurrency to 1 per device; use a small download-concurrency limit.
- Stream large-file reads and writes instead of loading whole books or dictionaries into memory at once.

## 15. Implementation order and release gates

These are implementation phases within the same V1 scope. Later phases are not automatically deferred beyond V1.

### Phase A: Foundations and device validation

- Initialize the SwiftUI project, module boundaries, SQLite migrations, and job model.
- Validate mounted-volume and MTP reading/writing, cancellation, busy-device handling, and reconnection on standard Kindles.
- Confirm minimum OS, distribution architectures, USB dependency licenses, signing, and notarization approach.

### Phase B: Complete annotation workflow

- Manual My Clippings import, parsing, original snapshots, deduplication, and local corrections.
- Markdown preview, export, and conflict handling.
- Integrate automatic device reading using the same import use case.

### Phase C: Book management and conversion

- Device listing, backup, direct transfer, deletion planning, and outcome verification.
- Calibre detection, conversion planning, execution, cancellation, and artifact validation.
- Write logs, outcome reconciliation, retry deduplication, and recovery.

### Phase D: Dictionaries and release validation

- App dictionary import, indexing, lookup, editing, merged export, and update conflicts.
- Download catalog, validation, and installation; installation of existing Kindle dictionaries.
- Physical-device compatibility table, performance measurements, complete offline testing, signing, notarization, and
  installation validation.

Release gates: applicable section 13 acceptance criteria pass; at least one mounted-volume Kindle and one standard MTP
Kindle pass physical-device validation; downloaded dictionary sources and licenses are established; conversion
dependencies and unsupported scope are visible in both the interface and documentation.

## 16. Decisions still requiring confirmation

| Item | Current approach | Confirmation point |
| --- | --- | --- |
| Initial model and firmware list | No all-model commitment; first cover one standard Kindle for each protocol | Phase A |
| Minimum macOS and Intel support | macOS 14+ and Apple Silicon confirmed; Intel support uncommitted | Confirmed by user on 2026-10-22 |
| Exact libmtp version and linking approach | libmtp 1.1.22 pinned with dynamic linking; approach confirmed 2026-10-22. Validate licensing, signing, cancellation, and physical devices | Phase A validation pending |
| Download catalog and content licensing | Design a fixed HTTPS manifest; real release resources have not been selected | Before Phase D |
| Kindle dictionary test samples | Select existing dictionaries that are clearly distributable and suitable for testing | Before Phase D |
| Additional UI locales | Centralize copy from the start and use English as the default per `AGENTS.md`; confirm additional localized resources separately | Before localization work |

Unverified implementation assumptions cannot replace these decisions. Decisions affecting external compatibility,
download sources, or release commitments must update this document and the compatibility table.

## 17. Technical basis and references

These references explain protocol and format boundaries. Pin versions and revalidate during integration. Third-party
tool documentation does not establish support for every Kindle model.

1. [Amazon: Connect, Browse, and Transfer Files on E-Reader](https://digprjsurvey.amazon.com/csad/help/node/TCUBEdEkbIhK07ysFu) — Mac USB transfers and differences in newer devices.
2. [Calibre FAQ](https://manual.calibre-ebook.com/faq.html) — Device connections, MTP, and format guidance.
3. [Apple: Disk Arbitration](https://developer.apple.com/documentation/diskarbitration) — Disk discovery and removal events.
4. [libmtp](https://github.com/libmtp/libmtp) — Candidate MTP adapter implementation.
5. [Calibre: E-book conversion](https://manual.calibre-ebook.com/conversion.html) — Conversion capabilities and limits.
6. [Calibre: ebook-convert](https://manual.calibre-ebook.com/generated/en/ebook-convert.html) — Local command-line conversion interface.
7. [Apple: NLTagScheme.lemma](https://developer.apple.com/documentation/naturallanguage/nltagscheme/lemma) — Lemmatization support.
8. [Amazon: Creating Dictionaries](https://kdp.amazon.com/en_US/help/topic/G2HXJS944GL88DNV) — Kindle dictionary metadata, indexes, inflections, and physical-device testing requirements.

This is an independent project design. It does not inherit runtime, directory structure, media-processing, or build
requirements from a video-editor project.
