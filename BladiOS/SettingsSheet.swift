import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @AppStorage(Pref.theme) private var themeID: ThemeID = .paper
    @AppStorage(Pref.paperGrain) private var paperGrain = true
    @AppStorage(Pref.font) private var fontID = EditorFont.defaultID
    @AppStorage(Pref.fontSize) private var fontSize = Pref.defaultFontSize
    @AppStorage(Pref.showWordCount) private var showWordCount = true
    @AppStorage(Pref.spellCheck) private var spellCheck = true
    @AppStorage(Pref.sortOrder) private var sortOrder: FileSort = .name

    var body: some View {
        NavigationStack {
            Form {
                Section("Thema") {
                    HStack(spacing: 10) {
                        ForEach(ThemeID.allCases) { id in
                            Button {
                                themeID = id
                            } label: {
                                ThemeSwatch(id: id, isSelected: id == themeID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    Toggle("Papierstructuur", isOn: $paperGrain)
                        .disabled(themeID == .light || themeID == .night)
                }

                Section("Tekst") {
                    Picker("Lettertype", selection: $fontID) {
                        ForEach(EditorFont.presets, id: \.id) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                        Section("Geïnstalleerd") {
                            ForEach(EditorFont.installedFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Stepper(value: $fontSize, in: 13...28, step: 1) {
                        LabeledContent("Grootte", value: "\(Int(fontSize)) pt")
                    }

                    Toggle("Spellingcontrole", isOn: $spellCheck)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Een rustige plek")
                            .font(Font(EditorFont.font(id: fontID, size: fontSize * 1.3, weight: .semibold) as CTFont))
                        Text("Schrijf zonder afleiding. De markdown blijft zichtbaar, maar stil.")
                            .font(Font(EditorFont.font(id: fontID, size: fontSize) as CTFont))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Pagina's") {
                    Picker("Sorteer op", selection: $sortOrder) {
                        ForEach(FileSort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    Toggle("Woordentelling", isOn: $showWordCount)
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .onChange(of: sortOrder) {
                library.refreshAll()
            }
        }
    }
}

private struct ThemeSwatch: View {
    let id: ThemeID
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                }
            Text(id.label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var preview: some View {
        switch id {
        case .paper: sample(.paper)
        case .light: sample(.light)
        case .night: sample(.night)
        case .system:
            HStack(spacing: 0) {
                sample(.paper)
                sample(.night)
            }
        }
    }

    private func sample(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aa")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Color(platform: theme.text))
            Capsule().fill(Color(platform: theme.accent)).frame(width: 16, height: 3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(platform: theme.background))
    }
}
