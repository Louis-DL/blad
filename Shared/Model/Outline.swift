import Foundation

/// A heading in a page. The outline lists these so a long note can be jumped through.
nonisolated struct Heading: Identifiable, Equatable, Sendable {
    /// Its place among the headings, which is also its place in reading mode.
    let id: Int
    let level: Int
    let title: String
    /// Where the heading's line starts in the page's text, counted the way text views count.
    let offset: Int
}

/// Where the outline wants the page to go. The id makes a second jump to the same heading count.
nonisolated struct Jump: Equatable, Sendable {
    let offset: Int
    let heading: Int
    let id = UUID()
}

enum Outline {
    private static let heading = /^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$/

    /// The headings of a page, in the order they appear. Headings inside code blocks don't count.
    nonisolated static func headings(in text: String) -> [Heading] {
        var headings: [Heading] = []
        var offset = 0
        var insideCode = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCode.toggle()
            } else if !insideCode, let match = trimmed.firstMatch(of: heading) {
                headings.append(Heading(
                    id: headings.count,
                    level: match.output.1.count,
                    title: String(match.output.2),
                    offset: offset
                ))
            }
            offset += line.utf16.count + 1
        }
        return headings
    }
}
