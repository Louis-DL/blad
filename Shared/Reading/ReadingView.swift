import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reading mode: the same page, rendered without the markdown syntax.
struct ReadingView: View {
    let text: String
    let baseURL: URL?
    let theme: Theme
    let fontID: String
    let fontSize: CGFloat
    let lineWidth: CGFloat
    let backlinks: [Backlink]
    /// Set by the outline; scrolls to that heading.
    var jump: Jump?
    let onToggleTask: (Int) -> Void
    let onOpenBacklink: (URL) -> Void

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ReadingContent(
                        blocks: blocks,
                        baseURL: baseURL,
                        theme: theme,
                        fontID: fontID,
                        fontSize: fontSize,
                        onToggleTask: onToggleTask
                    )
                    if !backlinks.isEmpty {
                        BacklinksSection(backlinks: backlinks, theme: theme, onOpen: onOpenBacklink)
                            .padding(.top, fontSize * 3)
                    }
                }
                .frame(maxWidth: lineWidth, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: jump) { _, jump in
                guard let jump, let block = Self.blockIndex(ofHeading: jump.heading, in: blocks) else { return }
                withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(block, anchor: .top) }
            }
        }
    }

    /// Reading mode shows the same headings in the same order, so the nth one is the nth block heading.
    private static func blockIndex(ofHeading number: Int, in blocks: [MarkdownBlock]) -> Int? {
        var seen = 0
        for (index, block) in blocks.enumerated() {
            guard case .heading = block else { continue }
            if seen == number { return index }
            seen += 1
        }
        return nil
    }
}

struct ReadingContent: View {
    let blocks: [MarkdownBlock]
    let baseURL: URL?
    let theme: Theme
    let fontID: String
    let fontSize: CGFloat
    let onToggleTask: (Int) -> Void
    /// False when these blocks continue a page, so a leading heading keeps its space above.
    var isFirstBlockAtTop = true

