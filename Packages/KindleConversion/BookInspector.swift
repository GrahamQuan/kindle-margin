import Foundation
import PDFKit
import CZlib
import KindleDomain

public struct BookInspection: Sendable {
    public let format: String
    public let protected: Bool
    public let dictionaryLanguages: (UInt32, UInt32)?
    public let dictionaryIdentity: UInt32?
}
/// Bounded structural inspection. Unknown compound formats fail closed; no ebook scripts execute.
public struct BookInspector: Sendable {
    public init() {}
    public func inspect(_ url: URL) throws -> BookInspection {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let size = try handle.seekToEnd(); try handle.seek(toOffset: 0)
        guard size > 0, size <= 2 * 1024 * 1024 * 1024 else { throw MarginError.invalidInput("Book must be nonempty and at most 2 GiB.") }
        let header = try handle.read(upToCount: 1024 * 1024) ?? Data()
        if header.starts(with: [0x50,0x4b,3,4]) {
            let archive = try CheckedZIP(url: url)
            if archive.entries["mimetype"] != nil {
                guard String(data: try archive.read("mimetype"), encoding: .utf8) == "application/epub+zip" else { throw MarginError.invalidInput("ZIP is not an EPUB container.") }
                let container = try archive.read("META-INF/container.xml")
                let root = try XMLFields.read(container, attribute: "full-path", element: "rootfile").first
                guard let root, archive.entries[root] != nil else { throw MarginError.invalidInput("EPUB package document is missing.") }
                _ = try XMLFields.read(archive.read(root), attribute: "href", element: "item")
                return .init(format: "epub", protected: archive.entries["META-INF/encryption.xml"] != nil || archive.entries["META-INF/rights.xml"] != nil, dictionaryLanguages: nil, dictionaryIdentity: nil)
            }
            guard archive.entries["[Content_Types].xml"] != nil, archive.entries["word/document.xml"] != nil else { throw MarginError.invalidInput("Unknown ZIP ebook container.") }
            _ = try XMLFields.read(archive.read("[Content_Types].xml"), attribute: "ContentType", element: "Override")
            _ = try XMLFields.read(archive.read("word/document.xml"), attribute: "", element: "")
            return .init(format: "docx", protected: false, dictionaryLanguages: nil, dictionaryIdentity: nil)
        }
        if header.count >= 86, String(data: header[60..<68], encoding: .ascii) == "BOOKMOBI" {
            let count = try header.number(76, 2, big: true); let offset = try header.number(78, 4, big: true)
            guard count > 0, 78 + count * 8 <= header.count, offset >= 78 + count * 8, offset + 112 <= header.count,
                  String(data: header[(offset + 16)..<(offset + 20)], encoding: .ascii) == "MOBI" else { throw MarginError.invalidInput("Damaged MOBI container.") }
            let headerLength = try header.number(offset + 20,4,big:true)
            guard headerLength >= 96, offset + 16 + headerLength <= header.count else { throw MarginError.invalidInput("Invalid MOBI header length.") }
            var previous = offset
            for index in 0..<count { let next = try header.number(78 + index * 8,4,big:true); guard next >= previous, next < size else { throw MarginError.invalidInput("Invalid MOBI record offsets.") }; previous = next }
            let encrypted = try header.number(offset + 12,2,big:true) != 0
            let version = try header.number(offset + 104,4,big:true)
            let input = try header.number(offset + 96,4,big:true); let output = try header.number(offset + 100,4,big:true)
            let orthography = try header.number(offset + 40,4,big:true)
            var dictionary = input != 0 && output != 0 && input != Int(UInt32.max) && output != Int(UInt32.max) && orthography > 0 && orthography < count
            if dictionary {
                let indexOffset = try header.number(78 + orthography * 8,4,big:true)
                try handle.seek(toOffset: UInt64(indexOffset))
                dictionary = try handle.read(upToCount: 4) == Data("INDX".utf8)
            }
            return .init(format: version >= 8 ? "azw3" : "mobi", protected: encrypted, dictionaryLanguages: dictionary ? (UInt32(input),UInt32(output)) : nil, dictionaryIdentity: dictionary ? UInt32(try header.number(offset + 32,4,big:true)) : nil)
        }
        if header.starts(with: Data("%PDF-".utf8)) {
            try handle.seek(toOffset: size > 4096 ? size - 4096 : 0)
            let tail = try handle.readToEnd() ?? Data()
            guard tail.range(of: Data("%%EOF".utf8)) != nil else { throw MarginError.invalidInput("PDF end marker is missing.") }
            try handle.seek(toOffset: 0); var protected = false; var carry = Data()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                let bytes = carry + chunk; if bytes.range(of: Data("/Encrypt".utf8)) != nil { protected = true }; carry = Data(bytes.suffix(16))
            }
            if !protected {
                guard let document = PDFDocument(url: url), document.pageCount > 0 else { throw MarginError.invalidInput("PDF structure is unreadable.") }
                protected = document.isEncrypted || document.isLocked
            }
            return .init(format: "pdf", protected: protected, dictionaryLanguages: nil, dictionaryIdentity: nil)
        }
        guard size <= Limits.importBytes else { throw MarginError.invalidInput("Unrecognized large-file format.") }
        try handle.seek(toOffset: 0)
        let data = try handle.readToEnd() ?? Data()
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0"), !text.unicodeScalars.contains(where: { $0.value < 9 || (14...31).contains($0.value) }) else { throw MarginError.invalidInput("Unrecognized, protected, or binary input format.") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let format = trimmed.hasPrefix("{\\rtf") ? "rtf" : trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html") ? "html" : "txt"
        if format == "html", text.range(of: "(?:src|href)\\s*=\\s*[\"'](?:https?:|file:|//)", options: [.regularExpression,.caseInsensitive]) != nil { throw MarginError.invalidInput("HTML references external resources. Save a self-contained local book before conversion.") }
        return .init(format: format, protected: false, dictionaryLanguages: nil, dictionaryIdentity: nil)
    }
}
private extension Data {
    func number(_ offset: Int, _ length: Int, big: Bool = false) throws -> Int {
        guard offset >= 0, offset + length <= count else { throw MarginError.invalidInput("Truncated container metadata.") }
        let indexes = big ? Array(offset..<(offset + length)) : Array((offset..<(offset + length)).reversed())
        return indexes.reduce(0) { ($0 << 8) | Int(self[$1]) }
    }
}
private final class CheckedZIP {
    struct Entry { let offset: Int; let compressed: Int; let size: Int; let method: Int; let crc: Int }
    let file: FileHandle
    var entries: [String: Entry] = [:]
    init(url: URL) throws {
        file = try FileHandle(forReadingFrom: url)
        let size = try file.seekToEnd(); let tailStart = size > 65557 ? size - 65557 : 0
        try file.seek(toOffset: tailStart); let tail = try file.readToEnd() ?? Data()
        guard let range = tail.range(of: Data([0x50,0x4b,5,6]), options: .backwards), range.lowerBound + 22 <= tail.count else { throw MarginError.invalidInput("ZIP central directory is missing.") }
        let end = range.lowerBound
        let count = try tail.number(end + 10,2); let length = try tail.number(end + 12,4); let offset = try tail.number(end + 16,4)
        guard count <= 10_000, length <= 8 * 1024 * 1024, offset + length <= size, try tail.number(end + 4,2) == 0, try tail.number(end + 6,2) == 0 else { throw MarginError.invalidInput("Split, oversized, or ZIP64 containers are not supported.") }
        try file.seek(toOffset: UInt64(offset)); let directory = try file.read(upToCount: length) ?? Data()
        var cursor = 0; var total = 0
        for _ in 0..<count {
            guard try directory.number(cursor,4) == 0x02014b50 else { throw MarginError.invalidInput("Invalid ZIP directory record.") }
            let flags = try directory.number(cursor + 8,2); let method = try directory.number(cursor + 10,2)
            let compressed = try directory.number(cursor + 20,4); let expanded = try directory.number(cursor + 24,4)
            let nameLength = try directory.number(cursor + 28,2); let extra = try directory.number(cursor + 30,2); let comment = try directory.number(cursor + 32,2)
            let attributes = try directory.number(cursor + 38,4); let localOffset = try directory.number(cursor + 42,4)
            guard cursor + 46 + nameLength + extra + comment <= directory.count, let name = String(data: directory[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8), !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.split(separator: "/").contains(".."), !name.contains("\0"), entries[name] == nil else { throw MarginError.invalidInput("Unsafe or duplicate ZIP member name.") }
            total += expanded
            guard flags & 1 == 0, [0,8].contains(method), (attributes >> 16) & 0xF000 != 0xA000, total <= 512 * 1024 * 1024, localOffset + compressed < offset else { throw MarginError.invalidInput("Encrypted, unsafe, or oversized ZIP member.") }
            try file.seek(toOffset: UInt64(localOffset))
            let local = try file.read(upToCount: 30) ?? Data()
            guard try local.number(0,4) == 0x04034b50, try local.number(6,2) == flags, try local.number(8,2) == method else { throw MarginError.invalidInput("ZIP member headers disagree.") }
            let localNameLength = try local.number(26,2); let localExtra = try local.number(28,2)
            guard localOffset + 30 + localNameLength + localExtra + compressed <= offset,
                  let localName = try file.read(upToCount: localNameLength), String(data: localName, encoding: .utf8) == name else { throw MarginError.invalidInput("ZIP member path or bounds disagree.") }
            entries[name] = .init(offset: localOffset, compressed: compressed, size: expanded, method: method, crc: try directory.number(cursor + 16,4))
            cursor += 46 + nameLength + extra + comment
        }
    }
    deinit { try? file.close() }
    func read(_ name: String) throws -> Data {
        guard let entry = entries[name], entry.size <= 8 * 1024 * 1024, entry.compressed <= 8 * 1024 * 1024 else { throw MarginError.invalidInput("Missing or oversized ebook metadata.") }
        try file.seek(toOffset: UInt64(entry.offset)); let header = try file.read(upToCount: 30) ?? Data()
        guard try header.number(0,4) == 0x04034b50, try header.number(8,2) == entry.method else { throw MarginError.invalidInput("ZIP local header disagrees with directory.") }
        let nameLength = try header.number(26,2); let extra = try header.number(28,2)
        guard let localName = try file.read(upToCount: nameLength), String(data: localName, encoding: .utf8) == name else { throw MarginError.invalidInput("ZIP local name disagrees with directory.") }
        try file.seek(toOffset: UInt64(entry.offset + 30 + nameLength + extra)); let compressed = try file.read(upToCount: entry.compressed) ?? Data()
        var output = Data(count: entry.size)
        if entry.method == 0 { output = compressed }
        else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw MarginError.invalidInput("Cannot initialize ebook decompression.") }
            defer { inflateEnd(&stream) }
            let result = compressed.withUnsafeBytes { input in output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(compressed.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(entry.size)
                return inflate(&stream, Z_FINISH)
            } }
            guard result == Z_STREAM_END, stream.total_out == entry.size else { throw MarginError.invalidInput("Invalid or oversized deflated ebook member.") }
        }
        let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
        guard output.count == entry.size, checksum == entry.crc else { throw MarginError.verificationFailed }
        return output
    }
}
private final class XMLFields: NSObject, XMLParserDelegate {
    let attribute: String; let element: String; var values: [String] = []
    init(attribute: String, element: String) { self.attribute = attribute; self.element = element }
    static func read(_ data: Data, attribute: String, element: String) throws -> [String] {
        let decoded = data.starts(with: [0xff,0xfe]) || data.starts(with: [0xfe,0xff]) ? String(data: data, encoding: .utf16) : String(data: data, encoding: .utf8)
        guard let decoded, decoded.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else { throw MarginError.invalidInput("External XML declarations are not accepted in ebook metadata.") }
        let delegate = XMLFields(attribute: attribute, element: element); let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse() else { throw MarginError.invalidInput("Invalid ebook XML metadata.") }; return delegate.values
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) { if elementName == element, let value = attributes[attribute] { values.append(value) } }
}
