import Foundation

/// A block of markdown as shown in reading mode. Inline syntax (bold, links, code)
/// stays in the text and is rendered by `AttributedString`.
nonisolated enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([ListItem])
    case quote(String)
    case code(language: String, code: String)
    case table(header: [String], rows: [[String]])
    case image(alt: String, source: String)
    case rule

    struct ListItem: Equatable {
        enum Marker: Equatable {
            case bullet
            case number(String)
            case task(done: Bool)
        }

        let depth: Int
        let marker: Marker
        var text: String
        /// Line in the source, so a task can be ticked off from reading mode.
        let line: Int
    }

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let language = trimmed.drop { $0 == "`" || $0 == "~" }.trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                blocks.append(.code(language: language, code: code.joined(separator: "\n")))
            } else if let groups = match(headingPattern, trimmed) {
                blocks.append(.heading(level: groups[1].count, text: groups[2]))
                index += 1
            } else if match(rulePattern, line) != nil {
                blocks.append(.rule)
                index += 1
            } else if startsTable(at: index, lines) {
                let header = cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].contains("|"), !isBlank(lines[index]) {
                    rows.append(cells(lines[index]))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
            } else if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoted.append(String(quoteLine.drop { $0 == ">" || $0 == " " }))
                    index += 1
                }
                blocks.append(.quote(joinParagraph(quoted)))
            } else if listItem(line, at: index) != nil {
                var items: [ListItem] = []
                while index < lines.count {
                    if let item = listItem(lines[index], at: index) {
                        items.append(item)
                        index += 1
                    } else if !items.isEmpty, !isBlank(lines[index]), lines[index].first?.isWhitespace == true {
                        items[items.count - 1].text += " " + lines[index].trimmingCharacters(in: .whitespaces)
                        index += 1
                    } else if isBlank(lines[index]), index + 1 < lines.count, listItem(lines[index + 1], at: index + 1) != nil {
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(items))
            } else if let groups = match(imagePattern, trimmed) {
                blocks.append(.image(alt: groups[1], source: groups[2]))
                index += 1
            } else {
                var paragraph: [String] = []
                while index < lines.count, !isBlank(lines[index]), paragraph.isEmpty || !startsBlock(at: index, lines) {
                    paragraph.append(lines[index])
                    index += 1
                }
                blocks.append(.paragraph(joinParagraph(paragraph)))
            }
        }
        return blocks
    }

    // MARK: - Helpers

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    private static func startsBlock(at index: Int, _ lines: [String]) -> Bool {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") || trimmed.hasPrefix(">")
            || match(headingPattern, trimmed) != nil
            || match(rulePattern, line) != nil
            || listItem(line, at: index) != nil
            || startsTable(at: index, lines)
    }

    private static func startsTable(at index: Int, _ lines: [String]) -> Bool {
        lines[index].contains("|") && index + 1 < lines.count && match(tableSeparatorPattern, lines[index + 1]) != nil
    }

    private static func listItem(_ line: String, at index: Int) -> ListItem? {
        guard let groups = match(listPattern, line) else { return nil }
        let indent = groups[1].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let marker: ListItem.Marker
        if !groups[3].isEmpty {
            marker = .task(done: groups[3].lowercased().contains("x"))
        } else if groups[2].first?.isNumber == true {
            marker = .number(groups[2])
        } else {
            marker = .bullet
        }
        return ListItem(depth: indent / 2, marker: marker, text: groups[4], line: index)
    }

    /// Joins soft-wrapped lines with spaces; two trailing spaces or a backslash keep the line break.
    private static func joinParagraph(_ lines: [String]) -> String {
        var result = ""
        for (index, line) in lines.enumerated() {
            let hardBreak = line.hasSuffix("  ") || line.hasSuffix("\\")
            var content = line.trimmingCharacters(in: .whitespaces)
            if content.hasSuffix("\\") { content.removeLast() }
            result += content
            if index < lines.count - 1 { result += hardBreak ? "\n" : " " }
        }
        return result
    }

    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Capture groups of the first match; unmatched optional groups are empty strings.
    private static func match(_ regex: NSRegularExpression, _ string: String) -> [String]? {
        let text = string as NSString
        guard let result = regex.firstMatch(in: string, range: NSRange(location: 0, length: text.length)) else { return nil }
        return (0..<result.numberOfRanges).map {
            let range = result.range(at: $0)
            return range.location == NSNotFound ? "" : text.substring(with: range)
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static let headingPattern = regex(#"^(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$"#)
    private static let rulePattern = regex(#"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let tableSeparatorPattern = regex(#"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#)
    private static let listPattern = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?(.*)$"#)
    private static let imagePattern = regex(#"^!\[([^\]]*)\]\(([^)\s]+)(?:[ \t]+"[^"]*")?\)$"#)
}
