import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Workspaces, open pages and everything that happens to files.
/// A workspace ("ruimte") is just a folder on disk, so notes stay plain `.md` files
/// that sync through iCloud Drive or git like any other file.
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var workspaces: [URL] = []
    private(set) var looseFiles: [URL] = []
    private(set) var trees: [URL: [FileNode]] = [:]
    private(set) var recentFiles: [URL] = []
    var collapsedWorkspaces: Set<URL> = []

    private(set) var documents: [DocumentModel] = []
    private(set) var activeDocumentID: DocumentModel.ID?
    var sidebarSelection: URL?

    var columnVisibility: NavigationSplitViewVisibility
    private(set) var isFocusMode = false
    @ObservationIgnored private var visibilityBeforeFocus: NavigationSplitViewVisibility = .all

    var renameTarget: URL?
    var renameText = ""
    var errorMessage: String?
    var isQuickOpenPresented = false

    var activeDocument: DocumentModel? {
        documents.first { $0.id == activeDocumentID }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let workspaces = "workspaces"
        static let looseFiles = "looseFiles"
        static let recentFiles = "recentFiles"
        static let openTabs = "openTabs"
        static let activeTab = "activeTab"
    }

    private init() {
        let showSidebar = UserDefaults.standard.object(forKey: Pref.showSidebar) as? Bool ?? true
        columnVisibility = showSidebar ? .all : .detailOnly
        restore()
    }

    // MARK: - Pages and tabs

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        if let existing = documents.first(where: { $0.url == url }) {
            activate(existing)
            return
        }

        let document: DocumentModel
        do {
            document = try DocumentModel(url: url)
        } catch {
            present(error, "Kon \(url.lastPathComponent) niet openen")
            return
        }
        document.onSave = { [weak self] in self?.documentDidSave($0) }

        let showTabs = defaults.object(forKey: Pref.showTabs) as? Bool ?? true
        var index = documents.count
        if let active = activeDocument, let activeIndex = documents.firstIndex(where: { $0.id == active.id }) {
            if showTabs {
                index = activeIndex + 1
            } else {
                active.save()
                documents.remove(at: activeIndex)
                index = activeIndex
            }
        }
        documents.insert(document, at: index)
        activate(document)
        noteRecent(url)
    }

    /// Opens whatever came from the open panel, a drop, or the recent list.
    func openItem(_ url: URL) {
        let url = url.standardizedFileURL
        if isDirectory(url) {
            addWorkspace(url)
        } else {
            if workspace(containing: url) == nil { addLooseFile(url) }
            open(url)
        }
    }

    func activate(_ document: DocumentModel) {
        activeDocumentID = document.id
        if sidebarSelection != document.url { sidebarSelection = document.url }
        persistSession()
    }

    func close(_ document: DocumentModel) {
        document.save()
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents.remove(at: index)
        if activeDocumentID == document.id {
            let next = documents.indices.contains(index) ? documents[index] : documents.last
            activeDocumentID = next?.id
            sidebarSelection = next?.url
        }
        if documents.isEmpty, isFocusMode { toggleFocus() }
        persistSession()
    }

    func closeOthers(than document: DocumentModel) {
        for other in documents where other.id != document.id { other.save() }
        documents = [document]
        activate(document)
    }

    /// ⌘W closes the current page; with no page open (or in Instellingen) it closes the window.
    func closeActivePage() {
        let keyWindow = NSApp.keyWindow
        let isSettings = keyWindow?.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false
        if !isSettings, let document = activeDocument {
            close(document)
        } else {
            keyWindow?.performClose(nil)
        }
    }

    func selectTab(offset: Int) {
        guard documents.count > 1,
              let index = documents.firstIndex(where: { $0.id == activeDocumentID }) else { return }
        activate(documents[(index + offset + documents.count) % documents.count])
    }

    func saveAll() {
        documents.forEach { $0.save() }
    }

    func reloadFromDisk() {
        documents.forEach { $0.reloadFromDisk() }
        refreshAllTrees()
    }

    func toggleFocus() {
        guard isFocusMode || activeDocument != nil else { return }
        withAnimation(.smooth(duration: 0.4)) {
            if isFocusMode {
                columnVisibility = visibilityBeforeFocus
            } else {
                visibilityBeforeFocus = columnVisibility
                columnVisibility = .detailOnly
            }
            isFocusMode.toggle()
        }
    }

    // MARK: - Creating

    func newPage(in folder: URL? = nil) {
        guard let folder = folder ?? defaultFolderForNewPage() else {
            newPageWithPanel()
            return
        }
        let url = uniqueURL(in: folder, base: "Naamloos", pathExtension: "md")
        do {
            try Data().write(to: url)
        } catch {
            present(error, "Kon geen nieuwe pagina maken")
            return
        }
        refreshTree(containing: url)
        open(url)
        activeDocument?.namesItselfFromHeading = true
    }

    func createWorkspace() {
        let panel = NSSavePanel()
        panel.title = "Nieuwe ruimte"
        panel.message = "Een ruimte houdt de pagina's van één project of vak bij elkaar. Kies iCloud Drive om ze ook op je iPhone te hebben."
        panel.prompt = "Maak aan"
        panel.nameFieldLabel = "Naam:"
        panel.nameFieldStringValue = "Nieuwe ruimte"
        panel.canCreateDirectories = true
        panel.directoryURL = documentsFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            present(error, "Kon de ruimte niet maken")
            return
        }
        addWorkspace(url)
        newPage(in: url.standardizedFileURL)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Openen"
        panel.message = "Kies een map om als ruimte te gebruiken, of markdown-bestanden."
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.markdownFile, .plainText]
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(openItem)
    }

    func newFolder(in parent: URL) {
        let url = uniqueURL(in: parent, base: "Nieuwe map", pathExtension: nil)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            present(error, "Kon geen map maken")
            return
        }
        refreshTree(containing: url)
        beginRename(url)
    }

    private func newPageWithPanel() {
        let panel = NSSavePanel()
        panel.title = "Nieuwe pagina"
        panel.prompt = "Maak aan"
        panel.nameFieldStringValue = "Naamloos.md"
        panel.allowedContentTypes = [.markdownFile]
        panel.directoryURL = documentsFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data().write(to: url)
        } catch {
            present(error, "Kon geen nieuwe pagina maken")
            return
        }
        addLooseFile(url)
        open(url)
    }

    private func defaultFolderForNewPage() -> URL? {
        if let selection = sidebarSelection, isDirectory(selection) { return selection }
        if let active = activeDocument, workspace(containing: active.url) != nil {
            return active.url.deletingLastPathComponent()
        }
        return workspaces.first
    }

    // MARK: - Workspaces and files

    func addWorkspace(_ url: URL) {
        let url = url.standardizedFileURL
        if !workspaces.contains(url) { workspaces.append(url) }
        refreshTree(url)
        persistSpaces()
    }

    func removeWorkspace(_ url: URL) {
        workspaces.removeAll { $0 == url }
        trees[url] = nil
        persistSpaces()
    }

    func addLooseFile(_ url: URL) {
        let url = url.standardizedFileURL
        guard !looseFiles.contains(url) else { return }
        looseFiles.append(url)
        persistSpaces()
    }

    func removeLooseFile(_ url: URL) {
        looseFiles.removeAll { $0 == url }
        persistSpaces()
    }

    func beginRename(_ url: URL) {
        renameText = isDirectory(url) ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        renameTarget = url
    }

    func commitRename() {
        guard let source = renameTarget else { return }
        renameTarget = nil
        let name = sanitizedFileName(renameText)
        guard !name.isEmpty else { return }
        var destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if !isDirectory(source) {
            destination.appendPathExtension(source.pathExtension.isEmpty ? "md" : source.pathExtension)
        }
        guard destination != source else { return }
        move(source, to: destination, keepsAutoNaming: false)
    }

    func moveToTrash(_ url: URL) {
        for document in documents where document.url == url || document.url.path.hasPrefix(url.path + "/") {
            close(document)
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            present(error, "Kon \(url.lastPathComponent) niet naar de prullenmand verplaatsen")
            return
        }
        removeLooseFile(url)
        if workspaces.contains(url) { removeWorkspace(url) }
        refreshTree(containing: url)
    }

    func workspace(containing url: URL) -> URL? {
        workspaces.first { url.path == $0.path || url.path.hasPrefix($0.path + "/") }
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    func refreshAllTrees() {
        for workspace in workspaces { refreshTree(workspace) }
    }

    private func refreshTree(_ workspace: URL) {
        let sort = FileSort(rawValue: defaults.string(forKey: Pref.sortOrder) ?? "") ?? .name
        Task {
            let nodes = await Task.detached(priority: .userInitiated) { FileNode.scan(workspace, sort: sort) }.value
            if trees[workspace] != nodes { trees[workspace] = nodes }
        }
    }

    func refreshTree(containing url: URL) {
        if let workspace = workspace(containing: url) { refreshTree(workspace) }
    }

    @discardableResult
    func move(_ source: URL, to destination: URL, keepsAutoNaming: Bool) -> Bool {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            present(error, "Kon de naam niet wijzigen")
            return false
        }
        for document in documents {
            if document.url == source {
                document.move(to: destination)
                if !keepsAutoNaming { document.namesItselfFromHeading = false }
            } else if document.url.path.hasPrefix(source.path + "/") {
                let rest = document.url.path.dropFirst(source.path.count)
                document.move(to: URL(fileURLWithPath: destination.path + rest))
            }
        }
        workspaces = workspaces.map { $0 == source ? destination : $0 }
        looseFiles = looseFiles.map { $0 == source ? destination : $0 }
        recentFiles = recentFiles.map { $0 == source ? destination : $0 }
        if sidebarSelection == source { sidebarSelection = destination }
        refreshTree(containing: destination)
        if workspace(containing: source) != workspace(containing: destination) {
            refreshTree(containing: source)
        }
        persistSpaces()
        persistSession()
        return true
    }

    private func documentDidSave(_ document: DocumentModel) {
        guard document.namesItselfFromHeading, let heading = firstHeading(in: document.text) else { return }
        let name = sanitizedFileName(heading)
        guard !name.isEmpty, name != document.title else { return }
        let destination = document.url.deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension("md")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        move(document.url, to: destination, keepsAutoNaming: true)
    }

    private func firstHeading(in text: String) -> String? {
        let firstLine = text.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }
        guard let line = firstLine?.trimmingCharacters(in: .whitespaces), line.hasPrefix("#") else { return nil }
        return line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
    }

    func sanitizedFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(80))
    }

    func uniqueURL(in folder: URL, base: String, pathExtension: String?) -> URL {
        var number = 1
        while true {
            var url = folder.appendingPathComponent(number == 1 ? base : "\(base) \(number)")
            if let pathExtension { url.appendPathExtension(pathExtension) }
            if !FileManager.default.fileExists(atPath: url.path) { return url.standardizedFileURL }
            number += 1
        }
    }

    private var documentsFolder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    func present(_ error: Error, _ message: String) {
        errorMessage = "\(message).\n\n\(error.localizedDescription)"
    }

    // MARK: - Persistence

    private func noteRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(8))
        defaults.set(recentFiles.map(\.path), forKey: Keys.recentFiles)
    }

    private func persistSpaces() {
        defaults.set(workspaces.map(\.path), forKey: Keys.workspaces)
        defaults.set(looseFiles.map(\.path), forKey: Keys.looseFiles)
        defaults.set(recentFiles.map(\.path), forKey: Keys.recentFiles)
    }

    private func persistSession() {
        defaults.set(documents.map(\.url.path), forKey: Keys.openTabs)
        defaults.set(activeDocument?.url.path, forKey: Keys.activeTab)
    }

    private func restore() {
        func urls(_ key: String) -> [URL] {
            (defaults.stringArray(forKey: key) ?? [])
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0).standardizedFileURL }
        }
        workspaces = urls(Keys.workspaces)
        looseFiles = urls(Keys.looseFiles)
        recentFiles = urls(Keys.recentFiles)

        for url in urls(Keys.openTabs) {
            guard let document = try? DocumentModel(url: url) else { continue }
            document.onSave = { [weak self] in self?.documentDidSave($0) }
            documents.append(document)
        }
        let activePath = defaults.string(forKey: Keys.activeTab)
        activeDocumentID = (documents.first { $0.url.path == activePath } ?? documents.first)?.id
        sidebarSelection = activeDocument?.url
        refreshAllTrees()
    }
}

extension UTType {
    static var markdownFile: UTType {
        UTType(filenameExtension: "md", conformingTo: .text) ?? .plainText
    }
}