    private var textColor: Color { Color(platform: theme.text) }
    private var secondary: Color { Color(platform: theme.secondary) }
    private var accent: Color { Color(platform: theme.accent) }
    private var codeBackground: Color { Color(platform: theme.codeBackground) }

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.95) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                view(for: entry.element, isFirst: entry.offset == 0 && isFirstBlockAtTop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(textColor)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, isFirst: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            let scale: [CGFloat] = [1.7, 1.4, 1.2, 1.08, 1.0, 1.0]
            inline(text)
                .font(font(scale[level - 1], weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isFirst ? 0 : fontSize * (level <= 2 ? 0.9 : 0.4))
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            inline(text)
                .font(font())
                .lineSpacing(fontSize * 0.42)
                .fixedSize(horizontal: false, vertical: true)

        case .list(let items):
            VStack(alignment: .leading, spacing: fontSize * 0.4) {
                ForEach(Array(items.enumerated()), id: \.offset) { entry in
                    listRow(entry.element)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 14) {
                Capsule()
                    .fill(accent.opacity(0.5))
                    .frame(width: 3)
                inline(text)
                    .font(font().italic())
                    .lineSpacing(fontSize * 0.42)
                    .foregroundStyle(textColor.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let code):
            codeBlock(code, language: language)

        case .table(let header, let rows):
            table(header: header, rows: rows)

        case .image(let alt, let source):
            ReadingImage(alt: alt, source: source, baseURL: baseURL)

        case .rule:
            Rectangle()
                .fill(secondary.opacity(0.35))
                .frame(height: 1)
                .padding(.vertical, fontSize * 0.5)
        }
    }

    private func listRow(_ item: MarkdownBlock.ListItem) -> some View {
        let isDone = item.marker == .task(done: true)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            switch item.marker {
            case .bullet:
                Text("•")
                    .foregroundStyle(accent)
                    .frame(width: fontSize * 0.9)
            case .number(let number):
                Text(number)
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .frame(minWidth: fontSize * 0.9, alignment: .trailing)
            case .task(let done):
                Button {
                    onToggleTask(item.line)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? accent : secondary)
                }
                .buttonStyle(.plain)
                .frame(width: fontSize * 0.9)
                .help(done ? "Markeer als niet gedaan" : "Markeer als gedaan")
            }

            inline(item.text)
                .strikethrough(isDone, color: secondary)
                .foregroundStyle(isDone ? secondary : textColor)
                .lineSpacing(fontSize * 0.35)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(font())
        .padding(.leading, CGFloat(item.depth) * fontSize * 1.4)
    }

    private func codeBlock(_ code: String, language: String) -> some View {
        let text = Text(code)
            .font(.system(size: (fontSize * 0.84).rounded(), design: .monospaced))
            .lineSpacing(fontSize * 0.2)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

        return ViewThatFits(in: .horizontal) {
            text.fixedSize()
            ScrollView(.horizontal) { text.fixedSize() }
                .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(codeBackground, in: .rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if !language.isEmpty {
                Text(language.lowercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    private func table(header: [String], rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columns, id: \.self) { column in
                    tableCell(header.value(at: column), isHeader: true, isShaded: true)
                }
            }
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        tableCell(rows[row].value(at: column), isHeader: false, isShaded: row % 2 == 1)
                    }
                }
            }
        }
        .font(font(0.92))
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(secondary.opacity(0.3), lineWidth: 1)
        }
    }

    private func tableCell(_ text: String, isHeader: Bool, isShaded: Bool) -> some View {
        inline(text)
            .fontWeight(isHeader ? .semibold : nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(isShaded ? codeBackground : .clear)
    }

    private func font(_ scale: CGFloat = 1, weight: PlatformFont.Weight = .regular) -> Font {
        Font(EditorFont.font(id: fontID, size: (fontSize * scale).rounded(), weight: weight) as CTFont)
    }

    /// Bold, italic, code, strikethrough and links inside a block. `[[Page]]` becomes a link Blad opens.
    private func inline(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let source = Tags.markdownLinks(in: WikiLinks.markdownLinks(in: markdown))
        var result = (try? AttributedString(markdown: source, options: options, baseURL: baseURL)) ?? AttributedString(markdown)
        for range in result.runs.filter({ $0.link != nil }).map(\.range) {
            result[range].foregroundColor = accent
        }
        for range in result.runs.filter({ $0.inlinePresentationIntent?.contains(.code) == true }).map(\.range) {
            result[range].font = Font.system(size: (fontSize * 0.88).rounded(), design: .monospaced)
            result[range].backgroundColor = codeBackground
        }
        return Text(result)
    }
}

private struct BacklinksSection: View {
    let backlinks: [Backlink]
    let theme: Theme
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gelinkt vanuit")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color(platform: theme.secondary))
                .padding(.bottom, 2)
            ForEach(backlinks) { backlink in
                BacklinkRow(backlink: backlink, theme: theme) { onOpen(backlink.url) }
            }
        }
    }
}

private struct BacklinkRow: View {
    let backlink: Backlink
    let theme: Theme
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(backlink.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(platform: theme.text))
                Text(backlink.snippet)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(platform: theme.secondary))
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(platform: theme.codeBackground), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(platform: theme.accent).opacity(isHovering ? 0.45 : 0), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct ReadingImage: View {
    let alt: String
    let source: String
    let baseURL: URL?

    var body: some View {
        if let url, url.isFileURL, let image = PlatformImage.load(contentsOf: url) {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: image.size.width)
                .clipShape(.rect(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let url, !url.isFileURL, url.scheme != nil {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().clipShape(.rect(cornerRadius: 8))
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var url: URL? {
        let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        return (URL(string: source, relativeTo: baseURL) ?? URL(string: encoded, relativeTo: baseURL))?.absoluteURL
    }

    private var placeholder: some View {
        Label(alt.isEmpty ? source : alt, systemImage: "photo")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private extension Array where Element == String {
    func value(at index: Int) -> String {
        indices.contains(index) ? self[index] : ""
    }
}
