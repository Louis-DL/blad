import AppKit
import UniformTypeIdentifiers

/// Saves pasted, dropped or chosen images into an `assets` folder next to the page,
/// and returns the markdown that shows them. Plain files and relative links, so the
/// images keep working on GitHub and in other editors.
enum ImageImporter {
    enum Source {
        case files([URL])
        case data(Data)
    }

    static let folderName = "assets"

    /// A quick check for drag feedback, without reading any image data.
    static func hasImages(on pasteboard: NSPasteboard, allowsText: Bool) -> Bool {
        if !imageFiles(on: pasteboard).isEmpty { return true }
        return (allowsText || pasteboard.string(forType: .string) == nil)
            && pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    /// Image files, or else image data. Image data that comes with text (copied from a web page
    /// or a document) is left to a normal paste, unless `allowsText` is set.
    static func source(from pasteboard: NSPasteboard, allowsText: Bool) -> Source? {
        let files = imageFiles(on: pasteboard)
        if !files.isEmpty { return .files(files) }
        guard hasImages(on: pasteboard, allowsText: allowsText), let data = pngData(from: pasteboard) else { return nil }
        return .data(data)
    }

    static func importImages(_ source: Source, for page: URL) throws -> [String] {
        let pageFolder = page.deletingLastPathComponent().standardizedFileURL
        let assets = pageFolder.appendingPathComponent(folderName, isDirectory: true)
        let fileManager = FileManager.default

        switch source {
        case .files(let urls):
            return try urls.map { url in
                let url = url.standardizedFileURL
                let name = url.deletingPathExtension().lastPathComponent
                // Images already in the page's folder are linked where they are.
                if url.path.hasPrefix(pageFolder.path + "/") {
                    return markdown(for: url, alt: name, pageFolder: pageFolder)
                }
                try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
                let destination = uniqueURL(in: assets, base: slug(name), pathExtension: url.pathExtension.lowercased())
                try fileManager.copyItem(at: url, to: destination)
                return markdown(for: destination, alt: name, pageFolder: pageFolder)
            }

        case .data(let data):
            try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
            let base = slug(page.deletingPathExtension().lastPathComponent) + "-" + timestamp.string(from: Date())
            let destination = uniqueURL(in: assets, base: base, pathExtension: "png")
            try data.write(to: destination, options: .atomic)
            return [markdown(for: destination, alt: "", pageFolder: pageFolder)]
        }
    }

    // MARK: - Helpers

    private static func imageFiles(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func markdown(for image: URL, alt: String, pageFolder: URL) -> String {
        var path = image.standardizedFileURL.path
        if path.hasPrefix(pageFolder.path + "/") {
            path = String(path.dropFirst(pageFolder.path.count + 1))
        }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let cleanAlt = alt.filter { $0 != "[" && $0 != "]" }
        return "![\(cleanAlt)](\(encoded))"
    }

    /// "Schermafbeelding 2026-09-15 om 14.30" → "schermafbeelding-2026-09-15-om-14-30".
    private static func slug(_ name: String) -> String {
        var words: [String] = []
        var word = ""
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        let joined = words.joined(separator: "-")
        return joined.isEmpty ? "afbeelding" : String(joined.prefix(60))
    }

    private static func uniqueURL(in folder: URL, base: String, pathExtension: String) -> URL {
        var number = 1
        while true {
            let name = number == 1 ? base : "\(base)-\(number)"
            let url = folder.appendingPathComponent(name).appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
