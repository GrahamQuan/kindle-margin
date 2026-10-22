import Foundation
import KindleDomain

public enum SourceMetadata {
    public static func timestamp(_ text: String?) -> SourceTimestamp {
        guard let text, !text.isEmpty else { return .init(original: text, status: .missing) }
        // Parse wall-clock components only. UTC here is an internal formatter reference, never a claimed source zone.
        let formats = [("en_US_POSIX", "EEEE, MMMM d, yyyy h:mm:ss a"), ("en_US_POSIX", "EEEE, MMMM d, yyyy HH:mm:ss"), ("en_US_POSIX", "yyyy-MM-dd HH:mm:ss"), ("zh_CN", "yyyy年M月d日 HH:mm:ss"), ("zh_CN", "yyyy年M月d日EEEE ah:mm:ss")]
        for (locale, format) in formats {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: locale); formatter.dateFormat = format; formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
            if let date = formatter.date(from: text) {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return .init(original: text, status: .localDateTime, components: calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date))
            }
        }
        return .init(original: text, status: .unparsed)
    }
    public static func book(_ description: String) -> (title: String, author: String?) {
        guard description.last == ")", let start = description.lastIndex(of: "("), start > description.startIndex else { return (description, nil) }
        let title = String(description[..<start]).trimmingCharacters(in: .whitespaces)
        let author = String(description[description.index(after: start)..<description.index(before: description.endIndex)])
        // Nested parentheses and ambiguous multi-segment descriptions retain the complete original description.
        guard !title.contains("("), !title.contains(")"), !author.isEmpty, !author.contains("(") else { return (description, nil) }
        return (title, author)
    }
}
