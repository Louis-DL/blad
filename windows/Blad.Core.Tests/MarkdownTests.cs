using Blad.Core.Export;
using Blad.Core.Markdown;
using Blad.Core.Search;

namespace Blad.Core.Tests;

public class MarkdownParserTests
{
    [Fact]
    public void ParsesTheBlocksOfAPage()
    {
        var blocks = MarkdownParser.Parse("""
            # Welkom

            Een **rustige** plek.
            Tweede regel.

            - een
            - [x] klaar
            1. eerst

            > citaat

            ```swift
            let blad = 1
            ```

            | A | B |
            | --- | --- |
            | 1 | 2 |

            ![foto](assets/foto.png)

            ---
            """);

        Assert.Collection(blocks,
            b => Assert.Equal(new MarkdownBlock.Heading(1, "Welkom"), b),
            b => Assert.Equal(new MarkdownBlock.Paragraph("Een **rustige** plek. Tweede regel."), b),
            b =>
            {
                var list = Assert.IsType<MarkdownBlock.ListBlock>(b);
                Assert.Equal([ListKind.Bullet, ListKind.Task, ListKind.Number], list.Items.Select(i => i.Kind));
                Assert.True(list.Items[1].Done);
                Assert.Equal("klaar", list.Items[1].Text);
            },
            b => Assert.Equal(new MarkdownBlock.Quote("citaat"), b),
            b => Assert.Equal(new MarkdownBlock.CodeBlock("swift", "let blad = 1"), b),
            b =>
            {
                var table = Assert.IsType<MarkdownBlock.Table>(b);
                Assert.Equal(["A", "B"], table.Header);
                Assert.Equal(["1", "2"], table.Rows[0]);
            },
            b => Assert.Equal(new MarkdownBlock.Image("foto", "assets/foto.png"), b),
            b => Assert.IsType<MarkdownBlock.Rule>(b));
    }

    [Fact]
    public void TogglesATaskOnItsLine()
    {
        const string text = "# Taken\n- [ ] boodschappen\n- [x] afwas";
        Assert.Equal("# Taken\n- [x] boodschappen\n- [x] afwas", MarkdownParser.ToggleTask(text, 1));
        Assert.Equal("# Taken\n- [ ] boodschappen\n- [ ] afwas", MarkdownParser.ToggleTask(text, 2));
        Assert.Equal(text, MarkdownParser.ToggleTask(text, 0));
    }
}

public class InlineParserTests
{
    [Fact]
    public void SplitsTextIntoStyledRuns()
    {
        var runs = InlineParser.Parse("Een **vette** en *schuine* zin met `code`.");
        Assert.Equal(
            [
                new InlineRun("Een ", InlineStyle.None),
                new InlineRun("vette", InlineStyle.Bold),
                new InlineRun(" en ", InlineStyle.None),
                new InlineRun("schuine", InlineStyle.Italic),
                new InlineRun(" zin met ", InlineStyle.None),
                new InlineRun("code", InlineStyle.Code),
                new InlineRun(".", InlineStyle.None),
            ],
            runs);
    }

    [Fact]
    public void TurnsLinksAndPageLinksIntoLinkedRuns()
    {
        var runs = InlineParser.Parse("Zie [de site](https://example.com), [[Ideeën]] of [[Welkom|deze pagina]].");
        Assert.Contains(new InlineRun("de site", InlineStyle.None, "https://example.com"), runs);
        Assert.Contains(new InlineRun("Ideeën", InlineStyle.None, "blad-page:Idee%C3%ABn"), runs);
        Assert.Contains(new InlineRun("deze pagina", InlineStyle.None, "blad-page:Welkom"), runs);
        Assert.Equal("Ideeën", WikiLinks.PageName("blad-page:Idee%C3%ABn"));
    }

    [Fact]
    public void LeavesSnakeCaseAlone()
    {
        Assert.Equal([new InlineRun("een snake_case_naam", InlineStyle.None)], InlineParser.Parse("een snake_case_naam"));
    }
}

