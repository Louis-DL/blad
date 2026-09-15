import SwiftUI

struct TabBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(model.documents) { document in
                        TabButton(document: document, isActive: document.id == model.activeDocumentID)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

private struct TabButton: View {
    let document: DocumentModel
    let isActive: Bool

    @Environment(AppModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(document.title)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                model.close(document)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Sluit pagina")
        }
        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 28)
        .frame(maxWidth: 220)
        .background {
            if !isActive && isHovering {
                Capsule().fill(.primary.opacity(0.06))
            }
        }
        .glassEffect(isActive ? .regular.interactive() : .identity, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { model.activate(document) }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Sluit") { model.close(document) }
            Button("Sluit andere tabbladen") { model.closeOthers(than: document) }
                .disabled(model.documents.count < 2)
            Divider()
            Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([document.url]) }
        }
        .animation(.smooth(duration: 0.2), value: isActive)
    }
}
