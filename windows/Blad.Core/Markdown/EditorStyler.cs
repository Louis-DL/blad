using System.Text.RegularExpressions;

namespace Blad.Core.Markdown;

public enum LineKind { Body, Heading, Quote, ListItem, Rule, CodeFence, Code, Image }

/// <summary>How the editor lays out one line. Offsets are UTF-16 characters into the editor's text.</summary>
/// <param name="MarkerLength">Characters at the start that hang in the margin: "## ", "> ", or a list's "- [ ] ".</param>
/// <param name="Source">For an image line, the image path.</param>
public sealed record LineStyle(int Start, int Length, LineKind Kind, int HeadingLevel = 0, int MarkerLength = 0, string? Source = null);

public enum SpanKind
{
    /// <summary>Markdown syntax: shown, but quieter than the words around it.</summary>
    Syntax,
    Bold,
    Italic,
    Strike,
    InlineCode,
    LinkText,
    Url,
    ListMarker,
    DoneTask,
}

public sealed record StyleSpan(int Start, int Length, SpanKind Kind);

/// <summary>Lines first, then spans in the order they should be applied; later spans win.</summary>
public sealed record EditorStyling(IReadOnlyList<LineStyle> Lines, IReadOnlyList<StyleSpan> Spans);

/// <summary>
/// Works out how the editor shows markdown: the syntax stays visible but quiet, and heading, quote
/// and list markers hang in the margin so the text itself lines up. The same rules as the Mac app.
/// </summary>
public static partial class EditorStyler
{
    public static EditorStyling Style(string text)
    {
        var lines = new List<LineStyle>();
        var spans = new List<StyleSpan>();
        var inFence = false;
        var start = 0;

        while (true)
        {
            // The Windows text box separates paragraphs with \r; files use \n.
            var end = text.IndexOfAny(['\n', '\r'], start);
            var line = text[start..(end < 0 ? text.Length : end)];
            StyleLine(line, start, ref inFence, lines, spans);
            if (end < 0) break;
            start = end + 1;
        }
        return new EditorStyling(lines, spans);
    }

    private static void StyleLine(string line, int offset, ref bool inFence, List<LineStyle> lines, List<StyleSpan> spans)
    {
        var trimmed = line.Trim(' ', '\t');

        if (trimmed.StartsWith("```") || trimmed.StartsWith("~~~"))
        {
            lines.Add(new LineStyle(offset, line.Length, LineKind.CodeFence));
            spans.Add(new StyleSpan(offset, line.Length, SpanKind.Syntax));
            inFence = !inFence;
            return;
        }
        if (inFence)
        {
            lines.Add(new LineStyle(offset, line.Length, LineKind.Code));
            return;
        }
        if (ImageLine().Match(line) is { Success: true } image)
        {
            lines.Add(new LineStyle(offset, line.Length, LineKind.Image, Source: image.Groups[1].Value));
            spans.Add(new StyleSpan(offset, line.Length, SpanKind.Syntax));
            return;
        }
        if (Heading().Match(line) is { Success: true } heading)
        {
            var markerEnd = heading.Groups[2].Index + heading.Groups[2].Length;
            lines.Add(new LineStyle(offset, line.Length, LineKind.Heading, heading.Groups[1].Length, markerEnd));
            spans.Add(new StyleSpan(offset, markerEnd, SpanKind.Syntax));
            StyleInline(line, offset, spans);
            return;
        }
        if (Quote().Match(line) is { Success: true } quote)
        {
            lines.Add(new LineStyle(offset, line.Length, LineKind.Quote, MarkerLength: quote.Length));
            spans.Add(new StyleSpan(offset, quote.Length, SpanKind.Syntax));
            StyleInline(line, offset, spans);
            return;
        }
        if (Rule().IsMatch(line))
        {
            lines.Add(new LineStyle(offset, line.Length, LineKind.Rule));
            spans.Add(new StyleSpan(offset, line.Length, SpanKind.Syntax));
            return;
        }
        if (ListItem().Match(line) is { Success: true } item)
        {
            lines.Add(new LineStyle(offset, line.Length, LineKind.ListItem, MarkerLength: item.Length));
            spans.Add(new StyleSpan(offset + item.Groups[2].Index, item.Groups[2].Length, SpanKind.ListMarker));
            var box = item.Groups[4];
            if (box.Success)
            {
                spans.Add(new StyleSpan(offset + box.Index, box.Length, SpanKind.Syntax));
                if (box.Value.Contains('x', StringComparison.OrdinalIgnoreCase))
                {
                    spans.Add(new StyleSpan(offset + item.Length, line.Length - item.Length, SpanKind.DoneTask));
                }
            }
            StyleInline(line, offset, spans);
            return;
        }

        lines.Add(new LineStyle(offset, line.Length, LineKind.Body));
        StyleInline(line, offset, spans);
    }

