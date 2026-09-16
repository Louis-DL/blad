import SwiftUI

/// Blad's files on iPhone and iPad. A space is a folder picked in the Files app and remembered
/// with a security-scoped bookmark, so notes can live in iCloud Drive next to the Mac's.
@Observable
final class Library {
    static let shared = Library()

    struct Space: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// A page moved to a new name; the open screen follows it.
    struct Rename: Equatable {
        let from: URL
        let to: URL
    }

    private(set) var spaces: [Space] = []
    private(set) var trees: [URL: [FileNode]] = [:]
    private(set) var lastRename: Rename?
    var errorMessage: String?

    @ObservationIgnored private var documents: [URL: DocumentModel] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    private let bookmarksKey = "spaceBookmarks"

    private init() {
        restore()
    }

    // MARK: - Spaces

    func addSpace(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Blad kreeg geen toegang tot \(url.lastPathComponent)."
            return
        }
        let url = url.standardizedFileURL
        guard !spaces.contains(where: { $0.url == url }) else { return }
        spaces.append(Space(url: url))
        persist()
        refresh(url)
    }

    func removeSpace(_ space: Space) {
        spaces.removeAll { $0 == space }
        trees[space.url] = nil
        space.url.stopAccessingSecurityScopedResource()
        persist()
    }

    func space(containing url: URL) -> Space? {
        spaces.first { url.path == $0.url.path || url.path.hasPrefix($0.url.path + "/") }
    }

    func refreshAll() {
        for space in spaces { refresh(space.url) }
        for document in documents.values { document.reloadFromDisk() }
    }

    func refresh(containing url: URL) {
        if let space = space(containing: url) { refresh(space.url) }
    }

    private func refresh(_ folder: URL) {
        let sort = FileSort(rawValue: defaults.string(forKey: Pref.sortOrder) ?? "") ?? .name
        Task {
            let nodes = await Task.detached(priority: .userInitiated) { () -> [FileNode] in
                Library.downloadPlaceholders(in: folder)
                return FileNode.scan(folder, sort: sort)
            }.value
            if trees[folder] != nodes { trees[folder] = nodes }
        }
    }

    /// iCloud Drive keeps files that aren't on this device yet as hidden `.name.icloud` placeholders.
    nonisolated private static func downloadPlaceholders(in folder: URL) {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            guard name.hasPrefix("."), name.hasSuffix(".icloud") else { continue }
            let original = url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
            try? FileManager.default.startDownloadingUbiquitousItem(at: original)
        }
    }

    // MARK: - Pages

    func document(for url: URL) -> DocumentModel? {
        if let document = documents[url] { return document }
        guard let document = try? DocumentModel(url: url) else { return nil }
        documents[url] = document
        return document
    }

    func saveAll() {
        documents.values.forEach { $0.save() }
    }

    /// A new, empty page. It takes its name from its first heading when you leave it.
    func newPage(in folder: URL? = nil) -> URL? {
        guard let folder = folder ?? spaces.first?.url else { return nil }
        let url = uniqueURL(in: folder, base: "Naamloos", pathExtension: "md")
        do {
            try Data().write(to: url)
        } catch {
            present(error, "Kon geen nieuwe pagina maken")
            return nil
        }
        refresh(containing: url)
        document(for: url)?.namesItselfFromHeading = true
        return url
    }

    /// Renames a new page after its first heading. Done when leaving the page, not while typing,
    /// so the keyboard never disappears mid-sentence.
    func finishEditing(_ document: DocumentModel) {
        document.save()
        guard document.namesItselfFromHeading, let heading = firstHeading(in: document.text) else { return }
        let name = sanitized(heading)
        guard !name.isEmpty, name != document.title else { return }
        let destination = document.url.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension("md")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        move(document.url, to: destination, keepsAutoNaming: true)
    }

    @discardableResult
    func rename(_ url: URL, to name: String) -> URL? {
        let clean = sanitized(name)
        guard !clean.isEmpty else { return nil }
        var destination = url.deletingLastPathComponent().appendingPathComponent(clean)
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if !isFolder {
            destination.appendPathExtension(url.pathExtension.isEmpty ? "md" : url.pathExtension)
        }
        guard destination != url else { return url }
        return move(url, to: destination, keepsAutoNaming: false) ? destination : nil
    }

    func delete(_ url: URL) {
        documents = documents.filter { $0.key != url && !$0.key.path.hasPrefix(url.path + "/") }
        do {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                // Not every location has a trash, "On My iPhone" for one.
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            present(error, "Kon \(url.lastPathComponent) niet verwijderen")
            return
        }
        refresh(containing: url)
    }

    @discardableResult
    private func move(_ source: URL, to destination: URL, keepsAutoNaming: Bool) -> Bool {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            present(error, "Kon de naam niet wijzigen")
            return false
        }
        for (url, document) in documents where url == source || url.path.hasPrefix(source.path + "/") {
            let moved = URL(fileURLWithPath: destination.path + url.path.dropFirst(source.path.count))
            document.move(to: moved)
            if url == source, !keepsAutoNaming { document.namesItselfFromHeading = false }
            documents[url] = nil
            documents[moved] = document
        }
        lastRename = Rename(from: source, to: destination)
        refresh(containing: destination)
        return true
    }

    // MARK: - Links and search

    /// Pages offered in the `[[` link picker, most recently changed first.
    var pageRefs: [PageRef] {
        var pages: [(ref: PageRef, modified: Date)] = []
        func walk(_ nodes: [FileNode], location: String) {
            for node in nodes {
                if node.isDirectory {
                    walk(node.children ?? [], location: location + " › " + node.name)
                } else {
                    pages.append((PageRef(title: node.name, location: location), node.modified ?? .distantPast))
                }
            }
        }
        for space in spaces {
            walk(trees[space.url] ?? [], location: space.name)
        }
        return pages.sorted { $0.modified > $1.modified }.map(\.ref)
    }

    /// The page a `[[link]]` points to, preferring the linking page's own space.
    /// A link to a page that doesn't exist yet creates it next to the linking page.
    func openPage(named name: String, from source: URL) -> URL? {
        let target = (name.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        guard !target.isEmpty else { return nil }

        func pages(in nodes: [FileNode]) -> [URL] {
            nodes.flatMap { $0.isDirectory ? pages(in: $0.children ?? []) : [$0.url] }
        }
        let matches = spaces.flatMap { pages(in: trees[$0.url] ?? []) }.filter {
            $0.deletingPathExtension().lastPathComponent.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let sourceSpace = space(containing: source)
        if let url = matches.first(where: { space(containing: $0) == sourceSpace }) ?? matches.first {
            return url
        }

        let url = source.deletingLastPathComponent().appendingPathComponent(sanitized(target)).appendingPathExtension("md")
        do {
            try "# \(target)\n\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            present(error, "Kon de pagina \(target) niet maken")
            return nil
        }
        refresh(containing: url)
        return url
    }

    func buildSearchIndex() async -> [SearchEntry] {
        let folders = spaces.map(\.url)
        let openTexts = Dictionary(documents.map { ($0.key, $0.value.text) }, uniquingKeysWith: { first, _ in first })
        return await Task.detached(priority: .userInitiated) {
            SearchIndex.build(workspaces: folders, looseFiles: [], openTexts: openTexts)
        }.value
    }

    func backlinks(to document: DocumentModel) async -> [Backlink] {
        let entries = await buildSearchIndex()
        let title = document.title
        let url = document.url
        return await Task.detached(priority: .utility) {
            WikiLinks.backlinks(to: title, excluding: url, in: entries)
        }.value
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(spaces.compactMap { try? $0.url.bookmarkData() }, forKey: bookmarksKey)
    }

    private func restore() {
        let bookmarks = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        for bookmark in bookmarks {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource() else { continue }
            spaces.append(Space(url: url.standardizedFileURL))
        }
        // Writing the bookmarks again replaces any that went stale.
        persist()
        refreshAll()
    }

    private func firstHeading(in text: String) -> String? {
        let firstLine = text.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }
        guard let line = firstLine?.trimmingCharacters(in: .whitespaces), line.hasPrefix("#") else { return nil }
        return line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
    }

    private func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(80))
    }

    private func uniqueURL(in folder: URL, base: String, pathExtension: String) -> URL {
        var number = 1
        while true {
            let url = folder
                .appendingPathComponent(number == 1 ? base : "\(base) \(number)")
                .appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: url.path) { return url.standardizedFileURL }
            number += 1
        }
    }

    private func present(_ error: Error, _ message: String) {
        errorMessage = "\(message).\n\n\(error.localizedDescription)"
    }
}