public class EditorStylerTests
{
    [Fact]
    public void HeadingMarkersHangAndGoQuiet()
    {
        var styling = EditorStyler.Style("## Titel\nTekst");
        Assert.Equal(new LineStyle(0, 8, LineKind.Heading, 2, 3), styling.Lines[0]);
        Assert.Equal(new LineStyle(9, 5, LineKind.Body), styling.Lines[1]);
        Assert.Contains(new StyleSpan(0, 3, SpanKind.Syntax), styling.Spans);
    }

    [Fact]
    public void WorksWithTheWindowsTextBoxLineBreaks()
    {
        var styling = EditorStyler.Style("- [x] klaar\r**vet**");
        Assert.Equal(LineKind.ListItem, styling.Lines[0].Kind);
        Assert.Equal(6, styling.Lines[0].MarkerLength);
        Assert.Contains(new StyleSpan(6, 5, SpanKind.DoneTask), styling.Spans);
        Assert.Contains(new StyleSpan(12, 7, SpanKind.Bold), styling.Spans);
        Assert.Contains(new StyleSpan(12, 2, SpanKind.Syntax), styling.Spans);
    }

    [Fact]
    public void CodeBlocksAreNotStyledAsMarkdown()
    {
        var styling = EditorStyler.Style("```\n# geen kop\n```\n# kop");
        Assert.Equal([LineKind.CodeFence, LineKind.Code, LineKind.CodeFence, LineKind.Heading], styling.Lines.Select(l => l.Kind));
    }

    [Fact]
    public void ImageLinesCarryTheirSource()
    {
        var line = Assert.Single(EditorStyler.Style("![](assets/foto.png)").Lines);
        Assert.Equal(LineKind.Image, line.Kind);
        Assert.Equal("assets/foto.png", line.Source);
    }
}

public class WikiLinkTests
{
    [Fact]
    public void FindsPagesThatLinkHereIgnoringCaseAndAccents()
    {
        var entries = new[]
        {
            new SearchEntry("/n/Welkom.md", "Welkom", "n", "# Welkom", DateTime.UtcNow),
            new SearchEntry("/n/Plan.md", "Plan", "n", "Intro\nZie [[ideeen]] voor meer.", DateTime.UtcNow),
            new SearchEntry("/n/Los.md", "Los", "n", "Niets hier.", DateTime.UtcNow),
        };
        var backlink = Assert.Single(WikiLinks.Backlinks("Ideeën", "/n/Ideeën.md", entries));
        Assert.Equal("Plan", backlink.Title);
        Assert.Equal("Zie [[ideeen]] voor meer.", backlink.Snippet);
    }
}

public class HtmlExporterTests
{
    [Fact]
    public void ExportsReadableHtml()
    {
        var html = HtmlExporter.Export("# Titel\n\nZie **dit** en [[Andere pagina]].", "Titel", "/n/Titel.md", ExportStyle.Paper);
        Assert.Contains("<h1>Titel</h1>", html);
        Assert.Contains("<strong>dit</strong>", html);
        Assert.Contains("<a href=\"Andere%20pagina.md\">Andere pagina</a>", html);
        Assert.Contains("background: #F4EFE5", html);
    }
}

public class OutlineTests
{
    [Fact]
    public void ListsHeadingsWithTheirPlaceInTheText()
    {
        const string page = "# Titel\n\nTekst.\n\n## Deel een\n\n### Detail\n";
        var headings = Outline.Headings(page);

        Assert.Equal(3, headings.Count);
        Assert.Equal(["Titel", "Deel een", "Detail"], headings.Select(heading => heading.Title));
        Assert.Equal([1, 2, 3], headings.Select(heading => heading.Level));
        Assert.Equal([0, 1, 2], headings.Select(heading => heading.Index));
        Assert.Equal(page.IndexOf("## Deel een", StringComparison.Ordinal), headings[1].Offset);
    }

    [Fact]
    public void SkipsHashesInsideCodeAndTrailingHashes()
    {
        var headings = Outline.Headings("```sh\n# geen kopje\n```\n\n# Wel een kopje #\n\n#geenruimte\n");

        var heading = Assert.Single(headings);
        Assert.Equal("Wel een kopje", heading.Title);
    }
}

