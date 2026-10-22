import Foundation
import CryptoKit
import KindleDomain

public struct SnapshotParser: ClippingsParser {
    public init() {}
    public func parse(_ data: Data) throws -> ParsedSnapshot {
        guard data.count <= Limits.importBytes else { throw MarginError.invalidInput("Clippings file exceeds the 64 MiB import limit.") }
        let encoding: String.Encoding
        let label: String
        if data.starts(with: [0xFF, 0xFE]) { encoding = .utf16LittleEndian; label = "UTF-16LE" }
        else if data.starts(with: [0xFE, 0xFF]) { encoding = .utf16BigEndian; label = "UTF-16BE" }
        else { encoding = .utf8; label = "UTF-8" }
        guard var text = String(data: data, encoding: encoding), !text.contains("\u{0}") else {
            throw MarginError.invalidInput("Encoding is uncertain. Select a UTF-8 or BOM-marked UTF-16 copy; no data was imported.")
        }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var records: [Clipping] = []; var diagnostics: [ParseDiagnostic] = []; var lines: [String] = []; var ordinal = 0
        func consume(complete: Bool) {
            let raw = lines.joined(separator: "\n"); lines.removeAll(keepingCapacity: true)
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            ordinal += 1
            guard complete else { diagnostics.append(.init(ordinal: ordinal, reason: "Incomplete final record", raw: raw)); return }
            guard raw.count <= Limits.recordCharacters else { diagnostics.append(.init(ordinal: ordinal, reason: "Record exceeds size limit", raw: raw)); return }
            var parts = raw.components(separatedBy: "\n")
            while parts.first?.isEmpty == true { parts.removeFirst() }
            guard parts.count >= 2, !parts[0].isEmpty, parts[1].hasPrefix("-") else {
                diagnostics.append(.init(ordinal: ordinal, reason: "Missing book description or metadata", raw: raw)); return
            }
            let metadata = parts[1]
            let kind: ClippingKind?
            if metadata.localizedCaseInsensitiveContains("highlight") || metadata.contains("标注") || metadata.contains("畫線") { kind = .highlight }
            else if metadata.localizedCaseInsensitiveContains("note") || metadata.contains("笔记") || metadata.contains("筆記") { kind = .note }
            else if metadata.localizedCaseInsensitiveContains("bookmark") || metadata.contains("书签") || metadata.contains("書籤") { kind = .bookmark }
            else { kind = nil }
            guard let kind else { diagnostics.append(.init(ordinal: ordinal, reason: "Unsupported metadata language or type", raw: raw)); return }
            func capture(_ pattern: String) -> String? {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)), let range = Range(match.range(at: 1), in: metadata) else { return nil }
                return String(metadata[range]).trimmingCharacters(in: .whitespaces)
            }
            let location = capture("(?:Location|Loc\\.|位置|位置：)\\s*([0-9]+(?:[-–][0-9]+)?)") ?? capture("第\\s*([0-9]+(?:[-–][0-9]+)?)\\s*段")
            let page = capture("page\\s*([0-9]+(?:[-–][0-9]+)?)") ?? capture("第\\s*([0-9]+(?:[-–][0-9]+)?)\\s*[页頁]")
            let timestamp = capture("(?:Added on|添加于|添加於|已添加至)\\s*(.+)$")
            var bodyParts = Array(parts.dropFirst(2))
            if bodyParts.first == "" { bodyParts.removeFirst() }
            while bodyParts.last == "" { bodyParts.removeLast() }
            let body = bodyParts.joined(separator: "\n")
            guard kind == .bookmark || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                diagnostics.append(.init(ordinal: ordinal, reason: "Missing annotation body", raw: raw)); return
            }
            let components = [parts[0], kind.rawValue, location ?? "", page ?? "", timestamp ?? "", body].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let canonical = (try? JSONEncoder().encode(components)) ?? Data()
            let fingerprint = "v1:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
            var record = Clipping(description: parts[0], kind: kind, body: body, location: location, page: page, timestamp: timestamp, ordinal: ordinal, fingerprint: fingerprint, reliableIdentity: (location != nil || page != nil) && timestamp != nil)
            record.sourceTimestamp = SourceMetadata.timestamp(timestamp)
            records.append(record)
        }
        for line in text.components(separatedBy: "\n") {
            if line == "==========" { consume(complete: true) } else { lines.append(line) }
        }
        consume(complete: false)
        return .init(hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), encoding: label, parserVersion: 2, clippings: records, diagnostics: diagnostics)
    }
}

public struct StandardMarkdownRenderer: MarkdownRenderer {
    public init() {}
    public func render(_ items: [AnnotationItem], includeHidden: Bool = false, includeTags: Bool = true, book: BookMetadata? = nil) -> String {
        let visible = items.filter { includeHidden || !$0.override.hidden }.sorted {
            let left = Int($0.original.location?.components(separatedBy: CharacterSet(charactersIn: "-–")).first ?? "")
            let right = Int($1.original.location?.components(separatedBy: CharacterSet(charactersIn: "-–")).first ?? "")
            if left != right { return (left ?? Int.max) < (right ?? Int.max) }
            return $0.original.ordinal < $1.original.ordinal
        }
        guard let first = items.first else { return "" }
        let metadata = book.map { (title: $0.title, author: $0.author) } ?? SourceMetadata.book(first.original.description)
        var output = "# \(escape(metadata.title))\n"
        if let author = metadata.author { output += "\nAuthor: \(escape(author))\n" }
        for kind in ClippingKind.allCases {
            let group = visible.filter { $0.original.kind == kind }
            guard !group.isEmpty else { continue }
            output += "\n## \(kind == .highlight ? "Highlights" : kind == .note ? "Notes" : "Bookmarks")\n"
            for item in group {
                output += "\n"
                if !item.body.isEmpty {
                    output += item.body.components(separatedBy: "\n").map { (kind == .highlight ? "> " : "") + escape($0) }.joined(separator: "\n") + "\n\n"
                }
                if let location = item.original.location { output += "- Location: \(escape(location))\n" }
                if let page = item.original.page { output += "- Page: \(escape(page))\n" }
                if let time = item.original.timestamp { output += "- Annotation time: \(escape(time)) (original source time; timezone not inferred)\n" }
                if includeTags && !item.override.tags.isEmpty { output += "- Tags: \(item.override.tags.map(escape).joined(separator: ", "))\n" }
            }
        }
        return output
    }
    private func escape(_ value: String) -> String {
        var output = ""
        for c in value {
            if "\\`*_{}[]()#+-.!>|".contains(c) { output.append("\\") }
            if c == "<" { output += "&lt;" } else if c == "&" { output += "&amp;" } else { output.append(c) }
        }
        return output
    }
}
