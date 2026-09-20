using System.Diagnostics;
using Blad.Core.Export;
using Blad.Core.Images;
using Blad.Core.Pages;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;

namespace Blad;

public sealed partial class MainWindow
{
    private bool isFocusMode;

    private nint WindowHandle => WindowNative.GetWindowHandle(this);

    private void WireCommands()
    {
        SearchButton.Click += (_, _) => _ = ShowSearchAsync();
        NewPageItem.Click += (_, _) => NewPage(null);
        NewSpaceItem.Click += (_, _) => _ = NewSpaceAsync();
        OpenFolderItem.Click += (_, _) => _ = OpenFolderAsync();
        SettingsButton.Click += (_, _) => _ = ShowSettingsAsync();
        ModeButton.Click += (_, _) => ToggleReading();
        FocusButton.Click += (_, _) => SetFocusMode(true);
        LeaveFocusButton.Click += (_, _) => SetFocusMode(false);
        ExportPdfItem.Click += (_, _) => _ = ExportAsync(pdf: true);
        ExportHtmlItem.Click += (_, _) => _ = ExportAsync(pdf: false);
        InsertImageItem.Click += (_, _) => _ = InsertImageAsync();
        ShowInExplorerItem.Click += (_, _) => { if (active is not null) ShowInExplorer(active.Path); };

        Root.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
        const VirtualKeyModifiers control = VirtualKeyModifiers.Control;
        const VirtualKeyModifiers controlShift = VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift;
        Shortcut(VirtualKey.N, control, () => NewPage(null));
        Shortcut(VirtualKey.N, controlShift, () => _ = NewSpaceAsync());
        Shortcut(VirtualKey.O, control, () => _ = OpenFolderAsync());
        Shortcut(VirtualKey.K, control, () => _ = ShowSearchAsync());
        Shortcut(VirtualKey.W, control, () => { if (active is not null) ClosePage(active.Path); });
        Shortcut(VirtualKey.S, control, library.SaveAll);
        Shortcut(VirtualKey.R, control, ToggleReading);
        Shortcut(VirtualKey.F, control, ShowFind);
        Shortcut(VirtualKey.F3, VirtualKeyModifiers.None, () => { if (IsFindOpen) Step(1); });
        Shortcut(VirtualKey.F3, VirtualKeyModifiers.Shift, () => { if (IsFindOpen) Step(-1); });
        Shortcut(VirtualKey.F, controlShift, () => SetFocusMode(!isFocusMode));
        Shortcut(VirtualKey.F11, VirtualKeyModifiers.None, () => SetFocusMode(!isFocusMode));
        Shortcut(VirtualKey.Escape, VirtualKeyModifiers.None, () =>
        {
            if (IsFindOpen) CloseFind();
            else if (isFocusMode) SetFocusMode(false);
        });
        Shortcut(VirtualKey.E, controlShift, () => _ = ExportAsync(pdf: true));
        Shortcut(VirtualKey.Tab, control, () => NextTab(1));
        Shortcut(VirtualKey.Tab, controlShift, () => NextTab(-1));
        Shortcut((VirtualKey)188, control, () => _ = ShowSettingsAsync()); // Ctrl+,
        Shortcut((VirtualKey)187, control, () => AdjustFontSize(1));       // Ctrl+=
        Shortcut(VirtualKey.Add, control, () => AdjustFontSize(1));
        Shortcut((VirtualKey)189, control, () => AdjustFontSize(-1));      // Ctrl+-
        Shortcut(VirtualKey.Subtract, control, () => AdjustFontSize(-1));
    }

    private void Shortcut(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += (_, args) =>
        {
            action();
            args.Handled = true;
        };
        Root.KeyboardAccelerators.Add(accelerator);
    }

    // MARK: New and open

    /// <summary>A new page next to the open page, or in <paramref name="folder"/>, or in the first space.</summary>
    private void NewPage(string? folder)
    {
        if (library.Spaces.Count == 0)
        {
            _ = NewSpaceAsync();
            return;
        }
        folder ??= active is not null && library.SpaceContaining(active.Path) is not null
            ? Path.GetDirectoryName(active.Path)
            : null;
        if (library.NewPage(folder) is { } path) Show(path);
    }

    private async Task NewSpaceAsync()
    {
        var name = await Dialogs.AskNameAsync(Root.XamlRoot, "Nieuwe ruimte", "Bv. Wiskunde of Blad-app",
            "Een ruimte houdt de pagina's van één project of vak bij elkaar. Kies daarna waar ze komt: "
            + "in OneDrive of iCloud Drive heb je ze ook op je andere apparaten.",
            confirm: "Kies een plek");
        if (name is null || await PickFolderAsync() is not { } parent) return;
        if (library.CreateSpace(name, parent) is { } space && library.NewPage(space) is { } page) Show(page);
    }

    private async Task OpenFolderAsync()
    {
        if (await PickFolderAsync() is { } folder) library.AddSpace(folder);
    }

