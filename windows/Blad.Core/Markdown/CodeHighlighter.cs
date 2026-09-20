namespace Blad.Core.Markdown;

/// <summary>Colours inside a code block. Quiet on purpose: comments fade, words that carry
/// meaning get one colour each, and everything else stays the colour of the page.</summary>
public enum CodeToken { Keyword, String, Number, Comment }

/// <summary>A coloured piece of a code block, in the code's own character offsets.</summary>
public sealed record CodeSpan(int Start, int Length, CodeToken Token);

/// <summary>The same rules as the Mac and iPhone apps, so code reads the same everywhere.</summary>
public static class CodeHighlighter
{
    /// <summary>The coloured pieces, in order and without overlaps; the text in between keeps the page's colour.</summary>
    public static IReadOnlyList<CodeSpan> Tokens(string code, string language)
    {
        var rules = Rules.For(language);
        var spans = new List<CodeSpan>();
        var index = 0;

        while (index < code.Length)
        {
            var character = code[index];
            if (rules.CommentEnd(code, index) is { } commentEnd)
            {
                spans.Add(new CodeSpan(index, commentEnd - index, CodeToken.Comment));
                index = commentEnd;
            }
            else if (rules.StringEnd(code, index) is { } stringEnd)
            {
                spans.Add(new CodeSpan(index, stringEnd - index, CodeToken.String));
                index = stringEnd;
            }
            else if (char.IsAsciiDigit(character) && !IsWord(code, index - 1))
            {
                var end = index;
                while (end < code.Length && (char.IsAsciiDigit(code[end]) || IsNumberPart(code, end))) end++;
                spans.Add(new CodeSpan(index, end - index, CodeToken.Number));
                index = end;
            }
            else if (char.IsAsciiLetter(character) || character is '_' or '#' or '@')
            {
                var end = index;
                while (end < code.Length && (char.IsAsciiLetterOrDigit(code[end]) || code[end] == '_')) end++;
                if (rules.Keywords.Contains(code[index..end])) spans.Add(new CodeSpan(index, end - index, CodeToken.Keyword));
                index = end;
            }
            else
            {
                index++;
            }
        }
        return spans;
    }

    private static bool IsWord(string code, int index) =>
        index >= 0 && index < code.Length && (char.IsAsciiLetterOrDigit(code[index]) || code[index] == '_');

    /// <summary>Keeps <c>1.5</c>, <c>0x1f</c> and <c>1e9</c> together as one number.</summary>
    private static bool IsNumberPart(string code, int index) =>
        (code[index] == '.' || IsWord(code, index)) && IsWord(code, index - 1);

    /// <summary>What counts as a comment, a string and a keyword. Languages Blad doesn't know fall back
    /// to the shapes almost every language shares: quotes, <c>//</c>, <c>#</c> and <c>/* */</c>.</summary>
    private sealed record Rules(string[] LineComments, (string Open, string Close)? Block, char[] Quotes, HashSet<string> Keywords)
    {
        public static Rules For(string language) => language.ToLowerInvariant() switch
        {
            "swift" => new(["//"], ("/*", "*/"), ['"'], Swift),
            "python" or "py" => new(["#"], null, ['"', '\''], Python),
            "js" or "javascript" or "ts" or "typescript" or "jsx" or "tsx" => new(["//"], ("/*", "*/"), ['"', '\'', '`'], JavaScript),
            "json" => new([], null, ['"'], ["true", "false", "null"]),
            "sh" or "bash" or "zsh" or "shell" or "console" => new(["#"], null, ['"', '\''], Shell),
            "html" or "xml" or "css" or "scss" => new(["//"], ("/*", "*/"), ['"', '\''], []),
            "c" or "cpp" or "c++" or "java" or "kotlin" or "cs" or "csharp" or "go" or "rust" or "rs" or "php" =>
                new(["//"], ("/*", "*/"), ['"', '\''], Curly),
            _ => new(["//", "#"], ("/*", "*/"), ['"', '\'', '`'], []),
        };

        /// <summary>Where the comment starting here ends, or null when none starts here.</summary>
        public int? CommentEnd(string code, int index)
        {
            foreach (var marker in LineComments)
            {
                if (!Starts(code, index, marker)) continue;
                var newline = code.IndexOf('\n', index);
                return newline < 0 ? code.Length : newline;
            }
            if (Block is { } block && Starts(code, index, block.Open))
            {
                var close = code.IndexOf(block.Close, index + block.Open.Length, StringComparison.Ordinal);
                return close < 0 ? code.Length : close + block.Close.Length;
            }
            return null;
        }

        /// <summary>Where the string starting here ends, or null when none starts here.</summary>
        public int? StringEnd(string code, int index)
        {
            var quote = code[index];
            if (!Quotes.Contains(quote)) return null;
            var end = index + 1;
            while (end < code.Length)
            {
                if (code[end] == '\\') { end += 2; continue; }   // \" stays inside the string
                if (code[end] == '\n') return end;               // a line break ends it
                if (code[end] == quote) return end + 1;
                end++;
            }
            return code.Length;
        }

        private static bool Starts(string code, int index, string marker) =>
            index + marker.Length <= code.Length && code.AsSpan(index, marker.Length).SequenceEqual(marker);
    }

    private static readonly HashSet<string> Swift =
    [
        "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer",
        "deinit", "do", "else", "enum", "extension", "fileprivate", "final", "for", "func", "guard", "if", "import",
        "in", "init", "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator",
        "private", "protocol", "public", "repeat", "return", "self", "some", "static", "struct", "subscript", "super",
        "switch", "throw", "throws", "try", "typealias", "var", "weak", "where", "while", "true", "false",
    ];

    private static readonly HashSet<string> Python =
    [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except",
        "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
        "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "self",
    ];

    private static readonly HashSet<string> JavaScript =
    [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else",
        "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "interface",
        "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw", "try", "type", "typeof",
        "undefined", "var", "void", "while", "yield", "true", "false",
    ];

    private static readonly HashSet<string> Shell =
    [
        "case", "cd", "do", "done", "echo", "elif", "else", "esac", "exit", "export", "fi", "for", "function", "if",
        "in", "local", "return", "set", "source", "then", "while",
    ];

    private static readonly HashSet<string> Curly =
    [
        "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "false",
        "final", "finally", "for", "func", "function", "go", "if", "import", "interface", "let", "namespace", "new",
        "null", "package", "private", "protected", "public", "return", "static", "struct", "switch", "this", "throw",
        "true", "try", "type", "using", "var", "void", "while",
    ];
}
