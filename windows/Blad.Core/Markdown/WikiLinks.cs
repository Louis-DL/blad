using System.Globalization;
using System.Text.RegularExpressions;
using Blad.Core.Search;

namespace Blad.Core.Markdown;

/// <summary>A page that links to the current page with [[…]], and the line the link is on.</summary>
public sealed record Backlink(string Path, string Title, string Snippet);

public static partial class WikiLinks
{
    /// <summary>Reading mode turns [[Page]] into a link with this scheme, which Blad handles itself.</summary>
    public const string UrlScheme = "blad-page";

    /// <summary>[[Page]] or [[Page|shown text]]: group 1 is the page, group 2 the optional text.</summary>
    [GeneratedRegex(@"\[\[([^\[\]\n|]+)(?:\|([^\[\]\n]+))?\]\]")]
    public static partial Regex Pattern();

    public static string LinkTo(string page) => $"{UrlScheme}:{Uri.EscapeDataString(page)}";

    /// <summary>The page a <c>blad-page:</c> link points to, or null for any other link.</summary>
    public static string? PageName(string link) =>
        link.StartsWith(UrlScheme + ":", StringComparison.Ordinal)
            ? Uri.UnescapeDataString(link[(UrlScheme.Length + 1)..])
            : null;

    /// <summary>Page names match ignoring case and accents, so [[ideeen]] finds "Ideeën".</summary>
    public static bool SameName(string a, string b) =>
        string.Compare(a, b, CultureInfo.InvariantCulture, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) == 0;

    public static IReadOnlyList<Backlink> Backlinks(string title, string excludingPath, IEnumerable<SearchEntry> entries)
    {
        var backlinks = new List<Backlink>();
        foreach (var entry in entries)
        {
            if (string.Equals(entry.Path, excludingPath, StringComparison.OrdinalIgnoreCase)) continue;
            foreach (Match match in Pattern().Matches(entry.Text))
            {
                var target = Path.GetFileName(match.Groups[1].Value.Trim());
                if (!SameName(target, title)) continue;
                backlinks.Add(new Backlink(entry.Path, entry.Title, LineAround(entry.Text, match.Index)));
                break;
            }
        }
        return backlinks;
    }

    private static string LineAround(string text, int index)
    {
        var start = text.LastIndexOf('\n', Math.Max(0, index - 1)) + 1;
        var end = text.IndexOf('\n', index);
        return text[start..(end < 0 ? text.Length : end)].Trim();
    }
}
