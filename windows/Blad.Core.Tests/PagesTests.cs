using Blad.Core.Images;
using Blad.Core.Pages;
using Blad.Core.Search;

namespace Blad.Core.Tests;

/// <summary>A throwaway folder, so file tests never touch real notes.</summary>
public sealed class TemporaryFolder : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "blad-tests-" + Guid.NewGuid().ToString("N"));

    public TemporaryFolder() => Directory.CreateDirectory(Path);

    public string Write(string relative, string contents)
    {
        var file = System.IO.Path.Combine(Path, relative);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file)!);
        File.WriteAllText(file, contents);
        return file;
    }

    public void Dispose() => Directory.Delete(Path, recursive: true);
}

public class PageFilesTests
{
    [Fact]
    public void ShowsFoldersWithPagesAndHidesTheRest()
    {
        using var space = new TemporaryFolder();
        space.Write("Welkom.md", "# Welkom");
        space.Write("Hoofdstuk 1/Samenvatting.md", "tekst");
        space.Write("src/main.swift", "print()");
        space.Write("node_modules/pakket/README.md", "niet tonen");
        space.Write(".git/HEAD", "ref");
        Directory.CreateDirectory(System.IO.Path.Combine(space.Path, "Nieuwe map"));

        var nodes = PageFiles.Scan(space.Path);

        Assert.Equal(["Hoofdstuk 1", "Nieuwe map", "Welkom"], nodes.Select(n => n.Name));
        Assert.Equal("Samenvatting", Assert.Single(nodes[0].Children).Name);
    }

    [Fact]
    public void UniqueNamesCountUp()
    {
        using var space = new TemporaryFolder();
        space.Write("Naamloos.md", "");
        Assert.Equal(System.IO.Path.Combine(space.Path, "Naamloos 2.md"), PageFiles.UniquePath(space.Path, "Naamloos", ".md"));
        Assert.Equal("Plan- school", PageFiles.SafeName("Plan: school"));
    }
}

public class PageDocumentTests
{
    [Fact]
    public void KeepsWindowsLineEndingsWhenSaving()
    {
        using var space = new TemporaryFolder();
        var file = space.Write("README.md", "# Titel\r\nTekst\r\n");

        var document = PageDocument.Open(file);
        Assert.Equal("# Titel\nTekst\n", document.Text);
        Assert.Equal("Titel", document.FirstHeading());

        Assert.True(document.Edit("# Titel\rMeer tekst\n"));
        document.Save();

        Assert.Equal("# Titel\r\nMeer tekst\r\n", File.ReadAllText(file));
        Assert.False(document.IsDirty);
        Assert.Equal(3, document.WordCount);
    }

    [Fact]
    public void ReloadsChangesFromOtherAppsOnlyWhenNothingIsUnsaved()
    {
        using var space = new TemporaryFolder();
        var file = space.Write("Pagina.md", "een");
        var document = PageDocument.Open(file);

        File.WriteAllText(file, "twee");
        Assert.True(document.ReloadFromDisk());
        Assert.Equal("twee", document.Text);

        document.Edit("drie");
        File.WriteAllText(file, "vier");
        Assert.False(document.ReloadFromDisk());
        Assert.Equal("drie", document.Text);
    }
}

public class SearchIndexTests
{
    [Fact]
    public void RanksTitlesAboveTextAndShowsWhereTextMatched()
    {
        using var space = new TemporaryFolder();
        space.Write("Ideeën.md", "Lijstje");
        space.Write("School/Planning.md", "Het idee voor het examen.");

        var entries = SearchIndex.Build([space.Path]);
        var results = SearchIndex.Search("idee", entries);

        Assert.Equal(["Ideeën", "Planning"], results.Select(r => r.Entry.Title));
        Assert.Null(results[0].Snippet);
        Assert.Contains("idee voor het examen", results[1].Snippet);
        Assert.EndsWith("School", results[1].Entry.Location);
    }
}

public class ImageStoreTests
{
    [Fact]
    public void SavesPastedImagesNextToThePage()
    {
        using var space = new TemporaryFolder();
        var page = space.Write("Mijn pagina.md", "");

        var markdown = ImageStore.SaveImage([1, 2, 3], "PNG", page);

        Assert.Matches(@"^!\[\]\(assets/mijn-pagina-\d{8}-\d{6}\.png\)$", markdown);
        Assert.Single(Directory.GetFiles(System.IO.Path.Combine(space.Path, "assets")));
    }

    [Fact]
    public void CopiesDroppedImagesAndNeverOverwrites()
    {
        using var space = new TemporaryFolder();
        var page = space.Write("Pagina.md", "");
        using var elsewhere = new TemporaryFolder();
        var photo = elsewhere.Write("Vakantie foto.jpg", "jpg");

        Assert.Equal("![Vakantie foto](assets/vakantie-foto.jpg)", ImageStore.AddImageFile(photo, page));
        Assert.Equal("![Vakantie foto](assets/vakantie-foto-2.jpg)", ImageStore.AddImageFile(photo, page));
        Assert.Equal(System.IO.Path.Combine(space.Path, "assets", "vakantie-foto.jpg"), ImageStore.Resolve("assets/vakantie-foto.jpg", page));
    }
}
