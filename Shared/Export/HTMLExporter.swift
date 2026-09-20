import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turns a page into one standalone HTML file that looks like reading mode.
enum HTMLExporter {
    static func html(for blocks: [MarkdownBlock], title: String, theme: Theme, fontID: String, fontSize: CGFloat, baseURL: URL?) -> String {
        let body = blocks.map { block($0, baseURL: baseURL) }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="nl">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Blad">
        <title>\(escape(title))</title>
        <style>
        \(stylesheet(theme: theme, fontID: fontID, fontSize: fontSize))
        </style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>

        """
    }

    // MARK: - Blocks

    private static func block(_ block: MarkdownBlock, baseURL: URL?) -> String {
        switch block {
        case .heading(let level, let text):
            return "<h\(level)>\(inline(text, baseURL: baseURL))</h\(level)>"
        case .paragraph(let text):
            return "<p>\(inline(text, baseURL: baseURL))</p>"
        case .list(let items):
            let rows = items.map { item -> String in
                var classes = "item"
                let marker: String
                switch item.marker {
                case .bullet:
                    marker = "•"
                case .number(let number):
                    marker = escape(number)
                case .task(let done):
                    marker = done ? "☑" : "☐"
                    if done { classes += " done" }
                }
                return "<div class=\"\(classes)\" style=\"--depth: \(item.depth)\"><span class=\"marker\">\(marker)</span><span class=\"text\">\(inline(item.text, baseURL: baseURL))</span></div>"
            }
            return "<div class=\"list\">\n\(rows.joined(separator: "\n"))\n</div>"
        case .quote(let text):
            return "<blockquote>\(inline(text, baseURL: baseURL))</blockquote>"
        case .code(let language, let code):
            let label = language.isEmpty ? "" : "<span class=\"language\">\(escape(language.lowercased()))</span>"
            return "<pre>\(label)<code>\(highlighted(code, language: language))</code></pre>"
        case .table(let header, let rows):
            let head = header.map { "<th>\(inline($0, baseURL: baseURL))</th>" }.joined()
            let body = rows.map { row in
                "<tr>" + row.map { "<td>\(inline($0, baseURL: baseURL))</td>" }.joined() + "</tr>"
            }.joined(separator: "\n")
            return "<table>\n<thead><tr>\(head)</tr></thead>\n<tbody>\n\(body)\n</tbody>\n</table>"
        case .image(let alt, let source):
            return "<p><img src=\"\(imageSource(source, baseURL: baseURL))\" alt=\"\(escape(alt))\"></p>"
        case .rule:
            return "<hr>"
        }
    }

    // MARK: - Inline

    static func inline(_ markdown: String, baseURL: URL?) -> String {
        // Code spans first, so nothing inside them is treated as markdown.
        var codeSpans: [String] = []
        var text = replacing(inlineCode, in: markdown) { groups in
            codeSpans.append("<code>\(escape(groups[2]))</code>")
            return "\u{1}\(codeSpans.count - 1)\u{1}"
        }
        text = escape(text)
        text = replacing(image, in: text) { "<img src=\"\(imageSource(unescape($0[2]), baseURL: baseURL))\" alt=\"\($0[1])\">" }
        text = replacing(WikiLinks.pattern, in: text) { groups in
            let page = groups[1].trimmingCharacters(in: .whitespaces)
            let href = (page + ".md").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page
            return "<a class=\"page-link\" href=\"\(href)\">\(groups[2].isEmpty ? page : groups[2])</a>"
        }
        text = replacing(link, in: text) { "<a href=\"\($0[2])\">\($0[1])</a>" }
        text = replacing(bareURL, in: text) { "<a href=\"\($0[0])\">\($0[0])</a>" }
        text = replacing(bold, in: text) { "<strong>\($0[2])</strong>" }
        text = replacing(italicStar, in: text) { "<em>\($0[1])</em>" }
        text = replacing(italicUnderscore, in: text) { "<em>\($0[1])</em>" }
        text = replacing(strikethrough, in: text) { "<del>\($0[1])</del>" }
        for (index, span) in codeSpans.enumerated() {
            text = text.replacingOccurrences(of: "\u{1}\(index)\u{1}", with: span)
        }
        return text.replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Local images are embedded, so the exported file still shows them after it's moved.
    private static func imageSource(_ source: String, baseURL: URL?) -> String {
        if let url = URL(string: source, relativeTo: baseURL)?.absoluteURL, url.isFileURL,
           let data = try? Data(contentsOf: url), data.count < 15_000_000 {
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            return "data:\(type);base64,\(data.base64EncodedString())"
        }
        return escape(source)
    }

    /// The same code colours as reading mode, as spans the stylesheet paints.
    private static func highlighted(_ code: String, language: String) -> String {
        let source = code as NSString
        var result = ""
        var last = 0
        for (range, token) in CodeHighlighter.tokens(in: code, language: language) {
            result += escape(source.substring(with: NSRange(location: last, length: range.location - last)))
            result += "<span class=\"\(name(of: token))\">\(escape(source.substring(with: range)))</span>"
            last = NSMaxRange(range)
        }
        return result + escape(source.substring(from: last))
    }

    private static func name(of token: CodeToken) -> String {
        switch token {
        case .keyword: "kw"
        case .string: "str"
        case .number: "num"
        case .comment: "com"
        }
    }

    // MARK: - Styling

    private static func stylesheet(theme: Theme, fontID: String, fontSize: CGFloat) -> String {
        let text = css(theme.text)
        let secondary = css(theme.secondary)
        let accent = css(theme.accent)
        let code = css(theme.codeBackground)
        return """
        :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
        * { box-sizing: border-box; }
        body { margin: 0; background: \(css(theme.background)); color: \(text); font-family: \(fontFamily(fontID)); font-size: \(Int(fontSize))px; line-height: 1.65; -webkit-font-smoothing: antialiased; }
        main { max-width: 720px; margin: 0 auto; padding: 72px 32px 96px; }
        main > * { margin: 0; }
        main > * + * { margin-top: 0.95em; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; }
        h1 { font-size: 1.7em; }
        h2 { font-size: 1.4em; }
        h3 { font-size: 1.2em; }
        h4 { font-size: 1.08em; }
        h5, h6 { font-size: 1em; }
        main > * + h1, main > * + h2 { margin-top: 1.7em; }
        main > * + h3, main > * + h4 { margin-top: 1.3em; }
        a { color: \(accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; }
        code { font-size: 0.88em; background: \(code); padding: 0.1em 0.35em; border-radius: 4px; }
        pre { position: relative; background: \(code); padding: 16px 18px; border-radius: 12px; overflow-x: auto; font-size: 0.84em; line-height: 1.5; }
        pre code { background: none; padding: 0; font-size: 1em; }
        pre .kw { color: \(css(theme.code.keyword)); }
        pre .str { color: \(css(theme.code.string)); }
        pre .num { color: \(css(theme.code.number)); }
        pre .com { color: \(css(theme.code.comment)); }
        pre .language { position: absolute; top: 8px; right: 12px; font: 500 10.5px -apple-system, system-ui, sans-serif; color: \(secondary); }
        blockquote { padding-left: 14px; border-left: 3px solid \(css(theme.accent, alpha: 0.5)); font-style: italic; color: \(css(theme.text, alpha: 0.75)); }
        hr { border: 0; height: 1px; background: \(css(theme.secondary, alpha: 0.35)); }
        main > hr { margin: 1.6em 0; }
        .list .item { display: flex; gap: 10px; padding-left: calc(var(--depth) * 1.4em); }
        .list .item + .item { margin-top: 0.4em; }
        .marker { color: \(accent); min-width: 0.9em; text-align: right; font-variant-numeric: tabular-nums; }
        .done .text { color: \(secondary); text-decoration: line-through; }
        table { width: 100%; border-collapse: separate; border-spacing: 0; border: 1px solid \(css(theme.secondary, alpha: 0.3)); border-radius: 10px; overflow: hidden; font-size: 0.92em; }
        th, td { text-align: left; vertical-align: top; padding: 8px 12px; }
        th { font-weight: 600; background: \(code); }
        tbody tr:nth-child(even) td { background: \(code); }
        img { max-width: 100%; border-radius: 8px; }
        """
    }

    private static func fontFamily(_ id: String) -> String {
        switch id {
        case "system": return #"-apple-system, system-ui, "Helvetica Neue", sans-serif"#
        case "system-serif": return #""New York", ui-serif, Georgia, serif"#
        case "system-rounded": return #"ui-rounded, "SF Pro Rounded", -apple-system, sans-serif"#
        case "system-mono": return #"ui-monospace, "SF Mono", Menlo, monospace"#
        default: return "\"\(id.replacingOccurrences(of: "\"", with: ""))\", -apple-system, sans-serif"
        }
    }

    private static func css(_ color: PlatformColor, alpha: CGFloat? = nil) -> String {
        let rgba = color.srgbComponents
        return String(
            format: "rgba(%d, %d, %d, %.3f)",
            Int((rgba.red * 255).rounded()),
            Int((rgba.green * 255).rounded()),
            Int((rgba.blue * 255).rounded()),
            alpha ?? rgba.alpha
        )
    }

    // MARK: - Helpers

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Replaces every match with `transform(captureGroups)`; unmatched groups are empty strings.
    private static func replacing(_ regex: NSRegularExpression, in text: String, with transform: ([String]) -> String) -> String {
        let source = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map {
                let range = match.range(at: $0)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            result += transform(groups)
            last = NSMaxRange(match.range)
        }
        return result + source.substring(from: last)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let inlineCode = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let image = regex(#"!\[([^\]]*)\]\(([^)\s]+)\)"#)
    private static let link = regex(#"\[([^\]]+)\]\(([^)\s]+)\)"#)
    private static let bareURL = regex(#"(?<![">=\w/])https?://[^\s<"]+"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = regex(#"(?<![*\\\w])\*(?![\s*])(.+?)(?<![\s*\\])\*(?![*\w])"#)
    private static let italicUnderscore = regex(#"(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#)
    private static let strikethrough = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
}
