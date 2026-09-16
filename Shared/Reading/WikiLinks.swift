import Foundation

/// A page that links to the current page with `[[…]]`.
nonisolated struct Backlink: Identifiable, Sendable, Equatable {
    let url: URL
    let title: String
    /// The line the link is on.
    let snippet: String

    var id: URL { url }
}

nonisolated enum WikiLinks {
    /// Reading mode turns `[[Page]]` into a link with this scheme, which Blad handles itself.
    static let urlScheme = "blad-page"

    /// `[[Page]]` or `[[Page|shown text]]`: group 1 is the page, group 2 the optional text.
    static let pattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n|]+)(?:\|([^\[\]\n]+))?\]\]"#)

    /// Rewrites `[[Page]]` as a markdown link, so reading mode can render and open it.
    static func markdownLinks(in text: String) -> String {
        guard text.contains("[[") else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let page = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let shown = match.range(at: 2).location == NSNotFound ? page : source.substring(with: match.range(at: 2))
            let encoded = page.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? page
            result += "[\(shown)](\(urlScheme):\(encoded))"
            last = NSMaxRange(match.range)
        }
        return result + source.substring(from: last)
    }

    static func backlinks(to title: String, excluding url: URL, in entries: [SearchEntry]) -> [Backlink] {
        entries.compactMap { entry in
            guard entry.url != url else { return nil }
            let text = entry.text as NSString
            for match in pattern.matches(in: entry.text, range: NSRange(location: 0, length: text.length)) {
                let target = (text.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
                guard target.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { continue }
                let line = text.substring(with: text.lineRange(for: match.range)).trimmingCharacters(in: .whitespacesAndNewlines)
                return Backlink(url: entry.url, title: entry.title, snippet: line)
            }
            return nil
        }
    }
}
