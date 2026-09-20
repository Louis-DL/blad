import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Pref.sortOrder) private var sortOrder: FileSort = .name

    var body: some View {
        @Bindable var model = model

        List(selection: $model.sidebarSelection) {
            ForEach(model.workspaces, id: \.self) { workspace in
                Section(isExpanded: expansion(for: workspace)) {
                    OutlineGroup(model.trees[workspace] ?? [], children: \.children) { node in
                        FileRow(node: node)
                            .tag(node.url)
                    }
                } header: {
                    WorkspaceHeader(workspace: workspace, sortOrder: $sortOrder)
                }
            }

            if !model.looseFiles.isEmpty {
                Section("Losse pagina's") {
                    ForEach(model.looseFiles, id: \.self) { url in
                        Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.text")
                            .tag(url)
                            .contextMenu {
                                Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button("Verwijder uit zijbalk") { model.removeLooseFile(url) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.workspaces.isEmpty && model.looseFiles.isEmpty {
                EmptySidebar()
            }
        }
        .onChange(of: model.sidebarSelection) { _, selection in
            guard let selection, FileNode.isMarkdown(selection) else { return }
            model.open(selection)
        }
        .onChange(of: sortOrder) {
            model.refreshAllTrees()
        }
    }

    private func expansion(for workspace: URL) -> Binding<Bool> {
        Binding(
            get: { !model.collapsedWorkspaces.contains(workspace) },
            set: { isExpanded in
                if isExpanded {
                    model.collapsedWorkspaces.remove(workspace)
                } else {
                    model.collapsedWorkspaces.insert(workspace)
                }
            }
        )
    }
}

private struct WorkspaceHeader: View {
    let workspace: URL
    @Binding var sortOrder: FileSort

    @Environment(AppModel.self) private var model
    @State private var isDropTarget = false

    var body: some View {
        Text(workspace.lastPathComponent)
            .padding(.horizontal, 4)
            .background {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.2))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.moveItems(urls, into: workspace)
            } isTargeted: {
                isDropTarget = $0
            }
            .contextMenu {
                Button("Nieuwe pagina") { model.newPage(in: workspace) }
                Button("Nieuwe map") { model.newFolder(in: workspace) }
                Divider()
                Picker("Sorteer op", selection: $sortOrder) {
                    ForEach(FileSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                Divider()
                Button("Exporteer ruimte als PDF…") { model.exportWorkspace(workspace) }
                Divider()
                Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace]) }
                Button("Verwijder uit zijbalk") { model.removeWorkspace(workspace) }
            }
    }
}

private struct FileRow: View {
    let node: FileNode
    @Environment(AppModel.self) private var model
    @State private var isDropTarget = false

    var body: some View {
        Label(node.name, systemImage: icon)
            .draggable(node.url)
            .modifier(FolderDropTarget(folder: node.isDirectory ? node.url : nil, isTargeted: $isDropTarget))
            .contextMenu {
                if node.isDirectory {
                    Button("Nieuwe pagina") { model.newPage(in: node.url) }
                    Button("Nieuwe map") { model.newFolder(in: node.url) }
                    Divider()
                } else {
                    Button("Dupliceer") { model.duplicate(node.url) }
                }
                Button("Wijzig naam…") { model.beginRename(node.url) }
                Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                Divider()
                Button("Verplaats naar prullenmand", role: .destructive) { model.moveToTrash(node.url) }
            }
    }

    private var icon: String {
        guard node.isDirectory else { return "doc.text" }
        return isDropTarget ? "folder.fill" : "folder"
    }
}

/// Lets pages and folders be dropped onto a folder row.
private struct FolderDropTarget: ViewModifier {
    let folder: URL?
    @Binding var isTargeted: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if let folder {
            content.dropDestination(for: URL.self) { urls, _ in
                model.moveItems(urls, into: folder)
            } isTargeted: {
                isTargeted = $0
            }
        } else {
            content
        }
    }
}

private struct EmptySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Nog geen ruimtes", systemImage: "square.stack")
        } description: {
            Text("Maak een ruimte per project of vak, of open een bestaande map.")
        } actions: {
            Button("Nieuwe ruimte") { model.createWorkspace() }
                .buttonStyle(.glassProminent)
            Button("Openen…") { model.showOpenPanel() }
                .buttonStyle(.glass)
        }
    }
}
