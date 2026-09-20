import SwiftUI
import PhotosUI
import UIKit

/// One page on iPhone or iPad: the markdown editor, or the same page in reading mode.
struct PageScreen: View {
    let document: DocumentModel
    let theme: Theme
    let onOpenPage: (URL) -> Void
    /// Tapping a #tag leaves the page so the search field can show what has that tag.
    let onCloseForSearch: () -> Void

    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(Pref.font) private var fontID = EditorFont.defaultID
    @AppStorage(Pref.fontSize) private var fontSize = Pref.defaultFontSize
    @AppStorage(Pref.lineWidth) private var lineWidth = Pref.defaultLineWidth
    @AppStorage(Pref.paperGrain) private var paperGrain = true
    @AppStorage(Pref.showWordCount) private var showWordCount = true
    @AppStorage(Pref.spellCheck) private var spellCheck = true

    @State private var editor = EditorController()
    @State private var isPickingLink = false
    @State private var isPickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var backlinks: [Backlink] = []
    @State private var showsOutline = false
    @State private var isFocusMode = false
    @State private var sharedFile: SharedFile?

    var body: some View {
        ZStack {
            MarkdownTextView(
                text: document.text,
                style: style,
                baseURL: document.url.deletingLastPathComponent(),
                controller: editor,
                onChange: { document.text = $0 },
                onLinkTrigger: { isPickingLink = true },
                onPhoto: { isPickingPhoto = true },
                jump: document.jump,
                importImages: importImages
            )
            .opacity(document.isReading ? 0 : 1)
            .ignoresSafeArea(.container, edges: .bottom)

            if document.isReading {
                ReadingView(
                    text: document.text,
                    baseURL: document.url.deletingLastPathComponent(),
                    theme: theme,
                    fontID: fontID,
                    fontSize: fontSize,
                    lineWidth: lineWidth,
                    backlinks: backlinks,
                    jump: document.jump,
                    onToggleTask: { document.toggleTask(atLine: $0) },
                    onOpenBacklink: onOpenPage
                )
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .background {
            PaperBackground(theme: theme, showsGrain: paperGrain)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {
            if showWordCount, !editor.isEditing, !isFocusMode {
                wordCount
                    .padding(16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isFocusMode {
                Button("Klaar") {
                    withAnimation(.smooth) { isFocusMode = false }
                }
                .buttonStyle(.glass)
                .padding()
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(isFocusMode ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(isFocusMode)
        .sheet(isPresented: $showsOutline) {
            NavigationStack {
                OutlineList(headings: document.headings) { heading in
                    showsOutline = false
                    document.jump = Jump(offset: heading.offset, heading: heading.id)
                }
                .navigationTitle("Overzicht")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Klaar") { showsOutline = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color(platform: theme.background))
        }
        .sheet(isPresented: $isPickingLink) {
            LinkPicker(
                pages: library.pageRefs,
                theme: theme,
                onPick: { title in
                    isPickingLink = false
                    editor.insertLink(title)
                },
                onCancel: { _ in isPickingLink = false },
                onFocusLost: {},
                onSizeChange: { _ in },
                fillsWidth: true
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(Color(platform: theme.background))
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                defer { photo = nil }
                // Photos are often HEIC; JPEG opens everywhere, on the Mac and on GitHub alike.
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) else { return }
                editor.insertImages(importImages(.data(jpeg, pathExtension: "jpg")))
            }
        }
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
        }
        .environment(\.openURL, OpenURLAction { url in
            if let tag = Tags.name(from: url) {
                library.pendingSearch = "#" + tag
                onCloseForSearch()
                return .handled
            }
            if url.scheme == WikiLinks.urlScheme {
                let name = String(url.absoluteString.dropFirst(WikiLinks.urlScheme.count + 1))
                if let page = library.openPage(named: name.removingPercentEncoding ?? name, from: document.url) {
                    onOpenPage(page)
                }
                return .handled
            }
            guard url.isFileURL, FileNode.isMarkdown(url) else { return .systemAction }
            onOpenPage(url)
            return .handled
        })
        .task(id: document.isReading) {
            guard document.isReading else { return }
            backlinks = await library.backlinks(to: document)
        }
        .onDisappear {
            library.finishEditing(document)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                document.isReading.toggle()
            } label: {
                Label(document.isReading ? "Bewerk" : "Lees", systemImage: document.isReading ? "pencil" : "book")
            }
            .keyboardShortcut("r")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Focusmodus", systemImage: "scope") {
                    withAnimation(.smooth) { isFocusMode = true }
                }
                Button("Overzicht", systemImage: "list.bullet.indent") { showsOutline = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Zoek in pagina", systemImage: "magnifyingglass") { editor.find() }
                    .keyboardShortcut("f")
                    .disabled(document.isReading)
                Divider()
                Button("Deel als PDF", systemImage: "doc.richtext") { share(.pdf) }
                Button("Deel als HTML", systemImage: "chevron.left.forwardslash.chevron.right") { share(.html) }
                Button("Deel markdown", systemImage: "square.and.arrow.up") {
                    document.save()
                    sharedFile = SharedFile(url: document.url)
                }
            } label: {
                Label("Meer", systemImage: "ellipsis")
            }
        }
    }

    private var wordCount: some View {
        let words = document.wordCount
        return Text(words == 1 ? "1 woord" : "\(words.formatted()) woorden")
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassEffect(.regular, in: .capsule)
    }

    private var style: EditorStyle {
        EditorStyle(
            theme: theme,
            fontID: fontID,
            fontSize: fontSize,
            lineWidth: lineWidth,
            focusMode: isFocusMode,
            dimsParagraphs: false,
            typewriterScrolling: false,
            checksSpelling: spellCheck,
            // A phone can't spare three characters of margin on each side.
            gutterScale: sizeClass == .compact ? 1.2 : 3.2
        )
    }

    private func importImages(_ source: ImageImporter.Source) -> [String] {
        do {
            return try ImageImporter.importImages(source, for: document.url)
        } catch {
            library.errorMessage = "Kon de afbeelding niet bewaren.\n\n\(error.localizedDescription)"
            return []
        }
    }

    private enum ShareFormat {
        case pdf, html
    }

    private func share(_ format: ShareFormat) {
        document.save()
        let blocks = MarkdownBlock.parse(document.text)
        let baseURL = document.url.deletingLastPathComponent()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            switch format {
            case .pdf:
                let url = folder.appendingPathComponent(document.title).appendingPathExtension("pdf")
                try PDFExporter.export(blocks: blocks, title: document.title, fontID: fontID, fontSize: fontSize, baseURL: baseURL, to: url)
                sharedFile = SharedFile(url: url)
            case .html:
                let url = folder.appendingPathComponent(document.title).appendingPathExtension("html")
                let html = HTMLExporter.html(for: blocks, title: document.title, theme: theme, fontID: fontID, fontSize: fontSize, baseURL: baseURL)
                try html.write(to: url, atomically: true, encoding: .utf8)
                sharedFile = SharedFile(url: url)
            }
        } catch {
            library.errorMessage = "Kon \(document.title) niet delen.\n\n\(error.localizedDescription)"
        }
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
