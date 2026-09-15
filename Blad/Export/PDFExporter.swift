import SwiftUI

/// Lays reading mode out on A4 pages. Pages break between blocks, never through a line of text.
enum PDFExporter {
    private static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 60
    /// Reading mode is sized for a screen; this brings 17 pt text down to about 11.5 pt on paper.
    private static let scale: CGFloat = 0.68

    static func export(blocks: [MarkdownBlock], title: String, fontID: String, fontSize: CGFloat, baseURL: URL?, to url: URL) throws {
        let layoutWidth = (pageSize.width - margin * 2) / scale
        let pageHeight = (pageSize.height - margin * 2) / scale
        let spacing = fontSize * 0.95

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Blad"] as CFDictionary
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let pieces = splitForPages(blocks)
        var y: CGFloat = 0
        var isPageOpen = false

        for (index, piece) in pieces.enumerated() {
            let content = ReadingContent(
                blocks: [piece],
                baseURL: baseURL,
                theme: .paper,
                fontID: fontID,
                fontSize: fontSize,
                onToggleTask: { _ in },
                isFirstBlockAtTop: index == 0
            )
            .frame(width: layoutWidth)

            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: layoutWidth, height: nil)
            renderer.render { size, draw in
                var top = y == 0 ? 0 : y + spacing
                if isPageOpen, top + size.height > pageHeight {
                    context.endPDFPage()
                    isPageOpen = false
                }
                if !isPageOpen {
                    context.beginPDFPage(nil)
                    isPageOpen = true
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

        if !isPageOpen {
            context.beginPDFPage(nil)
        }
        context.endPDFPage()
        context.closePDF()
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
}
