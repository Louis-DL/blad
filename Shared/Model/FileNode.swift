import Foundation

nonisolated enum FileSort: String, CaseIterable, Identifiable {
    case name, modified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Naam"
        case .modified: "Laatst gewijzigd"
        }
    }
}

/// A folder or markdown page inside a workspace, as shown in the sidebar.
nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let modified: Date?
    var children: [FileNode]?

    var id: URL { url }

    var name: String {
        isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let skippedFolders: Set<String> = ["node_modules", "build", "DerivedData", "Pods", "dist", "vendor"]

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// Builds the tree of folders and markdown pages below `folder`. Folders always come first.
    /// Folders without any markdown are hidden so code repositories stay readable,
    /// unless they are completely empty (a freshly made folder should still show up).
    static func scan(_ folder: URL, sort: FileSort = .name, depth: Int = 0) -> [FileNode] {
        guard depth < 10 else { return [] }
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }

        var folders: [FileNode] = []
        var pages: [FileNode] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                guard values?.isPackage != true, !skippedFolders.contains(entry.lastPathComponent) else { continue }
                let children = scan(entry, sort: sort, depth: depth + 1)
                let isEmpty = (try? fileManager.contentsOfDirectory(atPath: entry.path))?.allSatisfy { $0.hasPrefix(".") } ?? true
                if !children.isEmpty || isEmpty {
                    folders.append(FileNode(url: entry.standardizedFileURL, isDirectory: true, modified: values?.contentModificationDate, children: children))
                }
            } else if isMarkdown(entry) {
                pages.append(FileNode(url: entry.standardizedFileURL, isDirectory: false, modified: values?.contentModificationDate, children: nil))
            }
        }

        let order: (FileNode, FileNode) -> Bool = { first, second in
            if sort == .modified, let a = first.modified, let b = second.modified, a != b {
                return a > b
            }
            return first.url.lastPathComponent.localizedStandardCompare(second.url.lastPathComponent) == .orderedAscending
        }
        return folders.sorted(by: order) + pages.sorted(by: order)
    }
}
