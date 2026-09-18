using Blad.Core.Markdown;
using Blad.Core.Pages;
using Blad.Core.Search;
using Microsoft.UI.Dispatching;
using Windows.Storage;

namespace Blad;

/// <summary>A page as the link picker and search show it.</summary>
public sealed record PageInfo(string Path, string Title, string Location, DateTime Modified);

/// <summary>
/// Spaces, their pages and the open documents. A space is a plain folder, one per project or course,
/// so pages stay .md files that also open on the Mac, the iPhone, in git or in any editor.
/// </summary>
public sealed class Library
{
    public static Library Shared { get; } = new();

    private readonly Dictionary<string, PageDocument> documents = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<PageNode>> trees = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<PageDocument> unsaved = [];
    private DispatcherQueueTimer? saveTimer;

    /// <summary>The page tree changed; the sidebar rebuilds.</summary>
    public event Action? TreesChanged;

    /// <summary>A page or folder moved from the first path to the second; open tabs follow it.</summary>
    public event Action<string, string>? PageMoved;

    public event Action<string>? ErrorOccurred;

    public IReadOnlyList<string> Spaces => AppSettings.Current.Spaces;

    public IReadOnlyList<PageNode> Tree(string space) => trees.TryGetValue(space, out var nodes) ? nodes : [];

    private static PageSort Sort => AppSettings.Current.Sort == "modified" ? PageSort.Modified : PageSort.Name;

    // MARK: Spaces

    public async Task RefreshAsync()
    {
        var sort = Sort;
        var spaces = Spaces.ToList();
        var scanned = await Task.Run(() => spaces.Select(space => (space, PageFiles.Scan(space, sort))).ToList());
        trees.Clear();
        foreach (var (space, nodes) in scanned) trees[space] = nodes;
        foreach (var document in documents.Values) document.ReloadFromDisk();
        TreesChanged?.Invoke();
    }

    public void AddSpace(string folder)
    {
        if (Spaces.Any(space => SamePath(space, folder))) return;
        AppSettings.Current.Spaces.Add(folder);
        AppSettings.Current.Save();
        _ = RefreshAsync();
    }

    /// <summary>Makes a folder for a new project or course inside <paramref name="parent"/> and opens it as a space.</summary>
    public string? CreateSpace(string name, string parent)
    {
        var clean = PageFiles.SafeName(name);
        if (clean.Length == 0) return null;
        try
        {
            var folder = PageFiles.UniquePath(parent, clean, null);
            Directory.CreateDirectory(folder);
            AddSpace(folder);
            return folder;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Report($"Kon de ruimte {clean} niet maken.", exception);
            return null;
        }
    }

    public void RemoveSpace(string space)
    {
        AppSettings.Current.Spaces.RemoveAll(item => SamePath(item, space));
        AppSettings.Current.Save();
        trees.Remove(space);
        TreesChanged?.Invoke();
    }

    public string? SpaceContaining(string path) => Spaces.FirstOrDefault(space => IsInside(path, space));

    // MARK: Pages

    public PageDocument? Document(string path)
    {
        if (documents.TryGetValue(path, out var open)) return open;
        try
        {
            var document = PageDocument.Open(path);
            documents[path] = document;
            return document;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Report($"Kon {Path.GetFileName(path)} niet openen.", exception);
            return null;
        }
    }

    /// <summary>Saves the page shortly after typing stops.</summary>
    public void ScheduleSave(PageDocument document)
    {
        unsaved.Add(document);
        if (saveTimer is null)
        {
            saveTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
            saveTimer.Interval = TimeSpan.FromMilliseconds(700);
            saveTimer.IsRepeating = false;
            saveTimer.Tick += (_, _) => SaveAll();
        }
        saveTimer.Stop();
        saveTimer.Start();
    }

    public void SaveAll()
    {
        foreach (var document in unsaved.ToList())
        {
            try
            {
                document.Save();
                unsaved.Remove(document);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                Report($"Kon {document.Title} niet bewaren.", exception);
            }
        }
    }

    /// <summary>A new, empty page. It takes its name from its first heading when you leave it.</summary>
    public string? NewPage(string? folder)
    {
        folder ??= Spaces.FirstOrDefault();
        if (folder is null) return null;
        try
        {
            var path = PageFiles.UniquePath(folder, "Naamloos", ".md");
            File.WriteAllText(path, "");
            if (Document(path) is { } document) document.NamesItselfFromHeading = true;
            _ = RefreshAsync();
            return path;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Report("Kon geen nieuwe pagina maken.", exception);
            return null;
        }
    }

    public string? NewFolder(string parent)
    {
        try
        {
            var path = PageFiles.UniquePath(parent, "Nieuwe map", null);
            Directory.CreateDirectory(path);
            _ = RefreshAsync();
            return path;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Report("Kon geen map maken.", exception);
            return null;
        }
    }

