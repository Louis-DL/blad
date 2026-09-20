using Blad.Core.Export;
using Blad.Core.Pages;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Blad;

/// <summary>A whole space as one PDF: a cover, a contents list, then every page.</summary>
public sealed partial class MainWindow
{
    private async Task ExportSpaceAsync(string space)
    {
        library.SaveAll();
        var name = Path.GetFileName(space);
        var pages = PagesInOrder(library.Tree(space)).ToList();
        if (pages.Count == 0)
        {
            ShowError($"{name} heeft nog geen pagina's.");
            return;
        }

        var picker = new FileSavePicker { SuggestedFileName = name, SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        picker.FileTypeChoices.Add("PDF", [".pdf"]);
        InitializeWithWindow.Initialize(picker, WindowHandle);
        if (await picker.PickSaveFileAsync() is not { } file) return;

        var sections = pages.Select(path => new HtmlExporter.Section(
            Path.GetFileNameWithoutExtension(path),
            library.Document(path)?.Text ?? ReadOrEmpty(path),
            path)).ToList();

        var style = ExportStyle.Paper with
        {
            FontFamily = EditorFonts.CssFamily(settings.Font),
            FontSize = settings.FontSize,
        };
        try
        {
            var html = HtmlExporter.ExportBundle(sections, name, style);
            await PdfExporter.ExportAsync(html, file.Path, WindowHandle, numberPages: true);
        }
        catch (Exception exception)
        {
            ShowError($"Kon {name} niet exporteren.\n\n{exception.Message}");
        }
    }

    /// <summary>Every page below these nodes, in the order the sidebar shows them.</summary>
    private static IEnumerable<string> PagesInOrder(IReadOnlyList<PageNode> nodes) =>
        nodes.SelectMany(node => node.IsFolder ? PagesInOrder(node.Children) : [node.Path]);

    private static string ReadOrEmpty(string path)
    {
        try
        {
            return File.ReadAllText(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return "";
        }
    }
}
