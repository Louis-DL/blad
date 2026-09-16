import SwiftUI

/// A page as offered in the link picker.
struct PageRef: Hashable {
    let title: String
    /// Workspace and folders, e.g. "Notities › School".
    let location: String
}

/// Opens after typing `[[`: type the title of a new page, or pick an existing one below.
struct LinkPicker: View {
    let pages: [PageRef]
    let theme: Theme
    let onPick: (String) -> Void
    /// `removesBracket` is true for backspace on the empty field, which also deletes a `[`.
    let onCancel: (_ removesBracket: Bool) -> Void
    let onFocusLost: () -> Void
    let onSizeChange: (CGSize) -> Void
    /// On iPhone and iPad the picker fills a sheet instead of floating as a card with keyboard hints.
    var fillsWidth = false

    /// Transparent space around the card, so its shadow isn't clipped.
    static let shadowRoom: CGFloat = 24

    @State private var query = ""
    /// -1 is the title field at the top; 0 and up are the pages below it.
    @State private var selection = -1
    @FocusState private var isFieldFocused: Bool

    private let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    private var accent: Color { Color(platform: theme.accent) }
    private var textColor: Color { Color(platform: theme.text) }
    private var secondary: Color { Color(platform: theme.secondary) }

    /// The typed title, without characters that would break the link.
    private var title: String {
        query.filter { !"[]|".contains($0) }.trimmingCharacters(in: .whitespaces)
    }

    private var matches: [PageRef] {
        guard !title.isEmpty else { return Array(pages.prefix(6)) }
        let prefixed = pages.filter { $0.title.range(of: title, options: matchOptions.union(.anchored)) != nil }
        let containing = pages.filter { !prefixed.contains($0) && $0.title.range(of: title, options: matchOptions) != nil }
        return Array((prefixed + containing).prefix(6))
    }

    private var pageExists: Bool {
        pages.contains { $0.title.compare(title, options: matchOptions) == .orderedSame }
    }

    var body: some View {
        let matches = self.matches

        VStack(spacing: 0) {
            titleField(matches: matches)
            if !matches.isEmpty {
                separator
                VStack(spacing: 2) {
                    ForEach(Array(matches.enumerated()), id: \.element) { entry in
                        pageRow(entry.element, isSelected: entry.offset == selection)
                            .onTapGesture { onPick(entry.element.title) }
                            .onHover { hovering in
                                if hovering { selection = entry.offset }
                            }
                    }
                }
                .padding(6)
            }
            if !fillsWidth {
                separator
                footer
            }
        }
        .frame(width: fillsWidth ? nil : 340)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .background(Color(platform: theme.background).mix(with: .white, by: theme.isDark ? 0.05 : 0.6))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(secondary.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(fillsWidth ? 0 : (theme.isDark ? 0.5 : 0.13)), radius: 20, y: 10)
        .padding(fillsWidth ? 16 : Self.shadowRoom)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .onChange(of: query) { selection = -1 }
        .onChange(of: isFieldFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { onFocusLost() }
        }
        .task {
            isFieldFocused = true
            // The first request can come before the view is fully in the window; ask once more.
            try? await Task.sleep(for: .milliseconds(60))
            isFieldFocused = true
        }
    }

    private func titleField(matches: [PageRef]) -> some View {
        HStack(spacing: 10) {
            Text("[[")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
            TextField("Titel van een nieuwe pagina", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(textColor)
                .focused($isFieldFocused)
                .onSubmit { submit(matches) }
                .onKeyPress(.downArrow) {
                    selection = min(selection + 1, matches.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(selection - 1, -1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    submit(matches)
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard query.isEmpty else { return .ignored }
                    onCancel(true)
                    return .handled
                }
                #if os(macOS)
                .onExitCommand { onCancel(false) }
                #endif

            if !title.isEmpty {
                Text(pageExists ? "Bestaat al" : "Nieuw")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(pageExists ? secondary : accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((pageExists ? secondary : accent).opacity(0.13), in: .capsule)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background {
            if selection == -1, !title.isEmpty {
                RoundedRectangle(cornerRadius: 9)
                    .fill(accent.opacity(0.08))
                    .padding(5)
            }
        }
    }

    private func pageRow(_ page: PageRef, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? accent : secondary)
                .frame(width: 18)
            Text(highlighted(page.title))
                .font(.system(size: 13.5))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(page.location)
                .font(.system(size: 11.5))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.1))
            }
        }
        .contentShape(.rect)
    }

    private var separator: some View {
        Rectangle()
            .fill(secondary.opacity(0.2))
            .frame(height: 1)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            keyHint("↑↓", "kies")
            keyHint("↩", "voeg link in")
            keyHint("esc", "sluit")
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(secondary.opacity(0.06))
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(secondary.opacity(0.4), lineWidth: 1)
                }
            Text(label)
        }
        .font(.system(size: 11))
        .foregroundStyle(secondary)
    }

    private func submit(_ matches: [PageRef]) {
        if matches.indices.contains(selection) {
            onPick(matches[selection].title)
        } else if !title.isEmpty {
            onPick(title)
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if !title.isEmpty, let range = attributed.range(of: title, options: matchOptions) {
            attributed[range].foregroundColor = accent
        }
        return attributed
    }
}
