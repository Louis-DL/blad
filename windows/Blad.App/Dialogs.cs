using Blad.Core.Search;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Blad;

/// <summary>Ctrl+K: find a page by name or contents. Recent pages show before anything is typed.</summary>
public sealed class SearchPanel : UserControl
{
    private readonly TextBox query = new() { PlaceholderText = "Zoek of open een pagina", FontSize = 18 };
    private readonly ListView results = new() { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 380 };
    private List<SearchEntry> entries = [];

    /// <summary>A result was chosen; the argument is the page's path.</summary>
    public event Action<string>? Chosen;

    public SearchPanel()
    {
        query.TextChanged += (_, _) => Update();
        query.KeyDown += OnKeyDown;
        results.IsItemClickEnabled = true;
        results.ItemClick += (_, e) => { if (e.ClickedItem is ListViewItem { Tag: string path }) Chosen?.Invoke(path); };
        Content = new StackPanel { Spacing = 10, Width = 500, Children = { query, results } };
        Loaded += async (_, _) =>
        {
            query.Focus(FocusState.Programmatic);
            entries = await Library.Shared.BuildSearchIndexAsync();
            Update();
        };
    }

    private void Update()
    {
        results.Items.Clear();
        foreach (var result in SearchIndex.Search(query.Text, entries))
        {
            results.Items.Add(new ListViewItem
            {
                Tag = result.Entry.Path,
                Padding = new Thickness(12, 8, 12, 8),
                Content = new StackPanel
                {
                    Spacing = 2,
                    Children =
                    {
                        new TextBlock { Text = result.Entry.Title, FontWeight = FontWeights.SemiBold, FontSize = 14 },
                        new TextBlock
                        {
                            Text = result.Snippet ?? result.Entry.Location,
                            FontSize = 12,
                            Opacity = 0.65,
                            TextTrimming = TextTrimming.CharacterEllipsis,
                        },
                    },
                },
            });
        }
        if (results.Items.Count > 0) results.SelectedIndex = 0;
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.Down:
                results.SelectedIndex = Math.Min(results.SelectedIndex + 1, results.Items.Count - 1);
                results.ScrollIntoView(results.SelectedItem);
                e.Handled = true;
                break;
            case VirtualKey.Up:
                results.SelectedIndex = Math.Max(results.SelectedIndex - 1, 0);
                results.ScrollIntoView(results.SelectedItem);
                e.Handled = true;
                break;
            case VirtualKey.Enter when results.SelectedItem is ListViewItem { Tag: string path }:
                Chosen?.Invoke(path);
                e.Handled = true;
                break;
        }
    }
}

/// <summary>
/// Opens after typing [[: the field at the top is the title of a new page; existing pages are listed below.
/// </summary>
public sealed class LinkPickerPanel : UserControl
{
    private readonly TextBox title = new() { PlaceholderText = "Titel van een nieuwe pagina", FontSize = 15 };
    private readonly ListView pages = new() { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 240 };
    private readonly IReadOnlyList<PageInfo> all;

    /// <summary>A page title was chosen or typed.</summary>
    public event Action<string>? Picked;

    public LinkPickerPanel(IReadOnlyList<PageInfo> allPages)
    {
        all = allPages;
        title.TextChanged += (_, _) => Update();
        title.KeyDown += OnKeyDown;
        pages.IsItemClickEnabled = true;
        pages.ItemClick += (_, e) => { if (e.ClickedItem is ListViewItem { Tag: string name }) Picked?.Invoke(name); };

        var brackets = new TextBlock
        {
            Text = "[[",
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily(EditorFonts.CodeFamily),
            FontWeight = FontWeights.SemiBold,
            Foreground = Theme.Brush(Theme.Current.Accent),
            VerticalAlignment = VerticalAlignment.Center,
        };
        var field = new Grid { ColumnSpacing = 10 };
        field.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        field.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(title, 1);
        field.Children.Add(brackets);
        field.Children.Add(title);

        var hint = new TextBlock
        {
            Text = "↑↓ kies  ·  Enter voegt de link in  ·  Esc sluit",
            FontSize = 11,
            Opacity = 0.6,
        };
        Content = new StackPanel { Spacing = 8, Width = 340, Children = { field, pages, hint } };
        Loaded += (_, _) => title.Focus(FocusState.Programmatic);
        Update();
    }

    private string Typed => new string(title.Text.Where(c => c is not ('[' or ']' or '|')).ToArray()).Trim();

    private void Update()
    {
        pages.Items.Clear();
        var typed = Typed;
        var matches = typed.Length == 0
            ? all.Take(6)
            : all.Where(page => page.Title.StartsWith(typed, StringComparison.CurrentCultureIgnoreCase))
                .Concat(all.Where(page => !page.Title.StartsWith(typed, StringComparison.CurrentCultureIgnoreCase)
                    && page.Title.Contains(typed, StringComparison.CurrentCultureIgnoreCase)))
                .Take(6);
        foreach (var page in matches)
        {
            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var location = new TextBlock { Text = page.Location, FontSize = 11.5, Opacity = 0.6 };
            Grid.SetColumn(location, 1);
            row.Children.Add(new TextBlock { Text = page.Title, FontSize = 13.5, TextTrimming = TextTrimming.CharacterEllipsis });
            row.Children.Add(location);
            pages.Items.Add(new ListViewItem { Tag = page.Title, Content = row, Padding = new Thickness(10, 6, 10, 6) });
        }
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case VirtualKey.Down:
                pages.SelectedIndex = Math.Min(pages.SelectedIndex + 1, pages.Items.Count - 1);
                e.Handled = true;
                break;
            case VirtualKey.Up:
                // Above the first page is the title field itself.
                pages.SelectedIndex = pages.SelectedIndex <= 0 ? -1 : pages.SelectedIndex - 1;
                e.Handled = true;
                break;
            case VirtualKey.Enter or VirtualKey.Tab:
                if (pages.SelectedItem is ListViewItem { Tag: string name }) Picked?.Invoke(name);
                else if (Typed.Length > 0) Picked?.Invoke(Typed);
                e.Handled = true;
                break;
        }
    }
}

/// <summary>Small dialogs in Blad's words.</summary>
public static class Dialogs
{
    public static async Task<string?> AskNameAsync(XamlRoot root, string title, string placeholder, string? message = null, string initial = "", string confirm = "OK")
    {
        var field = new TextBox { PlaceholderText = placeholder, Text = initial };
        field.SelectAll();
        var content = new StackPanel { Spacing = 12 };
        if (message is not null) content.Children.Add(new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, Opacity = 0.75 });
        content.Children.Add(field);

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = content,
            PrimaryButtonText = confirm,
            CloseButtonText = "Annuleer",
            DefaultButton = ContentDialogButton.Primary,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary && field.Text.Trim().Length > 0 ? field.Text.Trim() : null;
    }

    public static async Task<bool> ConfirmAsync(XamlRoot root, string title, string message, string confirm)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = message,
            PrimaryButtonText = confirm,
            CloseButtonText = "Annuleer",
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    public static async Task ShowErrorAsync(XamlRoot root, string message)
    {
        var dialog = new ContentDialog { XamlRoot = root, Title = "Er ging iets mis", Content = message, CloseButtonText = "OK" };
        await dialog.ShowAsync();
    }
}
