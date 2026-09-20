import SwiftUI

/// Lays reading mode out on A4 pages. Pages break between blocks, never through a line of text.
/// A whole space can go into one PDF: a cover, a contents list, and every page after it.
enum PDFExporter {
    private static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 60
    /// Reading mode is sized for a screen; this brings 17 pt text down to about 11.5 pt on paper.
    private static let scale: CGFloat = 0.68

    /// One page of a bundle: a note with the title it gets in the contents.
    struct Section {
        let title: String
        let text: String
        let baseURL: URL?
    }

    static func export(blocks: [MarkdownBlock], title: String, fontID: String, fontSize: CGFloat, baseURL: URL?, to url: URL) throws {
        let writer = try Writer(url: url, title: title)
        write(blocks: blocks, fontID: fontID, fontSize: fontSize, baseURL: baseURL, with: writer, numbersPages: false)
        writer.finish()
    }

    /// A whole space as one PDF: cover, contents with page numbers, then every page.
    static func export(sections: [Section], title: String, fontID: String, fontSize: CGFloat, to url: URL) throws {
        let parsed = sections.map { (section: $0, blocks: splitForPages(MarkdownBlock.parse($0.text))) }
        let spacing = fontSize * 0.95

        // How many sheets each page fills, so the contents can name the right sheet.
        let lengths = parsed.map { pages(of: $0.blocks, fontID: fontID, fontSize: fontSize, spacing: spacing) }
        let rows = sections.map(\.title)
        let contentsSheets = contentsPages(for: rows, fontSize: fontSize)

        var start: [Int] = []
        var sheet = 1 + contentsSheets + 1   // the cover, the contents, then the first page
        for length in lengths {
            start.append(sheet)
            sheet += length
        }

        let writer = try Writer(url: url, title: title)
        writer.add(view: Cover(title: title, count: sections.count, fontSize: fontSize), spacing: 0, onNewPage: true)
        writer.startNumbering()

        writer.add(view: ContentsHeading(fontSize: fontSize), spacing: 0, onNewPage: true)
        for (index, row) in rows.enumerated() {
            writer.add(view: ContentsRow(title: row, page: start[index], fontSize: fontSize), spacing: fontSize * 0.4, onNewPage: false)
        }

        for (section, blocks) in parsed {
            writer.add(view: PageTitle(title: section.title, fontSize: fontSize), spacing: 0, onNewPage: true)
            write(blocks: blocks, fontID: fontID, fontSize: fontSize, baseURL: section.baseURL, with: writer, numbersPages: true, isSplit: true)
        }
        writer.finish()
    }

    // MARK: Laying out

    private static func write(
        blocks: [MarkdownBlock],
        fontID: String,
        fontSize: CGFloat,
        baseURL: URL?,
        with writer: Writer,
        numbersPages: Bool,
        isSplit: Bool = false
    ) {
        let pieces = isSplit ? blocks : splitForPages(blocks)
        for (index, piece) in pieces.enumerated() {
            writer.add(
                view: content(piece, baseURL: baseURL, fontID: fontID, fontSize: fontSize, isFirst: index == 0 && !numbersPages),
                spacing: fontSize * 0.95,
                onNewPage: false
            )
        }
    }

    private static func content(_ block: MarkdownBlock, baseURL: URL?, fontID: String, fontSize: CGFloat, isFirst: Bool) -> some View {
        ReadingContent(
            blocks: [block],
            baseURL: baseURL,
            theme: .paper,
            fontID: fontID,
            fontSize: fontSize,
            onToggleTask: { _ in },
            isFirstBlockAtTop: isFirst
        )
        .frame(width: (pageSize.width - margin * 2) / scale)
    }

    /// How many sheets these blocks fill on their own, without drawing anything.
    private static func pages(of blocks: [MarkdownBlock], fontID: String, fontSize: CGFloat, spacing: CGFloat) -> Int {
        let limit = (pageSize.height - margin * 2) / scale
        var sheets = 1
        var y = height(of: PageTitle(title: " ", fontSize: fontSize))

        for block in blocks {
            let size = height(of: content(block, baseURL: nil, fontID: fontID, fontSize: fontSize, isFirst: false))
            let top = y + spacing
            if top + size > limit {
                sheets += 1
                y = size
            } else {
                y = top + size
            }
        }
        return sheets
    }

    /// How many sheets the contents list fills, so page numbers in it are right.
    private static func contentsPages(for titles: [String], fontSize: CGFloat) -> Int {
        guard let first = titles.first else { return 1 }
        let limit = (pageSize.height - margin * 2) / scale
        let row = height(of: ContentsRow(title: first, page: 1, fontSize: fontSize)) + fontSize * 0.4

        var sheets = 1
        var y = height(of: ContentsHeading(fontSize: fontSize))
        for _ in titles {
            if y + row > limit {
                sheets += 1
                y = row
            } else {
                y += row
            }
        }
        return sheets
    }

