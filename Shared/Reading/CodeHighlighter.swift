import Foundation

/// Colours inside a code block. Quiet on purpose: comments fade, words that carry
/// meaning get one colour each, and everything else stays the colour of the page.
nonisolated enum CodeToken: Equatable, Sendable {
    case keyword
    case string
    case number
    case comment
}

nonisolated enum CodeHighlighter {
    /// The coloured pieces of a code block. Ranges are in the code's own UTF-16 offsets,
    /// in order and without overlaps; everything in between keeps the page's text colour.
    static func tokens(in code: String, language: String) -> [(range: NSRange, token: CodeToken)] {
        let rules = Rules.forLanguage(language)
        let source = code as NSString
        var tokens: [(range: NSRange, token: CodeToken)] = []
        var index = 0

        while index < source.length {
            let character = source.character(at: index)

            if let end = rules.commentEnd(in: source, from: index) {
                tokens.append((NSRange(location: index, length: end - index), .comment))
                index = end
            } else if let end = rules.stringEnd(in: source, from: index) {
                tokens.append((NSRange(location: index, length: end - index), .string))
                index = end
            } else if isDigit(character), !isWordCharacter(source.safeCharacter(at: index - 1)) {
                var end = index
                while end < source.length, isDigit(source.character(at: end)) || isNumberPart(source, at: end) { end += 1 }
                tokens.append((NSRange(location: index, length: end - index), .number))
                index = end
            } else if isWordStart(character) {
                var end = index
                while end < source.length, isWordCharacter(source.character(at: end)) { end += 1 }
                let word = source.substring(with: NSRange(location: index, length: end - index))
                if rules.keywords.contains(word) {
                    tokens.append((NSRange(location: index, length: end - index), .keyword))
                }
                index = end
            } else {
                index += 1
            }
        }
        return tokens
    }

    // MARK: Characters

    private static func isDigit(_ character: unichar) -> Bool { character >= 48 && character <= 57 }

    private static func isWordStart(_ character: unichar) -> Bool {
        (character >= 65 && character <= 90) || (character >= 97 && character <= 122) || character == 95 || character == 35 || character == 64
    }

    private static func isWordCharacter(_ character: unichar?) -> Bool {
        guard let character else { return false }
        return isDigit(character) || (character >= 65 && character <= 90) || (character >= 97 && character <= 122) || character == 95
    }

    /// Keeps `1.5`, `0x1f` and `1e9` together as one number.
    private static func isNumberPart(_ source: NSString, at index: Int) -> Bool {
        let character = source.character(at: index)
        guard character == 46 || isWordCharacter(character) else { return false }
        return index > 0 && (isDigit(source.character(at: index - 1)) || isWordCharacter(source.character(at: index - 1)))
    }

    // MARK: Languages

    /// What counts as a comment, a string and a keyword. Languages Blad doesn't know fall back
    /// to the shapes almost every language shares: quotes, `//`, `#` and `/* */`.
    private struct Rules {
        var lineComments: [String]
        var blockComment: (open: String, close: String)?
        var quotes: [unichar]
        var keywords: Set<String>

        static func forLanguage(_ language: String) -> Rules {
            switch language.lowercased() {
            case "swift":
                Rules(lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [34], keywords: swift)
            case "python", "py":
                Rules(lineComments: ["#"], blockComment: nil, quotes: [34, 39], keywords: python)
            case "js", "javascript", "ts", "typescript", "jsx", "tsx":
                Rules(lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [34, 39, 96], keywords: javascript)
            case "json":
                Rules(lineComments: [], blockComment: nil, quotes: [34], keywords: ["true", "false", "null"])
            case "sh", "bash", "zsh", "shell", "console":
                Rules(lineComments: ["#"], blockComment: nil, quotes: [34, 39], keywords: shell)
            case "html", "xml", "css", "scss":
                Rules(lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [34, 39], keywords: [])
            case "c", "cpp", "c++", "java", "kotlin", "cs", "csharp", "go", "rust", "rs", "php":
                Rules(lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [34, 39], keywords: curly)
            default:
                Rules(lineComments: ["//", "#"], blockComment: ("/*", "*/"), quotes: [34, 39, 96], keywords: [])
            }
        }

        /// Where the comment starting here ends, or nil when none starts here.
        func commentEnd(in source: NSString, from index: Int) -> Int? {
            for marker in lineComments where source.starts(with: marker, at: index) {
                let newline = source.range(of: "\n", range: NSRange(location: index, length: source.length - index))
                return newline.location == NSNotFound ? source.length : newline.location
            }
            if let block = blockComment, source.starts(with: block.open, at: index) {
                let rest = NSRange(location: index + block.open.count, length: source.length - index - block.open.count)
                let close = source.range(of: block.close, range: rest)
                return close.location == NSNotFound ? source.length : NSMaxRange(close)
            }
            return nil
        }

        /// Where the string starting here ends, or nil when none starts here.
        func stringEnd(in source: NSString, from index: Int) -> Int? {
            let quote = source.character(at: index)
            guard quotes.contains(quote) else { return nil }
            var end = index + 1
            while end < source.length {
                let character = source.character(at: end)
                if character == 92 { end += 2; continue }               // \" stays inside the string
                if character == 10 { return end }                        // a line break ends it
                if character == quote { return end + 1 }
                end += 1
            }
            return source.length
        }
    }

    private static let swift: Set<String> = [
        "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer",
        "deinit", "do", "else", "enum", "extension", "fileprivate", "final", "for", "func", "guard", "if", "import",
        "in", "init", "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator",
        "private", "protocol", "public", "repeat", "return", "self", "some", "static", "struct", "subscript", "super",
        "switch", "throw", "throws", "try", "typealias", "var", "weak", "where", "while", "true", "false",
    ]

    private static let python: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except",
        "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
        "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "self",
    ]

    private static let javascript: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else",
        "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "interface",
        "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw", "try", "type", "typeof",
        "undefined", "var", "void", "while", "yield", "true", "false",
    ]

    private static let shell: Set<String> = [
        "case", "cd", "do", "done", "echo", "elif", "else", "esac", "exit", "export", "fi", "for", "function", "if",
        "in", "local", "return", "set", "source", "then", "while",
    ]

    private static let curly: Set<String> = [
        "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "false",
        "final", "finally", "for", "func", "function", "go", "if", "import", "interface", "let", "namespace", "new",
        "null", "package", "private", "protected", "public", "return", "static", "struct", "switch", "this", "throw",
        "true", "try", "type", "using", "var", "void", "while",
    ]
}

private extension NSString {
    func starts(with marker: String, at index: Int) -> Bool {
        guard index + marker.count <= length else { return false }
        return substring(with: NSRange(location: index, length: marker.count)) == marker
    }

    func safeCharacter(at index: Int) -> unichar? {
        index >= 0 && index < length ? character(at: index) : nil
    }
}
