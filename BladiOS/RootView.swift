import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(Pref.theme) private var themeID: ThemeID = .paper
    @State private var selection: URL?
    @State private var showsSettings = false
    @State private var isNamingSpace = false
    @State private var spaceName = ""
    @State private var isPickingFolder = false
    @State private var folderPurpose = FolderPurpose.existingFolder

    /// What the folder picker is open for.
    private enum FolderPurpose {
        /// Where a new space goes; Blad makes a folder with this name there.
        case newSpace(name: String)
        /// A folder that already holds pages, like a project with its README's.
        case existingFolder
    }

    var body: some View {
        let theme = Theme.resolve(themeID, scheme: systemScheme)

        NavigationSplitView {
            PagesList(
                selection: $selection,
                showsSettings: $showsSettings,
                onNewSpace: beginNewSpace,
                onOpenFolder: openExistingFolder
            )
        } detail: {
            if let selection, let document = library.document(for: selection) {
                PageScreen(document: document, theme: theme, onOpenPage: { self.selection = $0 })
                    .id(document.id)
            } else {
                StartView(theme: theme, onNewSpace: beginNewSpace, onOpenFolder: openExistingFolder) {
                    selection = library.newPage()
                }
            }
        }
        .tint(Color(platform: theme.accent))
        .preferredColorScheme(themeID.colorScheme)
        .alert("Nieuwe ruimte", isPresented: $isNamingSpace) {
            TextField("Bv. Wiskunde of Blad-app", text: $spaceName)
            Button("Kies een plek") {
                let name = spaceName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                folderPurpose = .newSpace(name: name)
                Task {
                    // Let the alert finish closing before the Files picker slides in.
                    try? await Task.sleep(for: .milliseconds(350))
                    isPickingFolder = true
                }
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("Een ruimte houdt de pagina's van één project of vak bij elkaar. Kies daarna waar ze komt, bijvoorbeeld in iCloud Drive.")
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            switch folderPurpose {
            case .newSpace(let name):
                library.createSpace(named: name, in: url)
            case .existingFolder:
                library.addSpace(url)
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheet()
        }
        .onChange(of: library.lastRename) { _, rename in
            if let rename, selection == rename.from { selection = rename.to }
        }
        .alert("Er ging iets mis", isPresented: hasError) {
            Button("OK") { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private func beginNewSpace() {
        spaceName = ""
        isNamingSpace = true
    }

    private func openExistingFolder() {
        folderPurpose = .existingFolder
        isPickingFolder = true
    }

    private var hasError: Binding<Bool> {
        Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })
    }
}

/// Spaces and their pages, or search results while searching.
private struct PagesList: View {
    @Binding var selection: URL?
    @Binding var showsSettings: Bool
    let onNewSpace: () -> Void
    let onOpenFolder: () -> Void

    @Environment(Library.self) private var library
    @State private var query = ""
    @State private var entries: [SearchEntry] = []
    @State private var renaming: URL?
    @State private var newName = ""
    @State private var deleting: URL?

    var body: some View {
        List(selection: $selection) {
            if query.isEmpty {
                if library.spaces.isEmpty {
                    emptyState
                }
                ForEach(library.spaces) { space in
                    Section {
                        OutlineGroup(library.trees[space.url] ?? [], children: \.children) { node in
                            row(node)
                        }
                    } header: {
                        spaceHeader(space)
                    }
                }
            } else {
                searchResults
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Blad")
        .searchable(text: $query, prompt: "Zoek in je pagina's")
        .task(id: query.isEmpty) {
            if !query.isEmpty { entries = await library.buildSearchIndex() }
        }
        .refreshable { library.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsSettings = true
                } label: {
                    Label("Instellingen", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Nieuwe pagina", systemImage: "square.and.pencil") {
                        selection = library.newPage(in: targetFolder)
                    }
                    .keyboardShortcut("n")
                    .disabled(library.spaces.isEmpty)
                    Button("Nieuwe ruimte…", systemImage: "plus.square.on.square", action: onNewSpace)
                    Button("Open een bestaande map…", systemImage: "folder", action: onOpenFolder)
                } label: {
                    Label("Nieuw", systemImage: "plus")
                }
            }
        }
        .alert("Wijzig naam", isPresented: isRenaming) {
            TextField("Naam", text: $newName)
            Button("Wijzig naam") {
                if let renaming, let renamed = library.rename(renaming, to: newName), selection == renaming {
                    selection = renamed
                }
            }
            Button("Annuleer", role: .cancel) {}
        }
        .confirmationDialog("Verwijder deze pagina?", isPresented: isDeleting, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) {
                if let deleting {
                    if selection == deleting { selection = nil }
                    library.delete(deleting)
                }
            }
        } message: {
            Text("Staat de pagina in iCloud Drive, dan vind je ze terug bij Recent verwijderd in Bestanden.")
        }
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label("Nog geen ruimte", systemImage: "square.stack")
            } description: {
                Text("Maak een ruimte per project of vak. Bewaar ze in iCloud Drive om ze ook op je Mac te hebben.")
            } actions: {
                Button("Nieuwe ruimte", action: onNewSpace)
                    .buttonStyle(.glassProminent)
                Button("Open een bestaande map", action: onOpenFolder)
                    .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder
    private func row(_ node: FileNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .contextMenu {
                    Button("Nieuwe pagina hier", systemImage: "square.and.pencil") {
                        selection = library.newPage(in: node.url)
                    }
                    Button("Wijzig naam", systemImage: "pencil") { beginRename(node.url) }
                }
        } else {
            Label(node.name, systemImage: "doc.text")
                .tag(node.url)
                .contextMenu {
                    Button("Wijzig naam", systemImage: "pencil") { beginRename(node.url) }
                    Button("Verwijder", systemImage: "trash", role: .destructive) { deleting = node.url }
                }
                .swipeActions {
                    Button("Verwijder", systemImage: "trash", role: .destructive) { deleting = node.url }
                }
        }
    }

    private func spaceHeader(_ space: Library.Space) -> some View {
        HStack {
            Text(space.name)
            Spacer()
            Menu {
                Button("Nieuwe pagina", systemImage: "square.and.pencil") {
                    selection = library.newPage(in: space.url)
                }
                Button("Verwijder uit Blad", systemImage: "minus.circle", role: .destructive) {
                    library.removeSpace(space)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var searchResults: some View {
        ForEach(SearchIndex.search(query, in: entries)) { result in
            VStack(alignment: .leading, spacing: 3) {
                Text(result.entry.title)
                    .font(.body.weight(.medium))
                Text(result.snippet ?? result.entry.location)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .tag(result.entry.url)
        }
    }

    /// New pages go next to the open page, or into the first space.
    private var targetFolder: URL? {
        if let selection, library.space(containing: selection) != nil {
            return selection.deletingLastPathComponent()
        }
        return library.spaces.first?.url
    }

    private func beginRename(_ url: URL) {
        newName = url.deletingPathExtension().lastPathComponent
        renaming = url
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

/// Shown next to the list on iPad when no page is open.
private struct StartView: View {
    let theme: Theme
    let onNewSpace: () -> Void
    let onOpenFolder: () -> Void
    let onNewPage: () -> Void

    @Environment(Library.self) private var library
    @AppStorage(Pref.paperGrain) private var paperGrain = true

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("Blad")
                    .font(.system(size: 54, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(platform: theme.text))
                Text("Een rustige plek voor notities en README's.")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(Color(platform: theme.secondary))
                    .multilineTextAlignment(.center)
            }

            if library.spaces.isEmpty {
                VStack(spacing: 12) {
                    Button(action: onNewSpace) {
                        Label("Nieuwe ruimte", systemImage: "plus.square.on.square")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    Button(action: onOpenFolder) {
                        Label("Open een bestaande map", systemImage: "folder")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    Text("Een ruimte per project of vak. In iCloud Drive heb je ze ook op je Mac.")
                        .font(.footnote)
                        .foregroundStyle(Color(platform: theme.secondary))
                        .multilineTextAlignment(.center)
                }
            } else {
                Button(action: onNewPage) {
                    Label("Nieuwe pagina", systemImage: "square.and.pencil")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PaperBackground(theme: theme, showsGrain: paperGrain)
                .ignoresSafeArea()
        }
    }
}
