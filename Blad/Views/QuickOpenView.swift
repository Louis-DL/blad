import SwiftUI

/// ⌘K: find a page by name or contents and open it.
struct QuickOpenOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { model.isQuickOpenPresented = false }
            QuickOpenView()
                .padding(.top, 80)
                .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}

private struct QuickOpenView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var entries: [SearchEntry] = []
    @State private var selection = 0
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        let results = SearchIndex.search(query, in: entries)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Zoek of open een pagina", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($isSearchFieldFocused)
                    .onSubmit { open(results, at: selection) }
                    .onKeyPress(.downArrow) {
                        selection = min(selection + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selection = max(selection - 1, 0)
                        return .handled
                    }
                    .onExitCommand { model.isQuickOpenPresented = false }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)

            if !results.isEmpty {
                Divider().opacity(0.6)
                ScrollViewReader { proxy in
                    ViewThatFits(in: .vertical) {
                        resultList(results)
                        ScrollView { resultList(results) }
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selection) { _, index in
                        proxy.scrollTo(index)
                    }
                }
            } else if !query.isEmpty && !entries.isEmpty {
                Divider().opacity(0.6)
                Text("Niets gevonden voor “\(query)”")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 22)
            }
        }
        .frame(maxWidth: 620)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .onChange(of: query) { selection = 0 }
        .task {
            // Clicking a #tag opens this list with that tag filled in.
            query = model.quickOpenQuery
            model.quickOpenQuery = ""
            isSearchFieldFocused = true
            entries = await model.buildSearchIndex()
        }
    }

    private func resultList(_ results: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Recent gewijzigd")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { entry in
                ResultRow(result: entry.element, query: query, isSelected: entry.offset == selection)
                    .id(entry.offset)
                    .onTapGesture { open(results, at: entry.offset) }
                    .onHover { hovering in
                        if hovering { selection = entry.offset }
                    }
            }
        }
        .padding(8)
    }

    private func open(_ results: [SearchResult], at index: Int) {
        guard results.indices.contains(index) else { return }
        model.isQuickOpenPresented = false
        model.openItem(results[index].entry.url)
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 15))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(highlighted(result.entry.title))
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(result.entry.location)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let snippet = result.snippet {
                    Text(highlighted(snippet))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.07))
            }
        }
        .contentShape(.rect)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, let range = attributed.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].foregroundColor = .accentColor
        }
        return attributed
    }
}