    private static func height(of view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: (pageSize.width - margin * 2) / scale))
        renderer.proposedSize = ProposedViewSize(width: (pageSize.width - margin * 2) / scale, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }

    /// Long code blocks and lists are cut into pieces that fit on a page.
    private static func splitForPages(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        blocks.flatMap { block -> [MarkdownBlock] in
            switch block {
            case .code(let language, let code):
                let lines = code.components(separatedBy: "\n")
                guard lines.count > 40 else { return [block] }
                return stride(from: 0, to: lines.count, by: 40).map { start in
                    .code(language: start == 0 ? language : "", code: lines[start..<min(start + 40, lines.count)].joined(separator: "\n"))
                }
            case .list(let items) where items.count > 12:
                return stride(from: 0, to: items.count, by: 12).map { start in
                    .list(Array(items[start..<min(start + 12, items.count)]))
                }
            default:
                return [block]
            }
        }
    }

    // MARK: Writing sheets

    /// Fills A4 sheets one view at a time and numbers them at the bottom.
    private final class Writer {
        private let context: CGContext
        private let limit = (pageSize.height - margin * 2) / scale
        private var y: CGFloat = 0
        private var isOpen = false
        private var sheet = 0
        private var numbers = false
        private var numbersThisSheet = false

        init(url: URL, title: String) throws {
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Blad"] as CFDictionary
            guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info) else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.context = context
        }

        /// Sheets from here on get a page number; the cover doesn't.
        func startNumbering() { numbers = true }

        func add(view: some View, spacing: CGFloat, onNewPage: Bool) {
            let width = (pageSize.width - margin * 2) / scale
            let renderer = ImageRenderer(content: view.frame(width: width))
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            renderer.render { size, draw in
                var top = y == 0 ? 0 : y + spacing
                if isOpen, onNewPage || top + size.height > limit {
                    end()
                }
                if !isOpen {
                    begin()
                    top = 0
                }
                context.saveGState()
                context.translateBy(x: margin, y: pageSize.height - margin - (top + size.height) * scale)
                context.scaleBy(x: scale, y: scale)
                draw(context)
                context.restoreGState()
                y = top + size.height
            }
        }

        func finish() {
            if !isOpen { begin() }
            end()
            context.closePDF()
        }

        private func begin() {
            context.beginPDFPage(nil)
            isOpen = true
            sheet += 1
            numbersThisSheet = numbers
            y = 0
        }

        private func end() {
            if numbersThisSheet { drawNumber() }
            context.endPDFPage()
            isOpen = false
        }

        private func drawNumber() {
            let renderer = ImageRenderer(content: PageNumber(sheet: sheet))
            renderer.render { size, draw in
                context.saveGState()
                context.translateBy(x: (pageSize.width - size.width * scale) / 2, y: margin / 2)
                context.scaleBy(x: scale, y: scale)
                draw(context)
                context.restoreGState()
            }
        }
    }

    // MARK: The pages Blad adds itself

    private struct Cover: View {
        let title: String
        let count: Int
        let fontSize: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: fontSize * 0.8) {
                Text(title)
                    .font(.system(size: fontSize * 2.6, weight: .semibold, design: .serif))
                Text(count == 1 ? "1 pagina" : "\(count) pagina's")
                    .font(.system(size: fontSize, design: .serif))
                    .foregroundStyle(Color(platform: Theme.paper.secondary))
                Text(Date.now.formatted(date: .long, time: .omitted))
                    .font(.system(size: fontSize, design: .serif))
                    .foregroundStyle(Color(platform: Theme.paper.secondary))
            }
            .padding(.top, fontSize * 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color(platform: Theme.paper.text))
        }
    }

    private struct ContentsHeading: View {
        let fontSize: CGFloat

        var body: some View {
            Text("Inhoud")
                .font(.system(size: fontSize * 1.6, weight: .semibold, design: .serif))
                .foregroundStyle(Color(platform: Theme.paper.text))
                .padding(.bottom, fontSize * 0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct ContentsRow: View {
        let title: String
        let page: Int
        let fontSize: CGFloat

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: fontSize, design: .serif))
                    .lineLimit(1)
                Rectangle()
                    .fill(Color(platform: Theme.paper.secondary).opacity(0.4))
                    .frame(height: 0.5)
                    .offset(y: -fontSize * 0.25)
                Text("\(page)")
                    .font(.system(size: fontSize * 0.9, design: .serif))
                    .foregroundStyle(Color(platform: Theme.paper.secondary))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color(platform: Theme.paper.text))
        }
    }

    /// The page's own title above its text, so a bundle reads like a book.
    private struct PageTitle: View {
        let title: String
        let fontSize: CGFloat

        var body: some View {
            Text(title)
                .font(.system(size: fontSize * 0.8, weight: .medium, design: .serif))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color(platform: Theme.paper.secondary))
                .padding(.bottom, fontSize * 0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct PageNumber: View {
        let sheet: Int

        var body: some View {
            Text("\(sheet)")
                .font(.system(size: 15, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Color(platform: Theme.paper.secondary))
        }
    }
}
