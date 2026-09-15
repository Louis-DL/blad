import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Weergave", systemImage: "paintbrush") {
                AppearanceSettings()
            }
            Tab("Indeling", systemImage: "sidebar.left") {
                LayoutSettings()
            }
            Tab("Focus", systemImage: "scope") {
                FocusSettings()
            }
        }
        .frame(width: 520)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Pref.theme) private var themeID: ThemeID = .paper
    @AppStorage(Pref.paperGrain) private var paperGrain = true
    @AppStorage(Pref.font) private var fontID = EditorFont.defaultID
    @AppStorage(Pref.fontSize) private var fontSize = Pref.defaultFontSize
    @AppStorage(Pref.lineWidth) private var lineWidth = Pref.defaultLineWidth

    var body: some View {
        Form {
            Section("Thema") {
                HStack(spacing: 14) {
                    ForEach(ThemeID.allCases) { id in
                        ThemeSwatch(id: id, isSelected: id == themeID)
                            .onTapGesture { themeID = id }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                Toggle("Papierstructuur", isOn: $paperGrain)
                    .disabled(themeID == .light || themeID == .night)
            }

            Section("Tekst") {
                Picker("Lettertype", selection: $fontID) {
                    ForEach(EditorFont.presets, id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    Divider()
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                LabeledContent("Grootte") {
                    HStack {
                        Slider(value: $fontSize, in: 12...28, step: 1)
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                LabeledContent("Regelbreedte") {
                    Slider(value: $lineWidth, in: 480...1000, step: 20) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "arrow.right.and.line.vertical.and.arrow.left").foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "arrow.left.and.line.vertical.and.arrow.right").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Voorbeeld") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Een rustige plek")
                        .font(Font(EditorFont.font(id: fontID, size: fontSize * 1.4, weight: .semibold)))
                    Text("Schrijf zonder afleiding. De markdown blijft zichtbaar, maar stil.")
                        .font(Font(EditorFont.font(id: fontID, size: fontSize)))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let id: ThemeID
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            preview
                .frame(width: 92, height: 62)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                }
            Text(id.label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
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
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(Color(nsColor: theme.text))
            Capsule().fill(Color(nsColor: theme.accent)).frame(width: 20, height: 3)
            Capsule().fill(Color(nsColor: theme.secondary).opacity(0.6)).frame(width: 30, height: 3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: theme.background))
    }
}

private struct LayoutSettings: View {
    @AppStorage(Pref.showTabs) private var showTabs = true
    @AppStorage(Pref.showSidebar) private var showSidebar = true
    @AppStorage(Pref.showWordCount) private var showWordCount = true

    var body: some View {
        Form {
            Section {
                Toggle("Tabbladen", isOn: $showTabs)
                Text("Zonder tabbladen vervangt een geopende pagina de huidige.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Toon de zijbalk bij het openen", isOn: $showSidebar)
                Toggle("Woordentelling", isOn: $showWordCount)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FocusSettings: View {
    @AppStorage(Pref.dimParagraphs) private var dimParagraphs = true
    @AppStorage(Pref.typewriter) private var typewriter = true

    var body: some View {
        Form {
            Section {
                Toggle("Dim alles behalve de alinea waarin je schrijft", isOn: $dimParagraphs)
                Toggle("Typemachine: de regel waarin je typt blijft in het midden", isOn: $typewriter)
            } footer: {
                Text("Start focusmodus met ⇧⌘F. Stop met Esc.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
