import Foundation

/// `#tag` in a page. Tags gather pages across spaces: clicking one searches for it.
nonisolated enum Tags {
    /// Reading mode turns `#tag` into a link with this scheme, which Blad handles itself.
    static let urlScheme = "blad-tag"

    /// `#tag` after a space or at the start of a line. Group 2 is the name.
    /// A heading is `#` followed by a space, so it never matches here.
    static let pattern = try! NSRegularExpression(pattern: #"(^|[\s(\[{>])#(\p{L}[\p{L}\p{N}_/-]*)"#)

    private static let codeSpan = try! NSRegularExpression(pattern: #"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)

    /// The tag names in a page, in the order they appear, without the `#`.
    static func names(in text: String) -> [String] {
        let source = text as NSString
        let all = NSRange(location: 0, length: source.length)
        return pattern.matches(in: text, range: all).map { source.substring(with: $0.range(at: 2)) }
    }

    /// Rewrites `#tag` as a markdown link, so reading mode can render and open it.
    static func markdownLinks(in text: String) -> String {
        guard text.contains("#") else { return text }
        let source = text as NSString
        let all = NSRange(location: 0, length: source.length)
        let code = codeSpan.matches(in: text, range: all).map(\.range)

        var result = ""
        var last = 0
        for match in pattern.matches(in: text, range: all) {
            let range = match.range(at: 2)
            guard !code.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }
            let name = source.substring(with: range)
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            result += source.substring(with: match.range(at: 1))
            result += "[#\(name)](\(urlScheme):\(encoded))"
            last = NSMaxRange(match.range)
        }
        return result + source.substring(from: last)
    }

    /// The tag a `blad-tag:` link points at.
    static func name(from url: URL) -> String? {
        guard url.scheme == urlScheme else { return nil }
        let name = String(url.absoluteString.dropFirst(urlScheme.count + 1))
        return name.removingPercentEncoding ?? name
    }
}
