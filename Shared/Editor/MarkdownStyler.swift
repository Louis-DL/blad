import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditorStyle: Equatable {
    var theme: Theme
    var fontID: String
    var fontSize: CGFloat
    var lineWidth: CGFloat
    var focusMode: Bool
    var dimsParagraphs: Bool
    var typewriterScrolling: Bool
    /// Width of the margin where markers hang, in multiples of the font size. Narrower on iPhone.
    var gutterScale: CGFloat = 3.2
}

extension NSAttributedString.Key {
    /// Marks lines of a fenced code block; the text view draws one rounded panel behind them.
    static let codeBlock = NSAttributedString.Key("BladCodeBlock")
    /// Marks `inline code`; drawn as a small rounded background.
    static let inlineCode = NSAttributedString.Key("BladInlineCode")
    /// The page name of a `[[page]]` link, for ⌘-click.
    static let wikiLink = NSAttributedString.Key("BladWikiLink")
    /// The destination of a markdown link or bare URL, for ⌘-click.
    static let linkTarget = NSAttributedString.Key("BladLinkTarget")
    /// The source of an image previewed under its markdown line.
    static let imagePreview = NSAttributedString.Key("BladImagePreview")
}

/// Styles markdown in place. The syntax stays visible, just quieter than the words around it,
/// and heading and quote markers hang in the margin so the text itself lines up.
final class MarkdownStyler {
    private(set) var style: EditorStyle
    private(set) var bodyFont: PlatformFont
    private(set) var codeFont: PlatformFont
    private var lastFenceCount = -1

    /// Display size for an image path, or nil when there's nothing to preview.
    var imageSize: ((String) -> CGSize?)?

    /// Room on both sides of the text column where markers hang.
    var gutter: CGFloat { (style.fontSize * style.gutterScale).rounded() }
    /// Inner padding of code block panels.
    var codePadding: CGFloat { 14 }

    init(style: EditorStyle) {
        self.style = style
        bodyFont = EditorFont.font(id: style.fontID, size: style.fontSize)
        codeFont = .monospacedSystemFont(ofSize: (style.fontSize * 0.86).rounded(), weight: .regular)
    }

