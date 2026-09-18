using System.Globalization;
using System.Net;
using System.Text;
using Blad.Core.Images;
using Blad.Core.Markdown;

namespace Blad.Core.Export;

/// <summary>Colours and type for an export, as CSS values.</summary>
public sealed record ExportStyle(
    string Background,
    string Text,
    string Secondary,
    string Accent,
    string CodeBackground,
    bool IsDark,
    string FontFamily,
    double FontSize)
{
    /// <summary>Blad's paper theme; the PDF always uses it.</summary>
    public static ExportStyle Paper { get; } = new(
        "#F4EFE5", "#2F2A23", "#A69D8E", "#B4532A", "rgba(107, 90, 62, 0.075)", false,
        "Georgia, Cambria, 'Times New Roman', serif", 17);
}

/// <summary>Turns a page into one standalone HTML file that looks like reading mode.</summary>
public static class HtmlExporter
{
    public static string Export(string markdown, string title, string pagePath, ExportStyle style)
    {
        var body = string.Join("\n", MarkdownParser.Parse(markdown).Select(block => Block(block, pagePath)));
        return $"""
            <!doctype html>
            <html lang="nl">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="generator" content="Blad">
            <title>{Escape(title)}</title>
            <style>
            {Stylesheet(style)}
            </style>
            </head>
            <body>
            <main>
            {body}
            </main>
            </body>
            </html>

            """;
    }

    /// <summary>Bold, italic, code, strikethrough and links inside a block, as HTML.</summary>
    public static string Inline(string markdown)
    {
        var html = new StringBuilder();
        foreach (var run in InlineParser.Parse(markdown))
        {
            var text = Escape(run.Text).Replace("\n", "<br>");
            if (run.Style.HasFlag(InlineStyle.Code)) text = $"<code>{text}</code>";
            if (run.Style.HasFlag(InlineStyle.Bold)) text = $"<strong>{text}</strong>";
            if (run.Style.HasFlag(InlineStyle.Italic)) text = $"<em>{text}</em>";
            if (run.Style.HasFlag(InlineStyle.Strike)) text = $"<del>{text}</del>";
            if (run.Link is { } link)
            {
                // A [[page]] becomes a link to the page's file, which works next to the exported page.
                var href = WikiLinks.PageName(link) is { } page ? Uri.EscapeDataString(page) + ".md" : link;
                text = $"<a href=\"{Escape(href)}\">{text}</a>";
            }
            html.Append(text);
        }
        return html.ToString();
    }

    private static string Block(MarkdownBlock block, string pagePath) => block switch
    {
        MarkdownBlock.Heading heading => $"<h{heading.Level}>{Inline(heading.Text)}</h{heading.Level}>",
        MarkdownBlock.Paragraph paragraph => $"<p>{Inline(paragraph.Text)}</p>",
        MarkdownBlock.ListBlock list => "<div class=\"list\">\n" + string.Join("\n", list.Items.Select(ListItem)) + "\n</div>",
        MarkdownBlock.Quote quote => $"<blockquote>{Inline(quote.Text)}</blockquote>",
        MarkdownBlock.CodeBlock code => "<pre>"
            + (code.Language.Length > 0 ? $"<span class=\"language\">{Escape(code.Language.ToLowerInvariant())}</span>" : "")
            + $"<code>{Escape(code.Code)}</code></pre>",
        MarkdownBlock.Table table => Table(table),
        MarkdownBlock.Image image => $"<p><img src=\"{ImageSource(image.Source, pagePath)}\" alt=\"{Escape(image.Alt)}\"></p>",
        MarkdownBlock.Rule => "<hr>",
        _ => "",
    };

    private static string ListItem(ListItem item)
    {
        var (marker, classes) = item.Kind switch
        {
            ListKind.Task => (item.Done ? "☑" : "☐", item.Done ? "item done" : "item"),
            ListKind.Number => (Escape(item.Marker), "item"),
            _ => ("•", "item"),
        };
        return $"<div class=\"{classes}\" style=\"--depth: {item.Depth}\"><span class=\"marker\">{marker}</span><span class=\"text\">{Inline(item.Text)}</span></div>";
    }

