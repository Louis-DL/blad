using System.Text.RegularExpressions;

namespace Blad.Core.Markdown;

/// <summary>A heading in a page. <see cref="Index"/> is its place among the headings, which is also
/// its place in reading mode; <see cref="Offset"/> is where its line starts in the text.</summary>
public sealed record Heading(int Index, int Level, string Title, int Offset);

/// <summary>The headings of a page, for the outline that jumps through a long note.</summary>
public static partial class Outline
{
    [GeneratedRegex(@"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")]
    private static partial Regex HeadingLine();

    /// <summary>The headings in the order they appear. Headings inside code blocks don't count.
    /// Offsets count one character per line break, the way the editor's text box does.</summary>
    public static IReadOnlyList<Heading> Headings(string text)
    {
        var headings = new List<Heading>();
        var insideCode = false;
        var offset = 0;

        foreach (var line in MarkdownParser.SplitLines(text))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("```") || trimmed.StartsWith("~~~"))
            {
                insideCode = !insideCode;
            }
            else if (!insideCode && HeadingLine().Match(trimmed) is { Success: true } match)
            {
                headings.Add(new Heading(headings.Count, match.Groups[1].Length, match.Groups[2].Value, offset));
            }
            offset += line.Length + 1;
        }
        return headings;
    }
}
