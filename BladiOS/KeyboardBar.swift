import SwiftUI

/// The bar above the keyboard: the markdown you reach for most, one tap away.
struct KeyboardBar: View {
    static let height: CGFloat = 56

    let controller: EditorController
    let onPhoto: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    key("number", "Kopje") { controller.toggleHeading() }
                    key("bold", "Vet") { controller.toggleBold() }
                    key("italic", "Cursief") { controller.toggleItalic() }
                    key("checklist", "Taak") { controller.toggleTask() }
                    key("link", "Link naar een pagina") { controller.startLink() }
                    key("photo", "Foto") { onPhoto() }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
            .glassEffect(.regular, in: .capsule)

            Button {
                controller.dismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Verberg toetsenbord")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: Self.height)
    }

    private func key(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}
