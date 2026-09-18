namespace Blad.Core.Pages;

public enum PageSort { Name, Modified }

/// <summary>A folder or markdown page inside a space, as shown in the sidebar.</summary>
public sealed record PageNode(string Path, bool IsFolder, DateTime Modified, IReadOnlyList<PageNode> Children)
{
    public string Name => IsFolder ? System.IO.Path.GetFileName(Path) : System.IO.Path.GetFileNameWithoutExtension(Path);
}

public static class PageFiles
{
    private static readonly HashSet<string> MarkdownExtensions = new(StringComparer.OrdinalIgnoreCase) { ".md", ".markdown", ".mdown", ".mkd" };

    /// <summary>Build output and dependencies: never where notes live, and slow to walk through.</summary>
    private static readonly HashSet<string> SkippedFolders = new(StringComparer.OrdinalIgnoreCase)
    {
        "node_modules", "build", "bin", "obj", "DerivedData", "Pods", "dist", "vendor",
    };

    public static bool IsMarkdown(string path) => MarkdownExtensions.Contains(Path.GetExtension(path));

    /// <summary>
    /// The folders and markdown pages below <paramref name="folder"/>, folders first. Folders without any
    /// markdown are hidden so code repositories stay readable, unless they are empty (a new folder should show).
    /// </summary>
    public static IReadOnlyList<PageNode> Scan(string folder, PageSort sort = PageSort.Name, int depth = 0)
    {
        if (depth >= 10 || !Directory.Exists(folder)) return [];

        var folders = new List<PageNode>();
        var pages = new List<PageNode>();
        foreach (var entry in SafeEntries(folder))
        {
            var name = Path.GetFileName(entry);
            if (IsHidden(entry, name)) continue;

            if (Directory.Exists(entry))
            {
                if (SkippedFolders.Contains(name)) continue;
                var children = Scan(entry, sort, depth + 1);
                if (children.Count > 0 || IsEmpty(entry))
                {
                    folders.Add(new PageNode(entry, true, Directory.GetLastWriteTimeUtc(entry), children));
                }
            }
            else if (IsMarkdown(entry))
            {
                pages.Add(new PageNode(entry, false, File.GetLastWriteTimeUtc(entry), []));
            }
        }
        return [.. Sorted(folders, sort), .. Sorted(pages, sort)];
    }

    /// <summary>Every markdown page below <paramref name="folder"/>, skipping the same folders as <see cref="Scan"/>.</summary>
    public static IEnumerable<string> Enumerate(string folder, int depth = 0)
    {
        if (depth >= 10 || !Directory.Exists(folder)) yield break;
        foreach (var entry in SafeEntries(folder))
        {
            var name = Path.GetFileName(entry);
            if (IsHidden(entry, name)) continue;
            if (Directory.Exists(entry))
            {
                if (SkippedFolders.Contains(name)) continue;
                foreach (var page in Enumerate(entry, depth + 1)) yield return page;
            }
            else if (IsMarkdown(entry))
            {
                yield return entry;
            }
        }
    }

    /// <summary>"Naamloos.md", or "Naamloos 2.md" when that exists, and so on.</summary>
    public static string UniquePath(string folder, string name, string? extension)
    {
        for (var number = 1; ; number++)
        {
            var candidate = Path.Combine(folder, (number == 1 ? name : $"{name} {number}") + (extension ?? ""));
            if (!File.Exists(candidate) && !Directory.Exists(candidate)) return candidate;
        }
    }

    /// <summary>A name that is safe as a file name on Windows, macOS and iOS alike.</summary>
    public static string SafeName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars().Concat(['/', '\\', ':', '*', '?', '"', '<', '>', '|']).ToHashSet();
        var cleaned = new string(name.Select(c => invalid.Contains(c) ? '-' : c).ToArray()).Trim().TrimEnd('.');
        return cleaned.Length > 80 ? cleaned[..80] : cleaned;
    }

    private static IEnumerable<PageNode> Sorted(List<PageNode> nodes, PageSort sort) =>
        sort == PageSort.Modified
            ? nodes.OrderByDescending(node => node.Modified).ThenBy(node => node.Name, StringComparer.CurrentCultureIgnoreCase)
            : nodes.OrderBy(node => node.Name, StringComparer.CurrentCultureIgnoreCase);

    private static bool IsHidden(string path, string name)
    {
        if (name.StartsWith('.')) return true;
        try
        {
            return File.GetAttributes(path).HasFlag(FileAttributes.Hidden);
        }
        catch (IOException)
        {
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return true;
        }
    }

    private static bool IsEmpty(string folder) =>
        !SafeEntries(folder).Any(entry => !Path.GetFileName(entry).StartsWith('.'));

    private static IEnumerable<string> SafeEntries(string folder)
    {
        try
        {
            return Directory.GetFileSystemEntries(folder);
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }
}
