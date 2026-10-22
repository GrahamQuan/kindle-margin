import Foundation
import KindleDomain

public struct DictionaryParser: DictionaryParsing {
    public init() {}
    public func parseJSON(_ data: Data) throws -> DictionaryPackage {
        guard data.count <= Limits.importBytes else { throw MarginError.invalidInput("Dictionary exceeds the 64 MiB import limit.") }
        let package: DictionaryPackage
        do { package = try JSONDecoder().decode(DictionaryPackage.self, from: data) }
        catch let DecodingError.keyNotFound(key, context) { throw MarginError.invalidInput("Missing \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: ".")).") }
        catch let DecodingError.typeMismatch(_, context) { throw MarginError.invalidInput("Invalid field type at \(context.codingPath.map(\.stringValue).joined(separator: ".")).") }
        catch { throw MarginError.invalidInput("Invalid dictionary JSON: \(error.localizedDescription)") }
        try validate(package)
        return package
    }
    public func parseCSV(_ data: Data, name: String, source: String, target: String) throws -> DictionaryPackage {
        guard data.count <= Limits.importBytes, var text = String(data: data, encoding: .utf8) else { throw MarginError.invalidInput("CSV must be UTF-8 and at most 64 MiB.") }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let rows = try csvRows(text)
        guard let header = rows.first else { throw MarginError.invalidInput("CSV has no header row.") }
        let expected = ["headword", "definition", "partOfSpeech", "example", "forms"]
        guard Set(header).count == header.count, header.contains("headword"), header.contains("definition"), header.allSatisfy(expected.contains) else {
            throw MarginError.invalidInput("CSV header must contain headword and definition; optional columns are partOfSpeech, example, forms.")
        }
        var entries: [DictionaryEntry] = []
        for (index, row) in rows.dropFirst().enumerated() {
            if row.allSatisfy(\.isEmpty) { continue }
            guard row.count == header.count else { throw MarginError.invalidInput("CSV row \(index + 2) has \(row.count) fields; expected \(header.count).") }
            let fields = Dictionary(uniqueKeysWithValues: zip(header, row))
            guard !(fields["headword"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty, !(fields["definition"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { throw MarginError.invalidInput("CSV row \(index + 2): headword and definition are required.") }
            entries.append(.init(id: UUID().uuidString, headword: fields["headword"]!, definition: fields["definition"]!, partOfSpeech: fields["partOfSpeech"], example: fields["example"], forms: (fields["forms"] ?? "").split(separator: "|").map(String.init)))
        }
        let package = DictionaryPackage(id: UUID().uuidString, name: name, sourceLanguage: source, targetLanguage: target, license: "User-provided content", entries: entries)
        try validate(package)
        return package
    }
    private func validate(_ package: DictionaryPackage) throws {
        guard package.schemaVersion == 1 else { throw MarginError.invalidInput("Unsupported dictionary schemaVersion; expected 1.") }
        guard [package.id, package.version, package.name, package.sourceLanguage, package.targetLanguage, package.license].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw MarginError.invalidInput("Dictionary identity, version, name, languages, and license are required.") }
        var ids: Set<String> = []
        for (index, entry) in package.entries.enumerated() {
            try Task.checkCancellation()
            guard [entry.id, entry.headword, entry.definition].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), ids.insert(entry.id).inserted else { throw MarginError.invalidInput("Entry \(index + 1): id, headword, and definition must be nonempty; ids must be unique.") }
            guard entry.definition.count <= Limits.recordCharacters, entry.headword.count <= 1024, entry.id.count <= 256, entry.forms.count <= 1024, entry.forms.allSatisfy({ $0.count <= 1024 }), (entry.example?.count ?? 0) <= Limits.recordCharacters else { throw MarginError.invalidInput("Entry \(index + 1) exceeds the definition size limit.") }
        }
    }
    private func csvRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []; var row: [String] = []; var field = ""; var quoted = false; var closed = false
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n")); var index = 0
        while index < characters.count {
            if index % 1024 == 0 { try Task.checkCancellation() }
            let c = characters[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { row.append(field); field = ""; closed = false }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = ""; closed = false }
            else if c == "\"", field.isEmpty, !closed { quoted = true }
            else if c == "\"" || closed { throw MarginError.invalidInput("Malformed CSV quoting near row \(rows.count + 1).") }
            else { field.append(c) }
            index += 1
        }
        guard !quoted else { throw MarginError.invalidInput("Unclosed CSV quote near row \(rows.count + 1).") }
        if !field.isEmpty || !row.isEmpty || closed { row.append(field); rows.append(row) }
        return rows
    }
}
