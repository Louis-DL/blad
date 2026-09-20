import SwiftUI
import Combine

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(Pref.theme) private var themeID: ThemeID = .paper

    var body: some View {
        @Bindable var model = model
        let theme = Theme.resolve(themeID, scheme: systemScheme)

        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 380)
        } detail: {
            DetailView(theme: theme)
        }
        .preferredColorScheme(themeID.colorScheme)
        .tint(Color(nsColor: theme.accent))
        .overlay {
            if model.isQuickOpenPresented {
                QuickOpenOverlay()
            }
        }
        .animation(.smooth(duration: 0.2), value: model.isQuickOpenPresented)
        .alert("Wijzig naam", isPresented: isRenaming) {
            TextField("Naam", text: $model.renameText)
            Button("Wijzig naam") { model.commitRename() }
            Button("Annuleer", role: .cancel) { model.renameTarget = nil }
        }
        .alert("Er ging iets mis", isPresented: hasError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(model.openItem)
            return !urls.isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadFromDisk()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.saveAll()
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { model.renameTarget != nil }, set: { if !$0 { model.renameTarget = nil } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

struct DetailView: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.showTabs) private var showTabs = true
    @AppStorage(Pref.paperGrain) private var paperGrain = true

    private var showsTabBar: Bool {
        showTabs && !model.documents.isEmpty && !model.isFocusMode
    }

    var body: some View {
        Group {
            if let document = model.activeDocument {
                EditorScreen(document: document, theme: theme)
                    .id(document.id)
            } else {
                WelcomeView(theme: theme)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsTabBar {
                TabBarView()
                    .transition(.opacity)
            }
        }
        .background {
            PaperBackground(theme: theme, showsGrain: paperGrain)
                .backgroundExtensionEffect()
                .ignoresSafeArea()
        }
        .navigationTitle(model.activeDocument?.title ?? "Blad")
        .navigationSubtitle(subtitle)
        .toolbar(removing: showsTabBar ? ToolbarDefaultItemKind.title : nil)
        .toolbar { toolbarContent }
        .toolbar(model.isFocusMode ? .hidden : .automatic, for: .windowToolbar)
        .animation(.smooth(duration: 0.3), value: showsTabBar)
    }

    private var subtitle: String {
        guard let document = model.activeDocument else { return "" }
        return model.workspace(containing: document.url)?.lastPathComponent ?? ""
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarSpacer(.flexible)

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.isQuickOpenPresented = true
            } label: {
                Label("Zoek", systemImage: "magnifyingglass")
            }
            .help("Zoek en open (⌘K)")

            Menu {
                Button("Nieuwe pagina", systemImage: "square.and.pencil") { model.newPage() }
                Button("Nieuwe ruimte…", systemImage: "plus.square.on.square") { model.createWorkspace() }
                Divider()
                Button("Openen…", systemImage: "folder") { model.showOpenPanel() }
            } label: {
                Label("Nieuw", systemImage: "plus")
            }
            .menuIndicator(.hidden)
            .help("Nieuwe pagina, nieuwe ruimte of openen")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.isOutlinePresented.toggle()
            } label: {
                Label("Overzicht", systemImage: "list.bullet.indent")
            }
            .disabled(model.activeDocument == nil)
            .help("Kopjes van deze pagina (⇧⌘O)")
            .popover(
                isPresented: Binding(get: { model.isOutlinePresented }, set: { model.isOutlinePresented = $0 }),
                arrowEdge: .bottom
            ) {
                OutlineList(headings: model.activeDocument?.headings ?? []) { heading in
                    model.activeDocument?.jump = Jump(offset: heading.offset, heading: heading.id)
                    model.isOutlinePresented = false
                }
                .frame(width: 280, height: 360)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggleFocus()
            } label: {
                Label("Focusmodus", systemImage: "scope")
            }
            .disabled(model.activeDocument == nil)
            .help("Focusmodus (⇧⌘F)")
        }
    }
}
