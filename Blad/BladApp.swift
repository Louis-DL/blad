import SwiftUI

@main
struct BladApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Blad", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 520, minHeight: 360)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            TextEditingCommands()
            BladCommands(model: model)
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveAll()
    }
}

struct BladCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nieuwe pagina") { model.newPage() }
                .keyboardShortcut("n")
            Button("Nieuwe ruimte…") { model.createWorkspace() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Openen…") { model.showOpenPanel() }
                .keyboardShortcut("o")
            Button("Zoek en open…") { model.isQuickOpenPresented.toggle() }
                .keyboardShortcut("k")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Sluit pagina") { model.closeActivePage() }
                .keyboardShortcut("w")
            Button("Bewaar") { model.activeDocument?.save() }
                .keyboardShortcut("s")
        }

        CommandGroup(replacing: .importExport) {
            Button("Exporteer als PDF…") { model.exportActiveDocument(as: .pdf) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.activeDocument == nil)
            Button("Exporteer als HTML…") { model.exportActiveDocument(as: .html) }
                .disabled(model.activeDocument == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Voeg afbeelding in…") {
                NSApp.sendAction(#selector(EditorTextView.insertImageFromFile(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(model.activeDocument == nil || model.activeDocument?.isReading == true)
        }

        CommandGroup(after: .sidebar) {
            Button(model.isFocusMode ? "Verlaat focusmodus" : "Focusmodus") { model.toggleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button(model.activeDocument?.isReading == true ? "Bewerk bron" : "Leesmodus") {
                model.activeDocument?.isReading.toggle()
            }
            .keyboardShortcut("r")
            .disabled(model.activeDocument == nil)
            Divider()
            Button("Grotere tekst") { adjustFontSize(by: 1) }
                .keyboardShortcut("+")
            Button("Kleinere tekst") { adjustFontSize(by: -1) }
                .keyboardShortcut("-")
            Button("Standaardgrootte") { UserDefaults.standard.removeObject(forKey: Pref.fontSize) }
                .keyboardShortcut("0")
            Divider()
            Button("Vorig tabblad") { model.selectTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Volgend tabblad") { model.selectTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Divider()
            Menu("Sorteer pagina's") {
                ForEach(FileSort.allCases) { sort in
                    Button(sort.label) { UserDefaults.standard.set(sort.rawValue, forKey: Pref.sortOrder) }
                }
            }
        }
    }

    private func adjustFontSize(by delta: Double) {
        let defaults = UserDefaults.standard
        let current = defaults.object(forKey: Pref.fontSize) as? Double ?? Pref.defaultFontSize
        defaults.set(min(28, max(12, current + delta)), forKey: Pref.fontSize)
    }
}
