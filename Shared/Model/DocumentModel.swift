import Foundation
import Observation

/// One open markdown file. Edits are saved automatically shortly after typing stops.
@Observable
final class DocumentModel: Identifiable {
    let id = UUID()
    private(set) var url: URL
    private(set) var isDirty = false
    private(set) var wordCount = 0

    /// Pages made in Blad take their file name from the first heading, until renamed by hand.
    var namesItselfFromHeading = false

    /// Shows the rendered page instead of the markdown source.
    var isReading = false

    /// Set by the outline to move the page to a heading; the editor and reading mode pick it up.
    var jump: Jump?

    var headings: [Heading] { Outline.headings(in: text) }

    var text: String {
        didSet {
            guard text != oldValue else { return }
            wordCount = Self.countWords(in: text)
            if !isApplyingDiskContents {
                isDirty = true
                scheduleSave()
            }
        }
    }

    @ObservationIgnored var onSave: ((DocumentModel) -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingDiskContents = false

    var title: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL) throws {
        self.url = url
        let contents = try Self.read(url)
        text = contents
        wordCount = Self.countWords(in: contents)
    }

    func save() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            onSave?(self)
        } catch {
            NSLog("Blad: kon \(url.path) niet bewaren: \(error)")
        }
    }

    /// Picks up changes made by other apps, unless there are unsaved edits here.
    func reloadFromDisk() {
        guard !isDirty, let contents = try? Self.read(url), contents != text else { return }
        isApplyingDiskContents = true
        text = contents
        isApplyingDiskContents = false
    }

    func move(to newURL: URL) {
        url = newURL
    }

    /// Ticks the `[ ]` task on a source line on or off.
    func toggleTask(atLine line: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line),
              let box = lines[line].range(of: #"\[[ xX]\]"#, options: .regularExpression) else { return }
        let isDone = lines[line][box] != "[ ]"
        lines[line].replaceSubrange(box, with: isDone ? "[ ]" : "[x]")
        text = lines.joined(separator: "\n")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private static func read(_ url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Counts runs of text that contain a letter or digit, so markdown symbols like `#` or `-` don't count.
    static func countWords(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let properties = scalar.properties
            if properties.isWhitespace {
                inWord = false
            } else if !inWord, properties.isAlphabetic || properties.numericType != nil {
                inWord = true
                count += 1
            }
        }
        return count
    }
}
