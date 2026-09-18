using System.Text;
using System.Text.RegularExpressions;

namespace Blad.Core.Markdown;

public enum ListKind { Bullet, Number, Task }

/// <summary>One list item. <see cref="Line"/> is its line in the source, so a task can be ticked off from reading mode.</summary>
public sealed record ListItem(int Depth, ListKind Kind, string Marker, bool Done, string Text, int Line);

/// <summary>A block of markdown as shown in reading mode. Inline syntax (bold, links, code) stays in the text.</summary>
public abstract record MarkdownBlock
{
    public sealed record Heading(int Level, string Text) : MarkdownBlock;
    public sealed record Paragraph(string Text) : MarkdownBlock;
    public sealed record ListBlock(IReadOnlyList<ListItem> Items) : MarkdownBlock;
    public sealed record Quote(string Text) : MarkdownBlock;
    public sealed record CodeBlock(string Language, string Code) : MarkdownBlock;
    public sealed record Table(IReadOnlyList<string> Header, IReadOnlyList<IReadOnlyList<string>> Rows) : MarkdownBlock;
    public sealed record Image(string Alt, string Source) : MarkdownBlock;
    public sealed record Rule : MarkdownBlock;
}

/// <summary>The same parser as the Mac and iPhone apps, so a page reads the same everywhere.</summary>
public static partial class MarkdownParser
{
    public static IReadOnlyList<MarkdownBlock> Parse(string source)
    {
        var lines = SplitLines(source);
        var blocks = new List<MarkdownBlock>();
        var index = 0;

        while (index < lines.Length)
        {
            var line = lines[index];
            var trimmed = line.Trim(' ', '\t');

            if (trimmed.Length == 0)
            {
                index++;
            }
            else if (trimmed.StartsWith("```") || trimmed.StartsWith("~~~"))
            {
                var fence = trimmed[..3];
                var language = trimmed.TrimStart('`', '~').Trim();
                var code = new List<string>();
                index++;
                while (index < lines.Length && !lines[index].Trim(' ', '\t').StartsWith(fence))
                {
                    code.Add(lines[index]);
                    index++;
                }
                index++;
                blocks.Add(new MarkdownBlock.CodeBlock(language, string.Join('\n', code)));
            }
            else if (HeadingPattern().Match(trimmed) is { Success: true } heading)
            {
                blocks.Add(new MarkdownBlock.Heading(heading.Groups[1].Length, heading.Groups[2].Value));
                index++;
            }
            else if (RulePattern().IsMatch(line))
            {
                blocks.Add(new MarkdownBlock.Rule());
                index++;
            }
            else if (StartsTable(index, lines))
            {
                var header = Cells(line);
                var rows = new List<IReadOnlyList<string>>();
                index += 2;
                while (index < lines.Length && lines[index].Contains('|') && !IsBlank(lines[index]))
                {
                    rows.Add(Cells(lines[index]));
                    index++;
                }
                blocks.Add(new MarkdownBlock.Table(header, rows));
            }
            else if (trimmed.StartsWith('>'))
            {
                var quoted = new List<string>();
                while (index < lines.Length)
                {
                    var quoteLine = lines[index].Trim(' ', '\t');
                    if (!quoteLine.StartsWith('>')) break;
                    quoted.Add(quoteLine.TrimStart('>', ' '));
                    index++;
                }
                blocks.Add(new MarkdownBlock.Quote(JoinParagraph(quoted)));
            }
            else if (ListItemAt(line, index) is not null)
            {
                var items = new List<ListItem>();
                while (index < lines.Length)
                {
                    if (ListItemAt(lines[index], index) is { } item)
                    {
                        items.Add(item);
                        index++;
                    }
                    else if (items.Count > 0 && !IsBlank(lines[index]) && char.IsWhiteSpace(lines[index][0]))
                    {
                        var last = items[^1];
                        items[^1] = last with { Text = last.Text + " " + lines[index].Trim(' ', '\t') };
                        index++;
                    }
                    else if (IsBlank(lines[index]) && index + 1 < lines.Length && ListItemAt(lines[index + 1], index + 1) is not null)
                    {
                        index++;
                    }
                    else
                    {
                        break;
                    }
                }
                blocks.Add(new MarkdownBlock.ListBlock(items));
            }
            else if (ImagePattern().Match(trimmed) is { Success: true } image)
            {
                blocks.Add(new MarkdownBlock.Image(image.Groups[1].Value, image.Groups[2].Value));
                index++;
            }
            else
            {
                var paragraph = new List<string>();
                while (index < lines.Length && !IsBlank(lines[index]) && (paragraph.Count == 0 || !StartsBlock(index, lines)))
                {
                    paragraph.Add(lines[index]);
                    index++;
                }
                blocks.Add(new MarkdownBlock.Paragraph(JoinParagraph(paragraph)));
            }
        }
        return blocks;
    }