    private static void StyleInline(string line, int offset, List<StyleSpan> spans)
    {
        if (line.Length < 2) return;

        var code = new List<(int Start, int End)>();
        foreach (Match match in InlineCode().Matches(line))
        {
            code.Add((match.Index, match.Index + match.Length));
            var ticks = match.Groups[1].Length;
            spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.InlineCode));
            AddMarkers(match, ticks, offset, spans);
        }
        bool OutsideCode(Match match) => !code.Any(range => match.Index < range.End && range.Start < match.Index + match.Length);

        foreach (Match match in Bold().Matches(line))
        {
            if (!OutsideCode(match)) continue;
            spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.Bold));
            AddMarkers(match, 2, offset, spans);
        }
        foreach (var pattern in new[] { ItalicStar(), ItalicUnderscore() })
        {
            foreach (Match match in pattern.Matches(line))
            {
                if (!OutsideCode(match)) continue;
                spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.Italic));
                AddMarkers(match, 1, offset, spans);
            }
        }
        foreach (Match match in Strikethrough().Matches(line))
        {
            if (!OutsideCode(match)) continue;
            spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.Strike));
            AddMarkers(match, 2, offset, spans);
        }
        foreach (Match match in BareUrl().Matches(line))
        {
            if (OutsideCode(match)) spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.Url));
        }
        foreach (Match match in Link().Matches(line))
        {
            if (!OutsideCode(match)) continue;
            spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.Syntax));
            spans.Add(new StyleSpan(offset + match.Groups[1].Index, match.Groups[1].Length, SpanKind.LinkText));
        }
        foreach (Match match in WikiLinks.Pattern().Matches(line))
        {
            if (!OutsideCode(match)) continue;
            spans.Add(new StyleSpan(offset + match.Index, match.Length, SpanKind.Syntax));
            var shown = match.Groups[2].Success ? match.Groups[2] : match.Groups[1];
            spans.Add(new StyleSpan(offset + shown.Index, shown.Length, SpanKind.LinkText));
        }
    }

    private static void AddMarkers(Match match, int length, int offset, List<StyleSpan> spans)
    {
        if (match.Length < length * 2) return;
        spans.Add(new StyleSpan(offset + match.Index, length, SpanKind.Syntax));
        spans.Add(new StyleSpan(offset + match.Index + match.Length - length, length, SpanKind.Syntax));
    }

    [GeneratedRegex(@"^(#{1,6})([ \t]+|$)")]
    private static partial Regex Heading();

    [GeneratedRegex(@"^[ \t]*(?:>[ \t]?)+")]
    private static partial Regex Quote();

    [GeneratedRegex(@"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")]
    private static partial Regex Rule();

    /// <summary>Groups: 1 indent, 2 marker, 3 spacing, 4 optional task box.</summary>
    [GeneratedRegex(@"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?")]
    public static partial Regex ListItem();

    [GeneratedRegex(@"^[ \t]*!\[[^\]\n]*\]\(([^)\s]+)(?:[ \t]+""[^""]*"")?\)[ \t]*$")]
    private static partial Regex ImageLine();

    [GeneratedRegex(@"(`+)(?!`)(.+?)(?<!`)\1(?!`)")]
    private static partial Regex InlineCode();

    [GeneratedRegex(@"(\*\*|__)(?=\S)(.+?)(?<=\S)\1")]
    private static partial Regex Bold();

    [GeneratedRegex(@"(?<![*\\\w])\*(?![\s*])(.+?)(?<![\s*\\])\*(?![*\w])")]
    private static partial Regex ItalicStar();

    [GeneratedRegex(@"(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])")]
    private static partial Regex ItalicUnderscore();

    [GeneratedRegex(@"~~(?=\S)(.+?)(?<=\S)~~")]
    private static partial Regex Strikethrough();

    [GeneratedRegex(@"!?\[([^\]\n]+)\]\(([^)\s]*)(?:\s+""[^""]*"")?\)")]
    private static partial Regex Link();

    [GeneratedRegex(@"(?<![(<\w])https?://[^\s)>\]]+")]
    private static partial Regex BareUrl();
}