    /// <summary>Renames a new page after its first heading. Done when leaving the page, so typing is never interrupted.</summary>
    public void FinishEditing(PageDocument document)
    {
        SaveAll();
        if (!document.NamesItselfFromHeading || document.FirstHeading() is not { } heading) return;
        var name = PageFiles.SafeName(heading);
        if (name.Length == 0 || name == document.Title) return;
        var destination = Path.Combine(Path.GetDirectoryName(document.Path)!, name + ".md");
        if (!File.Exists(destination)) Move(document.Path, destination, keepsAutoNaming: true);
    }

    public string? Rename(string path, string name)
    {
        var clean = PageFiles.SafeName(name);
        if (clean.Length == 0) return null;
        var isFolder = Directory.Exists(path);
        var destination = Path.Combine(Path.GetDirectoryName(path)!, clean + (isFolder ? "" : Path.GetExtension(path)));
        return SamePath(destination, path) ? path : Move(path, destination, keepsAutoNaming: false);
    }

    /// <summary>Moves a page or folder to the Recycle Bin, so it can be put back.</summary>
    public async Task DeleteAsync(string path)
    {
        foreach (var key in documents.Keys.Where(key => IsInside(key, path)).ToList())
        {
            unsaved.Remove(documents[key]);
            documents.Remove(key);
        }
        try
        {
            IStorageItem item = Directory.Exists(path)
                ? await StorageFolder.GetFolderFromPathAsync(path)
                : await StorageFile.GetFileFromPathAsync(path);
            await item.DeleteAsync(StorageDeleteOption.Default);
        }
        catch (Exception exception)
        {
            Report($"Kon {Path.GetFileName(path)} niet verwijderen.", exception);
        }
        await RefreshAsync();
    }

    private string? Move(string source, string destination, bool keepsAutoNaming)
    {
        try
        {
            if (Directory.Exists(source)) Directory.Move(source, destination);
            else File.Move(source, destination);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Report("Kon de naam niet wijzigen.", exception);
            return null;
        }

        foreach (var (path, document) in documents.Where(entry => IsInside(entry.Key, source)).ToList())
        {
            var moved = destination + path[source.Length..];
            document.MoveTo(moved);
            if (SamePath(path, source) && !keepsAutoNaming) document.NamesItselfFromHeading = false;
            documents.Remove(path);
            documents[moved] = document;
        }
        PageMoved?.Invoke(source, destination);
        _ = RefreshAsync();
        return destination;
    }

    // MARK: Links and search

    /// <summary>Every page in the spaces, most recently changed first: what the link picker offers.</summary>
    public IReadOnlyList<PageInfo> Pages()
    {
        var pages = new List<PageInfo>();
        void Walk(IEnumerable<PageNode> nodes, string location)
        {
            foreach (var node in nodes)
            {
                if (node.IsFolder) Walk(node.Children, location + " › " + node.Name);
                else pages.Add(new PageInfo(node.Path, node.Name, location, node.Modified));
            }
        }
        foreach (var space in Spaces) Walk(Tree(space), Path.GetFileName(space));
        return pages.OrderByDescending(page => page.Modified).ToList();
    }

    /// <summary>The page a [[link]] points to, preferring the linking page's own space. A link to a page that
    /// doesn't exist yet creates it next to the linking page.</summary>
    public string? OpenPage(string name, string fromPath)
    {
        var target = Path.GetFileName(name.Trim());
        if (target.Length == 0) return null;

        var matches = Pages().Where(page => WikiLinks.SameName(page.Title, target)).ToList();
        var fromSpace = SpaceContaining(fromPath);
        var match = matches.FirstOrDefault(page => SpaceContaining(page.Path) == fromSpace) ?? matches.FirstOrDefault();
        if (match is not null) return match.Path;

        try
        {
            var path = Path.Combine(Path.GetDirectoryName(fromPath)!, PageFiles.SafeName(target) + ".md");
            File.WriteAllText(path, $"# {target}\n\n");
            _ = RefreshAsync();
            return path;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            Report($"Kon de pagina {target} niet maken.", exception);
            return null;
        }
    }

    public Task<List<SearchEntry>> BuildSearchIndexAsync()
    {
        var spaces = Spaces.ToList();
        var openTexts = documents.ToDictionary(entry => entry.Key, entry => entry.Value.Text, StringComparer.OrdinalIgnoreCase);
        return Task.Run(() => SearchIndex.Build(spaces, openTexts));
    }

    public async Task<IReadOnlyList<Backlink>> BacklinksAsync(PageDocument document)
    {
        var entries = await BuildSearchIndexAsync();
        var (title, path) = (document.Title, document.Path);
        return await Task.Run(() => WikiLinks.Backlinks(title, path, entries));
    }

    // MARK: Helpers

    public static bool SamePath(string a, string b) =>
        string.Equals(Path.TrimEndingDirectorySeparator(a), Path.TrimEndingDirectorySeparator(b), StringComparison.OrdinalIgnoreCase);

    public static bool IsInside(string path, string folder) =>
        SamePath(path, folder) || path.StartsWith(Path.TrimEndingDirectorySeparator(folder) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

    private void Report(string message, Exception exception) => ErrorOccurred?.Invoke($"{message}\n\n{exception.Message}");
}
