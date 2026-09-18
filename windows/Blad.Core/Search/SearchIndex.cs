using System.Globalization;
using Blad.Core.Pages;

namespace Blad.Core.Search;

/// <summary>One markdown page with its contents, for searching and finding links.</summary>
/// <param name="Location">Space and folders, e.g. "Wiskunde › Hoofdstuk 2".</param>
public sealed record SearchEntry(string Path, string Title, string Location, string Text, DateTime Modified);

/// <param name="Snippet">The text around a match inside the page; null when the title matched.</param>
public sealed record SearchResult(SearchEntry Entry, string? Snippet);

public static class SearchIndex
{
    private const long MaxFileSize = 1_000_000;
    private const int MaxFiles = 5_000;
    private const CompareOptions Loose = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace;

    /// <summary>Reads every page in the spaces, newest first. Open pages use their unsaved text.</summary>
    public static List<SearchEntry> Build(IEnumerable<string> spaces, IReadOnlyDictionary<string, string>? openTexts = null)
    {
        var entries = new List<SearchEntry>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var space in spaces)
        {
            var parent = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(space)) ?? space;
            foreach (var file in PageFiles.Enumerate(space))
            {
                if (entries.Count >= MaxFiles) break;
                if (!seen.Add(file)) continue;

                var info = new FileInfo(file);
                if (info.Length > MaxFileSize) continue;

                string text;
                if (openTexts is not null && openTexts.TryGetValue(file, out var open))
                {
                    text = open;
                }
                else
                {
                    try
                    {
                        text = File.ReadAllText(file).Replace("\r\n", "\n");
                    }
                    catch (IOException)
                    {
                        continue;
                    }
                    catch (UnauthorizedAccessException)
                    {
                        continue;
                    }
                }

                var folder = Path.GetRelativePath(parent, Path.GetDirectoryName(file) ?? parent);
                var location = string.Join(" › ", folder.Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries));
                entries.Add(new SearchEntry(file, Path.GetFileNameWithoutExtension(file), location, text, info.LastWriteTimeUtc));
            }
        }
        return entries.OrderByDescending(entry => entry.Modified).ToList();
    }

    /// <summary>Title matches rank above matches in the text. An empty query lists recent pages.</summary>
    public static IReadOnlyList<SearchResult> Search(string query, IReadOnlyList<SearchEntry> entries)
    {
        query = query.Trim();
        if (query.Length == 0) return entries.Take(10).Select(entry => new SearchResult(entry, null)).ToList();

        var compare = CultureInfo.InvariantCulture.CompareInfo;
        var scored = new List<(SearchResult Result, int Score)>();
        foreach (var entry in entries)
        {
            var score = 0;
            var titleIndex = compare.IndexOf(entry.Title, query, Loose);
            if (titleIndex >= 0) score = titleIndex == 0 ? 300 : 200;
            else if (query.Length > 1 && IsSubsequence(query, entry.Title)) score = 100;

            string? snippet = null;
            if (score == 0)
            {
                var index = compare.IndexOf(entry.Text, query, Loose, out var length);
                if (index >= 0)
                {
                    snippet = Snippet(entry.Text, index, length);
                    score = 50;
                }
            }
            if (score > 0) scored.Add((new SearchResult(entry, snippet), score));
        }

        return scored
            .OrderByDescending(item => item.Score)
            .ThenByDescending(item => item.Result.Entry.Modified)
            .Take(50)
            .Select(item => item.Result)
            .ToList();
    }

    /// <summary>"wkp" matches "Werkplan": the letters appear in order.</summary>
    private static bool IsSubsequence(string query, string title)
    {
        var letters = query.Where(c => !char.IsWhiteSpace(c)).Select(char.ToLowerInvariant).ToArray();
        var next = 0;
        foreach (var c in title.ToLowerInvariant())
        {
            if (next < letters.Length && c == letters[next]) next++;
        }
        return next == letters.Length;
    }

    private static string Snippet(string text, int index, int length)
    {
        var start = Math.Max(0, index - 40);
        var end = Math.Min(text.Length, index + length + 90);
        var excerpt = text[start..end].Replace('\n', ' ').Trim();
        return (start > 0 ? "…" : "") + excerpt + (end < text.Length ? "…" : "");
    }
}
