import Foundation

extension AppModel {
    /// Moves pages or folders into `folder`. Files from outside the workspaces are copied instead,
    /// so dragging something in from Finder never takes it away from where it was.
    @discardableResult
    func moveItems(_ urls: [URL], into folder: URL) -> Bool {
        let folder = folder.standardizedFileURL
        var didChange = false
        for source in urls.map(\.standardizedFileURL) {
            let isFolder = isDirectory(source)
            guard isFolder || FileNode.isMarkdown(source),
                  source != folder,
                  !folder.path.hasPrefix(source.path + "/"),
                  source.deletingLastPathComponent().path != folder.path else { continue }

            let destination = uniqueURL(
                in: folder,
                base: isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent,
                pathExtension: isFolder ? nil : source.pathExtension
            )
            if workspace(containing: source) != nil {
                didChange = move(source, to: destination, keepsAutoNaming: true) || didChange
            } else {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    refreshTree(containing: destination)
                    didChange = true
                } catch {
                    present(error, "Kon \(source.lastPathComponent) niet kopiëren")
                }
            }
        }
        return didChange
    }

    func duplicate(_ url: URL) {
        documents.first { $0.url == url }?.save()
        let copy = uniqueURL(
            in: url.deletingLastPathComponent(),
            base: url.deletingPathExtension().lastPathComponent + " kopie",
            pathExtension: url.pathExtension
        )
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            present(error, "Kon \(url.lastPathComponent) niet dupliceren")
            return
        }
        refreshTree(containing: copy)
        open(copy)
    }
}
