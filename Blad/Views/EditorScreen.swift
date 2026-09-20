import SwiftUI

struct EditorScreen: View {
    let document: DocumentModel
    let theme: Theme

    @Environment(AppModel.self) private var model
    @AppStorage(Pref.font) private var fontID = EditorFont.defaultID
    @AppStorage(Pref.fontSize) private var fontSize = Pref.defaultFontSize
    @AppStorage(Pref.lineWidth) private var lineWidth = Pref.defaultLineWidth
    @AppStorage(Pref.dimParagraphs) private var dimParagraphs = true
    @AppStorage(Pref.typewriter) private var typewriter = true
    @AppStorage(Pref.showWordCount) private var showWordCount = true
    @AppStorage(Pref.spellCheck) private var spellCheck = true
    @State private var backlinks: [Backlink] = []

    var body: some View {
        ZStack {
            // The editor stays alive while reading, so undo history and scroll position survive.
            MarkdownEditor(
                document: document,
                text: document.text,
                style: style,
                isActive: !document.isReading,
                pages: { model.pageRefs },
                onOpenPage: { model.openPage(named: $0, from: document.url) },
                onOpenLink: { model.openLink($0, from: document.url) },
                onOpenTag: { model.search(tag: $0) },
                importImages: { source in
                    do {
                        return try ImageImporter.importImages(source, for: document.url)
                    } catch {
                        model.present(error, "Kon de afbeelding niet bewaren")
                        return []
                    }
                },
                onEscape: { model.toggleFocus() }
            )
            .opacity(document.isReading ? 0 : 1)

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
                    onOpenBacklink: { model.openItem($0) }
                )
                // Only fade; animating the switch itself would also animate the page's first layout.
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .mask {
            // Text softly fades out under the tab bar instead of being cut off.
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                Color.black
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .bottomTrailing) {
            StatusBar(document: document, showsWordCount: showWordCount, isFocusMode: model.isFocusMode)
                .padding(18)
        }
        .environment(\.openURL, OpenURLAction { url in
            if let tag = Tags.name(from: url) {
                model.search(tag: tag)
                return .handled
            }
            if url.scheme == WikiLinks.urlScheme {
                let name = String(url.absoluteString.dropFirst(WikiLinks.urlScheme.count + 1))
                model.openPage(named: name.removingPercentEncoding ?? name, from: document.url)
                return .handled
            }
            // Links to other markdown files open inside Blad.
            guard url.isFileURL, FileNode.isMarkdown(url) else { return .systemAction }
            model.openItem(url)
            return .handled
        })
        .task(id: document.isReading) {
            guard document.isReading else { return }
            backlinks = await model.backlinks(to: document)
        }
    }

    private var style: EditorStyle {
        EditorStyle(
            theme: theme,
            fontID: fontID,
            fontSize: fontSize,
            lineWidth: lineWidth,
            focusMode: model.isFocusMode,
            dimsParagraphs: dimParagraphs,
            typewriterScrolling: typewriter,
            checksSpelling: spellCheck
        )
    }
}

/// Word count and the source/reading switch, bottom right.
private struct StatusBar: View {
    let document: DocumentModel
    let showsWordCount: Bool
    let isFocusMode: Bool

    @State private var isHovering = false
    @Namespace private var selection

    var body: some View {
        let isQuiet = isFocusMode && !isHovering

        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if showsWordCount {
                    wordCount
                        .glassEffect(isQuiet ? .identity : .regular, in: .capsule)
                }
                modeSwitch
                    .glassEffect(isQuiet ? .identity : .regular, in: .capsule)
            }
        }
        .opacity(isQuiet ? 0.45 : 1)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.25)) { isHovering = hovering }
        }
    }

    private var wordCount: some View {
        let words = document.wordCount
        return HStack(spacing: 6) {
            Text(words == 1 ? "1 woord" : "\(words.formatted()) woorden")
            if isHovering {
                Text("·").foregroundStyle(.tertiary)
                Text("\(max(1, Int((Double(words) / 230).rounded(.up)))) min lezen")
                Text("·").foregroundStyle(.tertiary)
                Text("\(document.text.count.formatted()) tekens")
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton(reading: false, symbol: "chevron.left.forwardslash.chevron.right", help: "Bewerk de bron (⌘R)")
            modeButton(reading: true, symbol: "book", help: "Leesmodus (⌘R)")
        }
        .padding(3)
        .frame(height: 28)
        .animation(.smooth(duration: 0.3), value: document.isReading)
    }

    private func modeButton(reading: Bool, symbol: String, help: String) -> some View {
        let isSelected = document.isReading == reading
        return Button {
            document.isReading = reading
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 30, height: 22)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.primary.opacity(0.08))
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
