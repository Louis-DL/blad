import AppKit

extension AppModel {
    /// Every markdown page in the sidebar.
    var allPages: [URL] {
        func pages(in nodes: [FileNode]) -> [URL] {
            nodes.flatMap { $0.isDirectory ? pages(in: $0.children ?? []) : [$0.url] }
        }
        return workspaces.flatMap { pages(in: trees[$0] ?? []) } + looseFiles
    }

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
        for workspace in workspaces {
            walk(trees[workspace] ?? [], location: workspace.lastPathComponent)
        }
        for url in looseFiles {
            pages.append((PageRef(title: url.deletingPathExtension().lastPathComponent, location: "Losse pagina's"), .distantPast))
        }
        return pages.sorted { $0.modified > $1.modified }.map(\.ref)
    }

    /// Opens the page a `[[link]]` points to, preferring the linking page's own workspace.
    /// A link to a page that doesn't exist yet creates it next to the linking page.
    func openPage(named name: String, from source: URL?) {
        let target = (name.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        guard !target.isEmpty else { return }

        let matches = allPages.filter {
            $0.deletingPathExtension().lastPathComponent.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let sourceWorkspace = source.flatMap { workspace(containing: $0) }
        if let url = matches.first(where: { workspace(containing: $0) == sourceWorkspace }) ?? matches.first {
            openItem(url)
            return
        }

        guard let folder = source?.deletingLastPathComponent() ?? workspaces.first else { return }
        let url = folder.appendingPathComponent(sanitizedFileName(target)).appendingPathExtension("md")
        do {
            try "# \(target)\n\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            present(error, "Kon de pagina \(target) niet maken")
            return
        }
        refreshTree(containing: url)
        openItem(url)
    }

    /// Follows a markdown link or URL: markdown files open in Blad, everything else in its own app.
    /// Clicking a `#tag` searches for it across the spaces.
    func search(tag name: String) {
        quickOpenQuery = "#" + name
        isQuickOpenPresented = true
    }

    func openLink(_ target: String, from source: URL) {
        let raw = target.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, !raw.hasPrefix("#") else { return }
        let base = source.deletingLastPathComponent()
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let url = (URL(string: raw, relativeTo: base) ?? encoded.flatMap { URL(string: $0, relativeTo: base) })?.absoluteURL else {
            return
        }
        if url.isFileURL, FileNode.isMarkdown(url) {
            openItem(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func backlinks(to document: DocumentModel) async -> [Backlink] {
        let entries = await buildSearchIndex()
        let title = document.title
        let url = document.url
        return await Task.detached(priority: .utility) {
            WikiLinks.backlinks(to: title, excluding: url, in: entries)
        }.value
    }
}
