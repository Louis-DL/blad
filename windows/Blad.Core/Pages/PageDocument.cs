using Blad.Core.Markdown;

namespace Blad.Core.Pages;

/// <summary>
/// One open markdown file. Text uses <c>\n</c> inside Blad; the file keeps the line endings it had,
/// so a README checked out with Windows line endings doesn't show up as changed in git.
/// </summary>
public sealed class PageDocument
{
    private readonly string lineEnding;

    public string Path { get; private set; }
    public string Text { get; private set; }
    public bool IsDirty { get; private set; }
    public int WordCount { get; private set; }

    /// <summary>Pages made in Blad take their file name from the first heading, until renamed by hand.</summary>
    public bool NamesItselfFromHeading { get; set; }

    /// <summary>Shows the rendered page instead of the markdown source.</summary>
    public bool IsReading { get; set; }

    public string Title => System.IO.Path.GetFileNameWithoutExtension(Path);

    public event Action<PageDocument>? Saved;

    private PageDocument(string path, string contents)
    {
        Path = path;
        lineEnding = contents.Contains("\r\n") ? "\r\n" : "\n";
        Text = Normalize(contents);
        WordCount = WordCounter.Count(Text);
    }

    public static PageDocument Open(string path) => new(path, File.ReadAllText(path));

    /// <summary>Takes the editor's text; returns whether anything changed.</summary>
    public bool Edit(string text)
    {
        text = Normalize(text);
        if (text == Text) return false;
        Text = text;
        IsDirty = true;
        WordCount = WordCounter.Count(text);
        return true;
    }

    public void ToggleTask(int line) => Edit(MarkdownParser.ToggleTask(Text, line));

    public void Save()
    {
        if (!IsDirty) return;
        var contents = lineEnding == "\n" ? Text : Text.Replace("\n", lineEnding);
        // Write next to the file and swap it in, so a crash never leaves half a page.
        var temporary = Path + ".blad-saving";
        File.WriteAllText(temporary, contents);
        File.Move(temporary, Path, overwrite: true);
        IsDirty = false;
        Saved?.Invoke(this);
    }

    /// <summary>Picks up changes made by other apps, unless there are unsaved edits here. Returns whether the text changed.</summary>
    public bool ReloadFromDisk()
    {
        if (IsDirty) return false;
        string contents;
        try
        {
            contents = Normalize(File.ReadAllText(Path));
        }
        catch (IOException)
        {
            return false;
        }
        if (contents == Text) return false;
        Text = contents;
        WordCount = WordCounter.Count(contents);
        return true;
    }

    public void MoveTo(string path) => Path = path;

    /// <summary>The first heading, if the page starts with one: what a new page is named after.</summary>
    public string? FirstHeading()
    {
        var line = MarkdownParser.SplitLines(Text).FirstOrDefault(line => line.Trim().Length > 0)?.Trim();
        return line is not null && line.StartsWith('#') ? line.TrimStart('#').Trim() : null;
    }

    private static string Normalize(string text) => text.Replace("\r\n", "\n").Replace('\r', '\n');
}
