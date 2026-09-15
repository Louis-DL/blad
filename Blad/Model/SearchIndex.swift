import Foundation

/// One markdown page with its contents, for searching and finding links.
nonisolated struct SearchEntry: Identifiable, Sendable {
    let url: URL
    let title: String
    /// Workspace and folders, e.g. "Notities › School".
    let location: String
    let text: String
    let modified: Date

    var id: URL { url }
}

nonisolated struct SearchResult: Identifiable, Sendable {
    let entry: SearchEntry
    /// The line around a match in the page's text; nil when the title matched.
    let snippet: String?

    var id: URL { entry.url }
}

nonisolated enum SearchIndex {
    private static let maxFileSize = 1_000_000
    private static let maxFiles = 5_000

    /// Reads every markdown page in the workspaces, newest first.
    /// Open pages use their text in memory, so unsaved edits are found too.
    static func build(workspaces: [URL], looseFiles: [URL], openTexts: [URL: String]) -> [SearchEntry] {
        var entries: [SearchEntry] = []
        var seen = Set<URL>()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]

        func add(_ url: URL, location: String) {
            let url = url.standardizedFileURL
            guard entries.count < maxFiles, seen.insert(url).inserted else { return }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard (values?.fileSize ?? 0) <= maxFileSize,
                  let text = openTexts[url] ?? (try? String(contentsOf: url, encoding: .utf8)) else { return }
            entries.append(SearchEntry(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                location: location,
                text: text,
                modified: values?.contentModificationDate ?? .distantPast
            ))
        }

        for workspace in workspaces {
            guard let enumerator = FileManager.default.enumerator(
                at: workspace,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            let parentPath = workspace.deletingLastPathComponent().path
            while let url = enumerator.nextObject() as? URL {
                if FileNode.skippedFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard FileNode.isMarkdown(url) else { continue }
                let folders = url.deletingLastPathComponent().path.dropFirst(parentPath.count).split(separator: "/")
                add(url, location: folders.joined(separator: " › "))
            }
        }
        for url in looseFiles {
            add(url, location: url.deletingLastPathComponent().lastPathComponent)
        }
        return entries.sorted { $0.modified > $1.modified }
    }

    /// Title matches rank above matches in the text. An empty query lists recent pages.
    static func search(_ query: String, in entries: [SearchEntry]) -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return entries.prefix(10).map { SearchResult(entry: $0, snippet: nil) }
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        var scored: [(result: SearchResult, score: Int)] = []
        for entry in entries {
            var score = 0
            if let range = entry.title.range(of: query, options: options) {
                score = range.lowerBound == entry.title.startIndex ? 300 : 200
            } else if query.count > 1, isSubsequence(query, of: entry.title) {
                score = 100
            }

            var snippet: String?
            if score == 0, let range = entry.text.range(of: query, options: options) {
                snippet = makeSnippet(entry.text, around: range)
                score = 50
            }
            if score > 0 {
                scored.append((SearchResult(entry: entry, snippet: snippet), score))
            }
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.result.entry.modified > $1.result.entry.modified }
            .prefix(50)
            .map(\.result)
    }

    /// "wkp" matches "Werkplan": the letters appear in order.
    private static func isSubsequence(_ query: String, of title: String) -> Bool {
        var remaining = Substring(query.lowercased().filter { !$0.isWhitespace })
        for character in title.lowercased() where character == remaining.first {
            remaining.removeFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func makeSnippet(_ text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[start..<end]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return (start > text.startIndex ? "…" : "") + excerpt + (end < text.endIndex ? "…" : "")
    }
}