    func update(_ style: EditorStyle) {
        self.style = style
        bodyFont = EditorFont.font(id: style.fontID, size: style.fontSize)
        codeFont = .monospacedSystemFont(ofSize: (style.fontSize * 0.86).rounded(), weight: .regular)
        lastFenceCount = -1
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: style.theme.text, .paragraphStyle: paragraph()]
    }

    // MARK: - Highlighting

    /// Restyles the lines touched by an edit, or the whole text when code fences were added or removed.
    func highlight(_ storage: NSTextStorage, editedRange: NSRange? = nil) {
        let text = storage.string
        let string = text as NSString
        let full = NSRange(location: 0, length: string.length)
        let fenceCount = Self.fence.numberOfMatches(in: text, range: full)

        var range = full
        var insideFence = false
        if let editedRange, fenceCount == lastFenceCount {
            let lines = string.lineRange(for: editedRange)
            if Self.fence.firstMatch(in: text, range: lines) == nil {
                range = lines
                let before = NSRange(location: 0, length: lines.location)
                insideFence = Self.fence.numberOfMatches(in: text, range: before) % 2 == 1
            }
        }
        lastFenceCount = fenceCount
        style(storage, in: range, insideFence: insideFence)
    }

    private func style(_ storage: NSTextStorage, in range: NSRange, insideFence: Bool) {
        let string = storage.string as NSString
        storage.setAttributes(baseAttributes, range: range)

        var inFence = insideFence
        var location = range.location
        let end = NSMaxRange(range)
        repeat {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            var content = lineRange
            while content.length > 0 {
                let last = string.character(at: NSMaxRange(content) - 1)
                guard last == 10 || last == 13 else { break }
                content.length -= 1
            }
            let line = string.substring(with: content)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                styleCodeLine(storage, lineRange: lineRange)
                storage.addAttribute(.foregroundColor, value: style.theme.secondary, range: content)
                inFence.toggle()
            } else if inFence {
                styleCodeLine(storage, lineRange: lineRange)
            } else {
                styleBlock(storage, line: line, content: content, lineRange: lineRange)
            }

            location = NSMaxRange(lineRange)
        } while location < end
    }

    private func styleCodeLine(_ storage: NSTextStorage, lineRange: NSRange) {
        let paragraph = paragraph(indent: codePadding, tailIndent: codePadding, lineHeight: 1.25)
        storage.addAttributes([.font: codeFont, .paragraphStyle: paragraph, .codeBlock: true], range: lineRange)
    }

    private func styleBlock(_ storage: NSTextStorage, line: String, content: NSRange, lineRange: NSRange) {
        let theme = style.theme
        let nsLine = line as NSString
        let local = NSRange(location: 0, length: nsLine.length)
        let offset = content.location

        if let match = Self.imageLine.firstMatch(in: line, range: local) {
            // The markup goes quiet; the image itself is drawn in the space left below the line.
            let source = nsLine.substring(with: match.range(at: 1))
            storage.addAttributes([.font: codeFont, .foregroundColor: theme.secondary, .linkTarget: source], range: content)
            if let size = imageSize?(source) {
                storage.addAttributes([.paragraphStyle: paragraph(spacingAfter: size.height + 20), .imagePreview: source], range: lineRange)
            }
            return
        }

        if let match = Self.heading.firstMatch(in: line, range: local) {
            let level = match.range(at: 1).length
            let scale: [CGFloat] = [1.7, 1.4, 1.2, 1.08, 1.0, 1.0]
            let font = EditorFont.font(id: style.fontID, size: (style.fontSize * scale[level - 1]).rounded(), weight: .semibold)
            let markerEnd = NSMaxRange(match.range(at: 2))
            let markerWidth = nsLine.substring(to: markerEnd).size(withAttributes: [.font: font]).width
            let spacing = content.location == 0 ? 0 : style.fontSize * (level <= 2 ? 1.2 : 0.8)
            let paragraph = paragraph(firstLineIndent: max(0, gutter - markerWidth), spacingBefore: spacing)
            storage.addAttributes([.font: font, .paragraphStyle: paragraph], range: lineRange)
            storage.addAttribute(.foregroundColor, value: theme.secondary, range: NSRange(location: offset, length: markerEnd))
        } else if let match = Self.quote.firstMatch(in: line, range: local) {
            let markerWidth = nsLine.substring(with: match.range).size(withAttributes: [.font: bodyFont]).width
            storage.addAttributes([
                .paragraphStyle: paragraph(firstLineIndent: max(0, gutter - markerWidth)),
                .foregroundColor: theme.text.withAlphaComponent(0.75),
                .font: bodyFont.adding(italic: true),
            ], range: lineRange)
            storage.addAttribute(.foregroundColor, value: theme.secondary, range: shifted(match.range, by: offset))
        } else if Self.rule.firstMatch(in: line, range: local) != nil {
            storage.addAttribute(.foregroundColor, value: theme.secondary, range: content)
            return
        } else if let match = Self.listItem.firstMatch(in: line, range: local) {
            let markerEnd = NSMaxRange(match.range)
            let prefixWidth = nsLine.substring(to: markerEnd).size(withAttributes: [.font: bodyFont]).width
            storage.addAttribute(.paragraphStyle, value: paragraph(firstLineIndent: gutter, indent: prefixWidth), range: lineRange)
            storage.addAttribute(.foregroundColor, value: theme.accent, range: shifted(match.range(at: 2), by: offset))

            let box = match.range(at: 4)
            if box.location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: theme.secondary, range: shifted(box, by: offset))
                if nsLine.substring(with: box).lowercased().contains("x") {
                    let rest = NSRange(location: offset + markerEnd, length: nsLine.length - markerEnd)
                    storage.addAttributes([
                        .foregroundColor: theme.secondary,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: theme.secondary.withAlphaComponent(0.7),
                    ], range: rest)
                }
            }
        }

        styleInline(storage, line: line, offset: offset)
    }

    private func styleInline(_ storage: NSTextStorage, line: String, offset: Int) {
        let local = NSRange(location: 0, length: (line as NSString).length)
        guard local.length > 1 else { return }
        let theme = style.theme

        var codeRanges: [NSRange] = []
        for match in Self.inlineCode.matches(in: line, range: local) {
            codeRanges.append(match.range)
            let range = shifted(match.range, by: offset)
            let ticks = match.range(at: 1).length
            storage.addAttributes([.font: codeFont, .inlineCode: true], range: range)
            dimMarkers(storage, range: range, length: ticks)
        }
        func isOutsideCode(_ range: NSRange) -> Bool {
            !codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        for match in Self.bold.matches(in: line, range: local) where isOutsideCode(match.range) {
            let range = shifted(match.range, by: offset)
            addTraits(bold: true, to: storage, in: range)
            dimMarkers(storage, range: range, length: 2)
        }
        for regex in [Self.italicStar, Self.italicUnderscore] {
            for match in regex.matches(in: line, range: local) where isOutsideCode(match.range) {
                let range = shifted(match.range, by: offset)
                addTraits(italic: true, to: storage, in: range)
                dimMarkers(storage, range: range, length: 1)
            }
        }
        for match in Self.strikethrough.matches(in: line, range: local) where isOutsideCode(match.range) {
            let range = shifted(match.range, by: offset)
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: theme.secondary,
            ], range: range)
            dimMarkers(storage, range: range, length: 2)
        }
        for match in Self.bareURL.matches(in: line, range: local) where isOutsideCode(match.range) {
            let target = (line as NSString).substring(with: match.range)
            storage.addAttributes([.foregroundColor: theme.accent, .linkTarget: target], range: shifted(match.range, by: offset))
        }
        for match in Self.link.matches(in: line, range: local) where isOutsideCode(match.range) {
            let target = (line as NSString).substring(with: match.range(at: 2))
            storage.addAttributes([.foregroundColor: theme.secondary, .linkTarget: target], range: shifted(match.range, by: offset))
            storage.addAttribute(.foregroundColor, value: theme.accent, range: shifted(match.range(at: 1), by: offset))
        }
        for match in WikiLinks.pattern.matches(in: line, range: local) where isOutsideCode(match.range) {
            let page = (line as NSString).substring(with: match.range(at: 1))
            storage.addAttributes([.foregroundColor: theme.secondary, .wikiLink: page], range: shifted(match.range, by: offset))
            let shown = match.range(at: 2).location == NSNotFound ? match.range(at: 1) : match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: theme.accent, range: shifted(shown, by: offset))
        }
    }

    // MARK: - Helpers

    private func paragraph(
        firstLineIndent: CGFloat? = nil,
        indent: CGFloat = 0,
        tailIndent: CGFloat = 0,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0,
        lineHeight: CGFloat = 1.4
    ) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeight
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        paragraph.headIndent = gutter + indent
        paragraph.firstLineHeadIndent = firstLineIndent ?? (gutter + indent)
        paragraph.tailIndent = -(gutter + tailIndent)
        return paragraph
    }

    private func addTraits(bold: Bool = false, italic: Bool = false, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? PlatformFont else { return }
            storage.addAttribute(.font, value: font.adding(bold: bold, italic: italic), range: subrange)
        }
    }

    private func dimMarkers(_ storage: NSTextStorage, range: NSRange, length: Int) {
        guard range.length >= length * 2 else { return }
        let color = style.theme.secondary
        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: range.location, length: length))
        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: NSMaxRange(range) - length, length: length))
    }

    private func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let fence = regex(#"^[ \t]*(```|~~~)"#)
    private static let heading = regex(#"^(#{1,6})([ \t]+|$)"#)
    private static let quote = regex(#"^[ \t]*(?:>[ \t]?)+"#)
    private static let rule = regex(#"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    /// Groups: 1 indent, 2 marker, 3 spacing, 4 optional task box.
    static let listItem = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let inlineCode = regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = regex(#"(?<![*\\\w])\*(?![\s*])(.+?)(?<![\s*\\])\*(?![*\w])"#)
    private static let italicUnderscore = regex(#"(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#)
    private static let strikethrough = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = regex(#"!?\[([^\]\n]+)\]\(([^)\s]*)(?:\s+"[^"]*")?\)"#)
    private static let bareURL = regex(#"(?<![(<\w])https?://[^\s)>\]]+"#)
    /// A line holding only `![alt](path)`.
    private static let imageLine = regex(#"^[ \t]*!\[[^\]\n]*\]\(([^)\s]+)(?:[ \t]+"[^"]*")?\)[ \t]*$"#)
}