    /// <summary>Ticks the <c>[ ]</c> task on a source line on or off.</summary>
    public static string ToggleTask(string text, int line)
    {
        var lines = text.Split('\n');
        if (line < 0 || line >= lines.Length) return text;
        var box = TaskBoxPattern().Match(lines[line]);
        if (!box.Success) return text;
        var replacement = box.Value == "[ ]" ? "[x]" : "[ ]";
        lines[line] = lines[line][..box.Index] + replacement + lines[line][(box.Index + box.Length)..];
        return string.Join('\n', lines);
    }

    /// <summary>Line breaks as <c>\n</c>, whatever the file or the text box used.</summary>
    public static string[] SplitLines(string source) =>
        source.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

    private static bool IsBlank(string line) => line.All(char.IsWhiteSpace);

    private static bool StartsBlock(int index, string[] lines)
    {
        var line = lines[index];
        var trimmed = line.Trim(' ', '\t');
        return trimmed.StartsWith("```") || trimmed.StartsWith("~~~") || trimmed.StartsWith('>')
            || HeadingPattern().IsMatch(trimmed)
            || RulePattern().IsMatch(line)
            || ListItemAt(line, index) is not null
            || StartsTable(index, lines);
    }

    private static bool StartsTable(int index, string[] lines) =>
        lines[index].Contains('|') && index + 1 < lines.Length && TableSeparatorPattern().IsMatch(lines[index + 1]);

    private static ListItem? ListItemAt(string line, int index)
    {
        var match = ListPattern().Match(line);
        if (!match.Success) return null;
        var indent = match.Groups[1].Value.Sum(c => c == '\t' ? 4 : 1);
        var marker = match.Groups[2].Value;
        var box = match.Groups[3].Value;
        var kind = box.Length > 0 ? ListKind.Task : char.IsDigit(marker[0]) ? ListKind.Number : ListKind.Bullet;
        var done = box.Contains('x', StringComparison.OrdinalIgnoreCase);
        return new ListItem(indent / 2, kind, marker, done, match.Groups[4].Value, index);
    }

    /// <summary>Joins soft-wrapped lines with spaces; two trailing spaces or a backslash keep the line break.</summary>
    private static string JoinParagraph(List<string> lines)
    {
        var result = new StringBuilder();
        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            var hardBreak = line.EndsWith("  ") || line.EndsWith('\\');
            var content = line.Trim(' ', '\t');
            if (content.EndsWith('\\')) content = content[..^1];
            result.Append(content);
            if (i < lines.Count - 1) result.Append(hardBreak ? '\n' : ' ');
        }
        return result.ToString();
    }

    private static IReadOnlyList<string> Cells(string line)
    {
        var row = line.Trim(' ', '\t');
        if (row.StartsWith('|')) row = row[1..];
        if (row.EndsWith('|')) row = row[..^1];
        return row.Split('|').Select(cell => cell.Trim(' ', '\t')).ToList();
    }

    [GeneratedRegex(@"^(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")]
    private static partial Regex HeadingPattern();

    [GeneratedRegex(@"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")]
    private static partial Regex RulePattern();

    [GeneratedRegex(@"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$")]
    private static partial Regex TableSeparatorPattern();

    /// <summary>Groups: 1 indent, 2 marker, 3 optional task box, 4 text.</summary>
    [GeneratedRegex(@"^([ \t]*)([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\][ \t]+)?(.*)$")]
    private static partial Regex ListPattern();

    [GeneratedRegex(@"^!\[([^\]]*)\]\(([^)\s]+)(?:[ \t]+""[^""]*"")?\)$")]
    private static partial Regex ImagePattern();

    [GeneratedRegex(@"\[[ xX]\]")]
    private static partial Regex TaskBoxPattern();
}
