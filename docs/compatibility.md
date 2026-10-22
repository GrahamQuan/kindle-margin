# Compatibility evidence

## Platform

macOS 14+ and Apple Silicon are the initial supported development baseline, confirmed 2026-10-22.
Intel support is uncommitted. Local checks used arm64, Apple Swift 5.10, and macOS 14.8.4 (23J319).

## Physical devices

| Model | Firmware | Protocol | Operations verified | Status |
| --- | --- | --- | --- | --- |
| Not yet selected | Not recorded | Mounted volume | None | Physical acceptance pending |
| Not yet selected | Not recorded | MTP | None | Physical acceptance pending |

The local USB inventory check did not report a Kindle/Amazon/Scribe candidate. No user device was opened or written.
A volume name or Amazon USB vendor ID alone does not establish a supported writable Kindle. Scribe remains excluded.
The application exposes write workflows but disables them without a verified writable model profile. The bundled
profile list is empty; this must remain so until physical evidence is recorded.

## Local adapter evidence

Virtual temporary directories cover mounted-file upload/read-back, name conflicts, unsafe path rejection, stale
references, explicit deletion scope, changed-file rejection, and recoverable backups. These tests use synthetic data
and are not physical-device evidence. libmtp 1.1.22 compiled and linked against local libusb 1.0.29; MTP protocol calls
have not been validated against a physical Kindle. Fake MTP object-store tests cover transfer, verification failure,
disconnection, deletion with backup, partial deletion, and restart reconciliation without replay. These tests validate
application behavior; they do not emulate or certify the libmtp USB protocol.

Synthetic TXT and EPUB converted with local Calibre and passed AZW3 container checks. Opening, indexing, layout, and
dictionary lookup on a Kindle remain unverified. Do not infer those outcomes from a successful conversion or copy.
