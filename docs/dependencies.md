# Native dependencies and distribution gates

- Platform: macOS 14+, Apple Silicon, confirmed by the user on 2026-10-22. Intel support is uncommitted.
- Swift: validated locally with Apple Swift 5.10 from Command Line Tools.
- SQLite: system SQLite via a small C module map; no downloaded SQLite binary.
- libmtp: **1.1.22**, dynamic linking, approach confirmed by the user on 2026-10-22.
  Source: <https://downloads.sourceforge.net/project/libmtp/libmtp/1.1.22/libmtp-1.1.22.tar.gz>.
  SHA-256: `c3fcf411aea9cb9643590cbc9df99fa5fe30adcac695024442973d76fa5f87bc`.
  Upstream project and license: <https://github.com/libmtp/libmtp> (LGPL-2.1).
  The source archive's `COPYING` is copied by the build script into the install prefix.
- libusb: local development build used the pre-existing Homebrew **1.0.29** dynamic library. The setup script requires
  an explicit prefix. Redistribution must pin and build this dependency as well; Homebrew paths are not release paths.
- Calibre: a user-selected local `ebook-convert`; never bundled or discovered through PATH. Selection invokes
  `--version` and per-format help probes, records architecture via the system `file` utility, and freezes capabilities,
  version, source content, and executable hash in conversion plans. Command-line reference:
  <https://manual.calibre-ebook.com/generated/en/ebook-convert.html>.

The pinned libmtp source built and linked locally. This establishes neither physical Kindle compatibility nor release
readiness. The adapter serializes C calls on a dedicated queue and uses callback cancellation for transfers. MTP writes
are disabled unless the composing application supplies a verified writable capability; the current app supplies none.

Before distribution: establish license obligations and source availability, embed architecture-compatible dylibs using
bundle-relative paths, validate USB access, complete signing and notarization, and verify installation on a clean Mac.
The development wrapper is not a distribution artifact. No signing, notarization, publishing, or device writes were
performed by the implementation checks.

System zlib performs bounded ZIP metadata decompression; PDFKit validates unencrypted PDF structure. Neither is a
bundled third-party binary. Container field references used during implementation include Calibre's
[reader header definitions](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/ebooks/mobi/reader/headers.py)
and the [PKWARE ZIP format specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).

Dictionary language and index fields were cross-checked against the [libmobi header reference](https://www.fabiszewski.net/libmobi/structMOBIMobiHeader.html). Synthetic header tests establish inspection behavior, not compatibility of a usable dictionary.
