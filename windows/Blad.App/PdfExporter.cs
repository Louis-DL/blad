using Microsoft.Web.WebView2.Core;

namespace Blad;

/// <summary>
/// PDF export: the HTML export laid out on A4 by WebView2, the Edge engine built into Windows,
/// so pages break cleanly and the PDF looks like reading mode.
/// </summary>
public static class PdfExporter
{
    /// <param name="numberPages">True for a bundle: Edge prints the sheet number in the footer.</param>
    public static async Task ExportAsync(string html, string destination, nint windowHandle, bool numberPages = false)
    {
        // A file rather than NavigateToString: pages with embedded images can be larger than its 2 MB limit.
        var page = Path.Combine(Path.GetTempPath(), $"blad-export-{Guid.NewGuid():N}.html");
        await File.WriteAllTextAsync(page, html);

        var environment = await CoreWebView2Environment.CreateAsync();
        var controller = await environment.CreateCoreWebView2ControllerAsync(
            CoreWebView2ControllerWindowReference.CreateFromWindowHandle((ulong)windowHandle));
        controller.IsVisible = false;
        try
        {
            var web = controller.CoreWebView2;
            var loaded = new TaskCompletionSource<bool>();
            web.NavigationCompleted += (_, args) => loaded.TrySetResult(args.IsSuccess);
            web.Navigate(new Uri(page).AbsoluteUri);
            if (!await loaded.Task) throw new IOException("De pagina kon niet opgemaakt worden.");

            var settings = environment.CreatePrintSettings();
            settings.PageWidth = 8.27;
            settings.PageHeight = 11.69;
            settings.MarginTop = settings.MarginBottom = 0.8;
            settings.MarginLeft = settings.MarginRight = 0.85;
            settings.ShouldPrintBackgrounds = true;
            settings.ShouldPrintHeaderAndFooter = numberPages;
            if (numberPages) settings.HeaderTitle = "";
            if (!await web.PrintToPdfAsync(destination, settings))
            {
                throw new IOException("De PDF kon niet gemaakt worden.");
            }
        }
        finally
        {
            controller.Close();
            File.Delete(page);
        }
    }
}