public class TagTests
{
    [Fact]
    public void FindsTagsButNotHeadings()
    {
        Assert.Equal(["examen", "geschiedenis/1789"], Tags.Names("# Kopje\n\nLezen voor #examen, zie #geschiedenis/1789."));
        Assert.Empty(Tags.Names("## Nog een kopje"));
        Assert.Empty(Tags.Names("Kleur #123456 is geen tag."));
    }

    [Fact]
    public void ReadingModeMakesTagsClickable()
    {
        var runs = InlineParser.Parse("Lezen voor #examen.");

        var tag = Assert.Single(runs, run => run.Link is not null);
        Assert.Equal("#examen", tag.Text);
        Assert.Equal("examen", Tags.TagName(tag.Link!));
    }
}

public class CodeHighlighterTests
{
    private static string[] Pieces(string code, string language, CodeToken token) =>
        CodeHighlighter.Tokens(code, language)
            .Where(span => span.Token == token)
            .Select(span => code.Substring(span.Start, span.Length))
            .ToArray();

    [Fact]
    public void ColoursKeywordsStringsNumbersAndComments()
    {
        const string code = "let naam = \"Blad\" // een notitie\nlet jaar = 1789";

        Assert.Equal(["let", "let"], Pieces(code, "swift", CodeToken.Keyword));
        Assert.Equal(["\"Blad\""], Pieces(code, "swift", CodeToken.String));
        Assert.Equal(["1789"], Pieces(code, "swift", CodeToken.Number));
        Assert.Equal(["// een notitie"], Pieces(code, "swift", CodeToken.Comment));
    }

    [Fact]
    public void FollowsTheLanguage()
    {
        const string code = "# alles hierna is uitleg\ndef jaar(x): return 1789";

        Assert.Equal(["# alles hierna is uitleg"], Pieces(code, "python", CodeToken.Comment));
        Assert.Equal(["def", "return"], Pieces(code, "python", CodeToken.Keyword));
        // In Swift a # doesn't start a comment, so that line stays plain text.
        Assert.Empty(Pieces(code, "swift", CodeToken.Comment));
    }

    [Theory]
    [InlineData("swift", "@main struct App { #available(macOS 27, *) }")]
    [InlineData("swift", "# in Swift is dit geen commentaar\nlet jaar = 1789")]
    [InlineData("", "### @@@ ###")]
    [InlineData("python", "s = 'niet afgesloten\nx = 1")]
    public void AlwaysReachesTheEndOfTheCode(string language, string code)
    {
        // A stray # or @ once left the highlighter walking in place.
        var spans = CodeHighlighter.Tokens(code, language);

        Assert.All(spans, span => Assert.InRange(span.Start + span.Length, 0, code.Length));
    }

    [Fact]
    public void KeepsTextWithoutColourOutsideTheSpans()
    {
        const string code = "geen code, gewoon tekst";

        Assert.Empty(CodeHighlighter.Tokens(code, ""));
    }
}

public class BundleExportTests
{
    [Fact]
    public void PutsEveryPageInOneDocumentWithContents()
    {
        var html = HtmlExporter.ExportBundle(
            [
                new HtmlExporter.Section("Franse Revolutie", "# De Franse Revolutie\n\nTekst.", "/vak/Franse Revolutie.md"),
                new HtmlExporter.Section("Tijdlijn", "# Tijdlijn\n\n1. 1789", "/vak/Tijdlijn.md"),
            ],
            "Geschiedenis",
            ExportStyle.Paper);

        Assert.Contains("<h1>Geschiedenis</h1>", html);
        Assert.Contains("<h2>Inhoud</h2>", html);
        Assert.Contains("<li>Franse Revolutie</li>", html);
        Assert.Contains("<li>Tijdlijn</li>", html);
        Assert.Contains("2 pagina's", html);
        // Each page starts on its own sheet when printed.
        Assert.Equal(3, html.Split("class=\"page").Length - 1);
    }
}
