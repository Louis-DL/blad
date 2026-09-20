import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat {
    case pdf, html
}

extension AppModel {
    func exportActiveDocument(as format: ExportFormat) {
        guard let document = activeDocument else { return }
        document.save()

        let panel = NSSavePanel()
        panel.title = format == .pdf ? "Exporteer als PDF" : "Exporteer als HTML"
        panel.prompt = "Exporteer"
        panel.nameFieldStringValue = document.title + (format == .pdf ? ".pdf" : ".html")
        panel.allowedContentTypes = [format == .pdf ? .pdf : .html]
        panel.directoryURL = document.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let defaults = UserDefaults.standard
        let fontID = defaults.string(forKey: Pref.font) ?? EditorFont.defaultID
        let fontSize = defaults.object(forKey: Pref.fontSize) as? Double ?? Pref.defaultFontSize
        let blocks = MarkdownBlock.parse(document.text)
        let baseURL = document.url.deletingLastPathComponent()

        do {
            switch format {
            case .pdf:
                try PDFExporter.export(blocks: blocks, title: document.title, fontID: fontID, fontSize: fontSize, baseURL: baseURL, to: url)
            case .html:
                let html = HTMLExporter.html(for: blocks, title: document.title, theme: exportTheme, fontID: fontID, fontSize: fontSize, baseURL: baseURL)
                try html.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            present(error, "Kon \(document.title) niet exporteren")
        }
    }

    /// A whole space as one PDF: a cover, a contents list with page numbers, then every page in
    /// the order of the sidebar. Handy to print a course before an exam.
    func exportWorkspace(_ workspace: URL) {
        saveAll()
        let name = workspace.lastPathComponent
        let pages = markdownPages(in: trees[workspace] ?? [])
        guard !pages.isEmpty else {
            errorMessage = "Kon \(name) niet exporteren.\n\nDeze ruimte heeft nog geen pagina's."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exporteer ruimte als PDF"
        panel.prompt = "Exporteer"
        panel.nameFieldStringValue = name + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = workspace.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let defaults = UserDefaults.standard
        let fontID = defaults.string(forKey: Pref.font) ?? EditorFont.defaultID
        let fontSize = defaults.object(forKey: Pref.fontSize) as? Double ?? Pref.defaultFontSize
        let sections = pages.map { page in
            PDFExporter.Section(
                title: page.deletingPathExtension().lastPathComponent,
                text: openText(of: page) ?? (try? String(contentsOf: page, encoding: .utf8)) ?? "",
                baseURL: page.deletingLastPathComponent()
            )
        }

        do {
            try PDFExporter.export(sections: sections, title: name, fontID: fontID, fontSize: fontSize, to: url)
        } catch {
            present(error, "Kon \(name) niet exporteren")
        }
    }

    /// Every page below these nodes, in the order the sidebar shows them.
    private func markdownPages(in nodes: [FileNode]) -> [URL] {
        nodes.flatMap { node in
            node.isDirectory ? markdownPages(in: node.children ?? []) : [node.url]
        }
    }

    /// Unsaved edits belong in the PDF too.
    private func openText(of url: URL) -> String? {
        documents.first { $0.url == url }?.text
    }

    /// HTML keeps the theme you write in; PDF always uses paper colours on white.
    private var exportTheme: Theme {
        let id = ThemeID(rawValue: UserDefaults.standard.string(forKey: Pref.theme) ?? "") ?? .paper
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return Theme.resolve(id, scheme: isDark ? .dark : .light)
    }
}