    private async Task<string?> PickFolderAsync()
    {
        var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowHandle);
        return (await picker.PickSingleFolderAsync())?.Path;
    }

    // MARK: Search and links

    private async Task ShowSearchAsync()
    {
        if (isShowingDialog) return;
        var panel = new SearchPanel();
        var dialog = new ContentDialog { XamlRoot = Root.XamlRoot, Content = panel, CloseButtonText = "Sluit" };
        panel.Chosen += path =>
        {
            dialog.Hide();
            Show(path);
        };
        isShowingDialog = true;
        try
        {
            await dialog.ShowAsync();
        }
        finally
        {
            isShowingDialog = false;
        }
    }

    private void ShowLinkPicker(Point point)
    {
        var panel = new LinkPickerPanel(library.Pages());
        var flyout = new Flyout { Content = panel };
        panel.Picked += title =>
        {
            flyout.Hide();
            Editor.CompleteLink(title);
        };
        flyout.ShowAt(Editor, new FlyoutShowOptions { Position = point, Placement = FlyoutPlacementMode.BottomEdgeAlignedLeft });
    }

    /// <summary>[[Page]] links open (or create) a page; other markdown files open in Blad; the rest in their own app.</summary>
    private void OpenLink(string target, bool isPage)
    {
        if (active is null) return;
        if (isPage)
        {
            if (library.OpenPage(target, active.Path) is { } page) Show(page);
            return;
        }
        if (Uri.TryCreate(target, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" or "mailto")
        {
            Launch(target);
            return;
        }
        if (ImageStore.Resolve(target, active.Path) is { } file && File.Exists(file))
        {
            if (PageFiles.IsMarkdown(file)) Show(file);
            else Launch(file);
        }
    }

    private static void Launch(string target) =>
        Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });

    // MARK: Page

    private void SetFocusMode(bool on)
    {
        if (on && active is null) return;
        isFocusMode = on;
        var chrome = on ? Visibility.Collapsed : Visibility.Visible;
        SidebarColumn.Width = on ? new GridLength(0) : new GridLength(264);
        Sidebar.Visibility = chrome;
        AppName.Visibility = chrome;
        Tabs.Visibility = !on && settings.ShowTabs ? Visibility.Visible : Visibility.Collapsed;
        PageActions.Visibility = chrome;
        LeaveFocusButton.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        StatusPill.Opacity = on ? 0.45 : 1;
        PageArea.CornerRadius = new CornerRadius(on ? 0 : 8, 0, 0, 0);
        PageArea.BorderThickness = new Thickness(on ? 0 : 1, on ? 0 : 1, 0, 0);
        // Focus mode fills the screen, like pressing F11.
        AppWindow.SetPresenter(on ? AppWindowPresenterKind.FullScreen : AppWindowPresenterKind.Default);
        if (!on) Editor.Focus();
    }

    private void NextTab(int offset)
    {
        var count = Tabs.TabItems.Count;
        if (count < 2) return;
        var index = (Math.Max(0, Tabs.SelectedIndex) + offset + count) % count;
        Show((string)((TabViewItem)Tabs.TabItems[index]).Tag);
    }

    private void AdjustFontSize(int delta)
    {
        settings.FontSize = Math.Clamp(settings.FontSize + delta, 12, 28);
        settings.Save();
    }

    private async Task ShowSettingsAsync()
    {
        if (isShowingDialog) return;
        isShowingDialog = true;
        try
        {
            await SettingsDialog.ShowAsync(Root.XamlRoot);
        }
        finally
        {
            isShowingDialog = false;
        }
    }

    private async Task InsertImageAsync()
    {
        if (active is null) return;
        if (active.IsReading) ToggleReading();
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary };
        foreach (var type in new[] { ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg" }) picker.FileTypeFilter.Add(type);
        InitializeWithWindow.Initialize(picker, WindowHandle);
        var files = await picker.PickMultipleFilesAsync();
        if (files.Count > 0) Editor.InsertImages(files.Select(file => file.Path));
    }

    /// <summary>HTML keeps the theme you write in; the PDF uses the paper colours on white pages.</summary>
    private async Task ExportAsync(bool pdf)
    {
        if (active is null) return;
        library.SaveAll();

        var picker = new FileSavePicker { SuggestedFileName = active.Title, SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        picker.FileTypeChoices.Add(pdf ? "PDF" : "Webpagina", [pdf ? ".pdf" : ".html"]);
        InitializeWithWindow.Initialize(picker, WindowHandle);
        if (await picker.PickSaveFileAsync() is not { } file) return;

        var style = pdf
            ? ExportStyle.Paper with { FontFamily = EditorFonts.CssFamily(settings.Font), FontSize = settings.FontSize }
            : theme.ToExportStyle(settings.Font, settings.FontSize);
        var html = HtmlExporter.Export(active.Text, active.Title, active.Path, style);
        try
        {
            if (pdf) await PdfExporter.ExportAsync(html, file.Path, WindowHandle);
            else await File.WriteAllTextAsync(file.Path, html);
        }
        catch (Exception exception)
        {
            ShowError($"Kon {active.Title} niet exporteren.\n\n{exception.Message}");
        }
    }
}
