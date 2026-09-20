using System.Text.RegularExpressions;

namespace Blad.Core.Markdown;

[Flags]
public enum InlineStyle
{
    None = 0,
    Bold = 1,
    Italic = 2,
    Code = 4,
    Strike = 8,
}

/// <summary>A piece of text in one style. <see cref="Link"/> is a URL or path, or <c>blad-page:Name</c> for a [[page]].</summary>
public sealed record InlineRun(string Text, InlineStyle Style, string? Link = null);

/// <summary>Splits a line of markdown into styled runs, the way reading mode shows it.</summary>
public static partial class InlineParser
{
    private enum Token { Code, WikiLink, Image, Link, Url, Tag, Bold, ItalicStar, ItalicUnderscore, Strike }

    // Earlier in this list wins when two tokens start at the same place.
    private static readonly (Token Kind, Regex Pattern)[] Tokens =
    [
        (Token.Code, CodePattern()),
        (Token.WikiLink, WikiLinks.Pattern()),
        (Token.Image, ImagePattern()),
        (Token.Link, LinkPattern()),
        (Token.Url, UrlPattern()),
        (Token.Tag, Tags.Pattern()),
        (Token.Bold, BoldPattern()),
        (Token.ItalicStar, ItalicStarPattern()),
        (Token.ItalicUnderscore, ItalicUnderscorePattern()),
        (Token.Strike, StrikePattern()),
    ];

    public static IReadOnlyList<InlineRun> Parse(string text)
    {
        var runs = new List<InlineRun>();
        Append(text, InlineStyle.None, null, runs);
        return Merge(runs);
    }

    private static void Append(string text, InlineStyle style, string? link, List<InlineRun> runs)
    {
        var position = 0;
        while (position < text.Length)
        {
            if (Next(text, position) is not var (kind, match))
            {
                runs.Add(new InlineRun(text[position..], style, link));
                return;
            }
            if (match.Index > position)
            {
                runs.Add(new InlineRun(text[position..match.Index], style, link));
            }

            switch (kind)
            {
                case Token.Code:
                    runs.Add(new InlineRun(match.Groups[2].Value, style | InlineStyle.Code, link));
                    break;
                case Token.WikiLink:
                    var page = match.Groups[1].Value.Trim();
                    var shown = match.Groups[2].Success ? match.Groups[2].Value : page;
                    runs.Add(new InlineRun(shown, style, WikiLinks.LinkTo(page)));
                    break;
                case Token.Tag:
                    // Group 1 is the space before the tag, which isn't part of the link.
                    if (match.Groups[1].Length > 0) runs.Add(new InlineRun(match.Groups[1].Value, style, link));
                    runs.Add(new InlineRun("#" + match.Groups[2].Value, style, Tags.LinkTo(match.Groups[2].Value)));
                    break;
                case Token.Image:
                    // Images inside a sentence (like badges) show their description.
                    runs.Add(new InlineRun(match.Groups[1].Value, style, link));
                    break;
                case Token.Link:
                    Append(match.Groups[1].Value, style, match.Groups[2].Value, runs);
                    break;
                case Token.Url:
                    runs.Add(new InlineRun(match.Value, style, match.Value));
                    break;
                case Token.Bold:
                    Append(match.Groups[2].Value, style | InlineStyle.Bold, link, runs);
                    break;
                case Token.ItalicStar:
                case Token.ItalicUnderscore:
                    Append(match.Groups[1].Value, style | InlineStyle.Italic, link, runs);
                    break;
                case Token.Strike:
                    Append(match.Groups[1].Value, style | InlineStyle.Strike, link, runs);
                    break;
            }
            position = match.Index + match.Length;
        }
    }

    private static (Token Kind, Match Match)? Next(string text, int position)
    {
        (Token Kind, Match Match)? best = null;
        foreach (var (kind, pattern) in Tokens)
        {
            var match = pattern.Match(text, position);
            if (match.Success && match.Length > 0 && (best is null || match.Index < best.Value.Match.Index))
            {
                best = (kind, match);
            }
        }
        return best;
    }

    private static List<InlineRun> Merge(List<InlineRun> runs)
    {
        var merged = new List<InlineRun>();
        foreach (var run in runs.Where(run => run.Text.Length > 0))
        {
            if (merged.Count > 0 && merged[^1].Style == run.Style && merged[^1].Link == run.Link)
            {
                merged[^1] = merged[^1] with { Text = merged[^1].Text + run.Text };
            }
            else
            {
                merged.Add(run);
            }
        }
        return merged;
    }

    [GeneratedRegex(@"(`+)(?!`)(.+?)(?<!`)\1(?!`)")]
    private static partial Regex CodePattern();

    [GeneratedRegex(@"!\[([^\]\n]*)\]\(([^)\s]+)(?:\s+""[^""]*"")?\)")]
    private static partial Regex ImagePattern();

    [GeneratedRegex(@"\[([^\]\n]+)\]\(([^)\s]+)(?:\s+""[^""]*"")?\)")]
    private static partial Regex LinkPattern();

    [GeneratedRegex(@"(?<![(<\w/])https?://[^\s)>\]]+")]
    private static partial Regex UrlPattern();

    [GeneratedRegex(@"(\*\*|__)(?=\S)(.+?)(?<=\S)\1")]
    private static partial Regex BoldPattern();

    [GeneratedRegex(@"(?<![*\\\w])\*(?![\s*])(.+?)(?<![\s*\\])\*(?![*\w])")]
    private static partial Regex ItalicStarPattern();

    [GeneratedRegex(@"(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])")]
    private static partial Regex ItalicUnderscorePattern();

    [GeneratedRegex(@"~~(?=\S)(.+?)(?<=\S)~~")]
    private static partial Regex StrikePattern();
}
