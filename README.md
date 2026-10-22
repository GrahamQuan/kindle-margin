# Kindle Margin

Native macOS 14+ Kindle companion for Apple Silicon. Intel support is uncommitted.

**V1 workflows are implemented locally; acceptance validation remains open.** Physical-device and release checks,
and interactive UI checks blocked by the current automation connection, remain explicit. The full contract remains
[the V1 design](sepcs/kindle-margin-design.md). See [acceptance status](docs/acceptance.md) for implemented paths,
unverified behavior, and remaining work.

The development application supports manual and device My Clippings import, annotation corrections and hiding, original-content
inspection, Markdown preview and conflict-preserving export, JSON/CSV dictionary import, offline lookup, entry edits,
priority ordering, merged dictionary export, task history, and explicitly selected local Calibre conversion.

Disk Arbitration/USB discovery, the device browser, confirmed transfer and associated-file deletion plans, verified
backups, and durable rescan reconciliation are integrated. Device writes require an exact verified model/firmware
profile. The bundled profile list is deliberately empty until physical acceptance supplies that evidence.
No Amazon login, telemetry, or background synchronization is configured. Dictionary download infrastructure exists;
no public catalog is configured, and the application does not download dictionaries automatically.

## Build and validate

The project uses Swift Package Manager with Swift 5.10 and macOS 14 APIs. Full Xcode is not required to build the
executable. The acceptance executable runs with Command Line Tools and includes an opt-in native AppKit/SwiftUI
validation harness; it does not require XCTest.

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build
swift run KindleMarginChecks
swift run KindleMargin
```

Tests create and remove isolated temporary directories. They do not access real Kindles or user books. Optional
Calibre checks require an explicit trusted executable path; they generate synthetic text and check the resulting AZW3
container. Set `KINDLE_MARGIN_TEST_EPUB` to a synthetic EPUB to also exercise EPUB conversion.

```sh
KINDLE_MARGIN_TEST_CONVERTER=/Applications/calibre.app/Contents/MacOS/ebook-convert swift run KindleMarginChecks
KINDLE_MARGIN_PERFORMANCE=1 swift run KindleMarginChecks
KINDLE_MARGIN_UI_CHECKS=1 swift run KindleMarginChecks
```

To exercise the pinned MTP build, install libusb separately, then build libmtp **into a local development prefix**:

```sh
export KINDLE_MARGIN_MTP_PREFIX="$PWD/.build/dependencies/libmtp"
export KINDLE_MARGIN_LIBUSB_PREFIX=/opt/homebrew/opt/libusb
Scripts/build-libmtp.sh
swift build
```

The build script verifies the libmtp 1.1.22 archive SHA-256 and uses dynamic linking. It does not install system-wide.
The local build was checked against libusb 1.0.29. See [dependency notes](docs/dependencies.md). Without the prefix,
local workflows build without the optional native MTP adapter.

A development `.app` wrapper can be created with `Scripts/package-development.sh`, setting `KINDLE_MARGIN_BINARY`
to the built executable and `KINDLE_MARGIN_APP_OUTPUT` to a new absolute `.app` destination. This does not produce a
signed/notarized release or embed dynamic dependencies. For isolated UI testing, launch the executable with
`--temporary-library /absolute/temporary/directory`.

Persistent data normally lives in the system Application Support directory under `Kindle Margin`. Conversion artifacts
live in the system Caches directory. Snapshots and dictionary originals are preserved separately from local overrides.
No migration replaces an unreadable or unrecognized database with an empty one.

## Local workflows and release configuration

Snapshots can be inspected and reparsed without discarding corrections. Annotation tools support tags, regrouping,
explicit title/author metadata, and selected-word lookup. Dictionary tools support FTS, local additions, conflict
resolution, recoverable removal, and original-entry inspection. Settings retain export choices, panel preferences,
and the explicitly validated converter identity; cache cleanup excludes originals and backups. Diagnostics are
redacted and previewed before export. Re-export retains a previous-file recovery copy as well as detecting conflicts.

`App/Resources/device-profiles.json` accepts exact `model`, `firmware`, `transport`, and `verifiedFormats` records only
after physical validation. `App/Resources/catalog.json` accepts licensed product-controlled packages described by
`CatalogPackage`. Both are empty release gates, not example claims of hardware or content compatibility.

Native screenshots from the optional validation harness default to `/tmp/kindle-margin-ui-evidence`; set
`KINDLE_MARGIN_UI_OUTPUT` to choose another directory. The harness closes its window before exit. It creates synthetic
annotations and fake device objects; it never enables writes to an attached physical Kindle.