    private static string Table(MarkdownBlock.Table table)
    {
        var head = string.Concat(table.Header.Select(cell => $"<th>{Inline(cell)}</th>"));
        var rows = string.Join("\n", table.Rows.Select(row => "<tr>" + string.Concat(row.Select(cell => $"<td>{Inline(cell)}</td>")) + "</tr>"));
        return $"<table>\n<thead><tr>{head}</tr></thead>\n<tbody>\n{rows}\n</tbody>\n</table>";
    }

    /// <summary>Local images are embedded, so the exported file still shows them after it's moved.</summary>
    private static string ImageSource(string source, string pagePath)
    {
        if (ImageStore.Resolve(source, pagePath) is { } file && File.Exists(file) && new FileInfo(file).Length < 15_000_000)
        {
            var type = Path.GetExtension(file).ToLowerInvariant() switch
            {
                ".jpg" or ".jpeg" => "image/jpeg",
                ".gif" => "image/gif",
                ".webp" => "image/webp",
                ".svg" => "image/svg+xml",
                _ => "image/png",
            };
            return $"data:{type};base64,{Convert.ToBase64String(File.ReadAllBytes(file))}";
        }
        return Escape(source);
    }

    private static string Stylesheet(ExportStyle s) => $$"""
        :root { color-scheme: {{(s.IsDark ? "dark" : "light")}}; }
        * { box-sizing: border-box; }
        body { margin: 0; background: {{s.Background}}; color: {{s.Text}}; font-family: {{s.FontFamily}}; font-size: {{s.FontSize.ToString(CultureInfo.InvariantCulture)}}px; line-height: 1.65; }
        main { max-width: 720px; margin: 0 auto; padding: 72px 32px 96px; }
        main > * { margin: 0; }
        main > * + * { margin-top: 0.95em; }
        h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; }
        h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; } h4 { font-size: 1.08em; } h5, h6 { font-size: 1em; }
        main > * + h1, main > * + h2 { margin-top: 1.7em; }
        main > * + h3, main > * + h4 { margin-top: 1.3em; }
        a { color: {{s.Accent}}; text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        code, pre { font-family: "Cascadia Mono", Consolas, ui-monospace, monospace; }
        code { font-size: 0.88em; background: {{s.CodeBackground}}; padding: 0.1em 0.35em; border-radius: 4px; }
        pre { position: relative; background: {{s.CodeBackground}}; padding: 16px 18px; border-radius: 12px; overflow-x: auto; font-size: 0.84em; line-height: 1.5; }
        pre code { background: none; padding: 0; font-size: 1em; }
        pre .language { position: absolute; top: 8px; right: 12px; font: 500 10.5px "Segoe UI Variable", system-ui, sans-serif; color: {{s.Secondary}}; }
        blockquote { padding-left: 14px; border-left: 3px solid {{s.Accent}}; font-style: italic; opacity: 0.8; }
        hr { border: 0; height: 1px; background: {{s.Secondary}}; opacity: 0.35; }
        main > hr { margin: 1.6em 0; }
        .list .item { display: flex; gap: 10px; padding-left: calc(var(--depth) * 1.4em); }
        .list .item + .item { margin-top: 0.4em; }
        .marker { color: {{s.Accent}}; min-width: 0.9em; text-align: right; font-variant-numeric: tabular-nums; }
        .done .text { color: {{s.Secondary}}; text-decoration: line-through; }
        table { width: 100%; border-collapse: separate; border-spacing: 0; border: 1px solid {{s.Secondary}}; border-radius: 10px; overflow: hidden; font-size: 0.92em; }
        th, td { text-align: left; vertical-align: top; padding: 8px 12px; }
        th { font-weight: 600; background: {{s.CodeBackground}}; }
        tbody tr:nth-child(even) td { background: {{s.CodeBackground}}; }
        img { max-width: 100%; border-radius: 8px; }
        @media print { body { background: white; } main { padding: 0; max-width: none; } pre, table, blockquote, img { break-inside: avoid; } }
        """;

    private static string Escape(string text) => WebUtility.HtmlEncode(text);
}
