import SwiftUI

/// What you see with no page open: three ways to start, and your recent pages.
struct WelcomeView: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    private let cardWidth: CGFloat = 188
    private let spacing: CGFloat = 14

    var body: some View {
        VStack(spacing: 44) {
            VStack(spacing: 10) {
                Text("Blad")
                    .font(.system(size: 60, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(nsColor: theme.text))
                Text("Een rustige plek voor notities en README's.")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Color(nsColor: theme.secondary))
            }

            GlassEffectContainer(spacing: spacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: spacing) { cards }
                    VStack(spacing: spacing) { cards }
                }
            }

            if !model.recentFiles.isEmpty {
                recents
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cards: some View {
        ActionCard(symbol: "square.and.pencil", title: "Nieuwe pagina", detail: "Begin meteen te schrijven", shortcut: "⌘N", width: cardWidth) {
            model.newPage()
        }
        ActionCard(symbol: "folder.badge.plus", title: "Nieuwe ruimte", detail: "Een map voor je notities", shortcut: "⇧⌘N", width: cardWidth) {
            model.createWorkspace()
        }
        ActionCard(symbol: "arrow.up.forward.square", title: "Openen", detail: "Een map of .md-bestand", shortcut: "⌘O", width: cardWidth) {
            model.showOpenPanel()
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)
                .padding(.bottom, 6)
            ForEach(model.recentFiles.prefix(5), id: \.self) { url in
                RecentRow(url: url) { model.openItem(url) }
            }
        }
        .frame(maxWidth: cardWidth * 3 + spacing * 2)
    }
}

private struct ActionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let shortcut: String
    let width: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 24)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(18)
            .frame(width: width, height: 136, alignment: .leading)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .scaleEffect(isHovering ? 1.025 : 1)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.25)) { isHovering = hovering }
        }
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                Spacer()
                Text(url.deletingLastPathComponent().lastPathComponent)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(isHovering ? 0.06 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
