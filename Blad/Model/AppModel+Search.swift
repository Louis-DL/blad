import Foundation

extension AppModel {
    /// Reads all pages off the main thread. Cheap enough to rebuild each time search opens.
    func buildSearchIndex() async -> [SearchEntry] {
        let workspaces = self.workspaces
        let looseFiles = self.looseFiles
        let openTexts = Dictionary(documents.map { ($0.url, $0.text) }, uniquingKeysWith: { first, _ in first })
        return await Task.detached(priority: .userInitiated) {
            SearchIndex.build(workspaces: workspaces, looseFiles: looseFiles, openTexts: openTexts)
        }.value
    }
}
