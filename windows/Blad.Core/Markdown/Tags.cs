using System.Text.RegularExpressions;

namespace Blad.Core.Markdown;

/// <summary>`#tag` in a page. Tags gather pages across spaces: clicking one searches for it.</summary>
public static partial class Tags
{
    /// <summary>Reading mode turns `#tag` into a link with this scheme, which Blad handles itself.</summary>
    public const string UrlScheme = "blad-tag";

    /// <summary>`#tag` after a space or at the start of a line; group 2 is the name.
    /// A heading is `#` followed by a space, so it never matches here.</summary>
    [GeneratedRegex(@"(^|[\s(\[{>])#(\p{L}[\p{L}\p{N}_/-]*)")]
    public static partial Regex Pattern();

    public static string LinkTo(string tag) => $"{UrlScheme}:{Uri.EscapeDataString(tag)}";

    /// <summary>The tag a <c>blad-tag:</c> link points at, or null for any other link.</summary>
    public static string? TagName(string link) =>
        link.StartsWith(UrlScheme + ":", StringComparison.Ordinal)
            ? Uri.UnescapeDataString(link[(UrlScheme.Length + 1)..])
            : null;

    /// <summary>The tag names in a page, in the order they appear, without the <c>#</c>.</summary>
    public static IReadOnlyList<string> Names(string text) =>
        Pattern().Matches(text).Select(match => match.Groups[2].Value).ToList();
}
