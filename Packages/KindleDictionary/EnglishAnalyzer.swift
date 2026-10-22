import NaturalLanguage
import KindleDomain

public struct EnglishAnalyzer: WordAnalyzing {
    public init() {}
    public func candidates(for word: String) -> [String] {
        guard word.count <= 256 else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma]); tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        var candidates: [String] = []
        tagger.enumerateTags(in: word.startIndex..<word.endIndex, unit: .word, scheme: .lemma, options: [.omitPunctuation, .omitWhitespace]) { tag, _ in
            if let lemma = tag?.rawValue, lemma != word, !candidates.contains(lemma) { candidates.append(lemma) }; return true
        }
        return candidates
    }
}
