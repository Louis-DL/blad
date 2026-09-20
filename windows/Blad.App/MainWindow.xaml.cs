using Blad.Core.Pages;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Blad;

/// <summary>The Blad window: spaces in the sidebar, open pages as tabs, and the page on paper.</summary>
public sealed partial class MainWindow : Window
{
    private readonly Library library = Library.Shared;
    private readonly AppSettings settings = AppSettings.Current;
    private PageDocument? active;
    private Theme theme = Theme.Current;
    private bool isSelectingTab;
    private bool isShowingDialog;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(DragRegion);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1280, 860));
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Blad.ico"));
        Root.Loaded += (_, _) =>
        {
            // Room for the minimise, maximise and close buttons, which Windows draws over the content.
            var scale = Root.XamlRoot.RasterizationScale;
            CaptionColumn.Width = new GridLength(AppWindow.TitleBar.RightInset / scale);
        };

        Tabs.SelectionChanged += (_, _) =>
        {
            if (!isSelectingTab && Tabs.SelectedItem is TabViewItem { Tag: string path }) Show(path);
        };
        Tabs.TabCloseRequested += (_, args) => ClosePage((string)args.Tab.Tag);
        Tabs.AddTabButtonClick += (_, _) => NewPage(null);

        Editor.Edited += OnEdited;
        Editor.LinkRequested += ShowLinkPicker;
        Editor.LinkOpened += OpenLink;
        Editor.ErrorOccurred += ShowError;
        Reading.TaskToggled += ToggleTask;
        Reading.LinkOpened += OpenLink;
        Reading.PageOpened += Show;

        library.ErrorOccurred += ShowError;
        library.TreesChanged += RebuildTree;
        library.PageMoved += OnPageMoved;
        settings.Changed += ApplySettings;
        Activated += OnActivated;
        Closed += OnClosed;

        WireSidebar();
        WireCommands();
        WireFind();
        WireOutline();
        _ = LoadPaperAsync();
        ApplySettings();
        RestoreSession();
        _ = library.RefreshAsync();
    }

    // MARK: Pages

    public void Show(string path)
    {
        if (active is not null && Library.SamePath(active.Path, path))
        {
            SelectTab(active.Path);
            return;
        }
        if (library.Document(path) is not { } document) return;

        if (active is not null) library.FinishEditing(active);
        if (!settings.ShowTabs)
        {
            // Without tabs, a page replaces the one that was open.
            Tabs.TabItems.Clear();
        }
        if (FindTab(document.Path) is null) AddTab(document);

        active = document;
        SelectTab(document.Path);
        ShowActive();
        Remember(document.Path);
    }

    public void ClosePage(string path)
    {
        if (FindTab(path) is not { } tab) return;
        var index = Tabs.TabItems.IndexOf(tab);
        var wasActive = active is not null && Library.SamePath(active.Path, path);
        if (wasActive) library.FinishEditing(active!);
        library.SaveAll();
        Tabs.TabItems.Remove(tab);

        if (wasActive)
        {
            active = null;
            if (Tabs.TabItems.Count > 0)
            {
                var next = (TabViewItem)Tabs.TabItems[Math.Min(index, Tabs.TabItems.Count - 1)];
                Show((string)next.Tag);
            }
            else
            {
                ShowActive();
            }
        }
        Persist();
    }

    private void ShowActive()
    {
        var hasPage = active is not null;
        Welcome.Visibility = hasPage ? Visibility.Collapsed : Visibility.Visible;
        PageActions.Visibility = hasPage && !isFocusMode ? Visibility.Visible : Visibility.Collapsed;
        StatusPill.Visibility = hasPage && settings.ShowWordCount ? Visibility.Visible : Visibility.Collapsed;

        if (active is null)
        {
            Editor.Visibility = Visibility.Collapsed;
            Reading.Visibility = Visibility.Collapsed;
            Title = "Blad";
            PageTitle.Text = "";
            BuildWelcome();
            return;
        }

        Editor.Load(active, theme);
        Title = $"{active.Title} – Blad";
        PageTitle.Text = active.Title;
        UpdateWordCount();
        UpdateMode();
        SelectInTree(active.Path);
    }

    private void OnEdited(string text)
    {
        if (active is null || !active.Edit(text)) return;
        library.ScheduleSave(active);
        UpdateWordCount();
    }

    private void ToggleTask(int line)
    {
        if (active is null) return;
        active.ToggleTask(line);
        library.ScheduleSave(active);
        UpdateMode();
    }

    private async void UpdateMode()
    {
        if (active is not { } page) return;
        Editor.Visibility = page.IsReading ? Visibility.Collapsed : Visibility.Visible;
        Reading.Visibility = page.IsReading ? Visibility.Visible : Visibility.Collapsed;
        ModeIcon.Glyph = page.IsReading ? "\uE70F" : "\uE736";
        ModeLabel.Text = page.IsReading ? "Bewerk" : "Lezen";

        if (!page.IsReading)
        {
            Editor.Load(page, theme);
            Editor.Focus();
            return;
        }
        Reading.Show(page, theme, []);
        var backlinks = await library.BacklinksAsync(page);
        if (active == page && page.IsReading) Reading.Show(page, theme, backlinks);
    }

    private void ToggleReading()
    {
        if (active is null) return;
        active.IsReading = !active.IsReading;
        UpdateMode();
    }

    private void UpdateWordCount()
    {
        if (active is null) return;
        WordCount.Text = active.WordCount == 1 ? "1 woord" : $"{active.WordCount:N0} woorden";
    }

    // MARK: Tabs

    private TabViewItem AddTab(PageDocument document)
    {
        var tab = new TabViewItem
        {
            Header = document.Title,
            Tag = document.Path,
            IconSource = new FontIconSource { Glyph = "\uE8A5" },
        };
        var index = Tabs.SelectedIndex >= 0 ? Tabs.SelectedIndex + 1 : Tabs.TabItems.Count;
        Tabs.TabItems.Insert(Math.Min(index, Tabs.TabItems.Count), tab);
        return tab;
    }

    private TabViewItem? FindTab(string path) =>
        Tabs.TabItems.OfType<TabViewItem>().FirstOrDefault(tab => Library.SamePath((string)tab.Tag, path));

    private void SelectTab(string path)
    {
        isSelectingTab = true;
        Tabs.SelectedItem = FindTab(path);
        isSelectingTab = false;
    }

    private void OnPageMoved(string from, string to)
    {
        foreach (var tab in Tabs.TabItems.OfType<TabViewItem>())
        {
            var path = (string)tab.Tag;
            if (!Library.IsInside(path, from)) continue;
            var moved = to + path[from.Length..];
            tab.Tag = moved;
            tab.Header = Path.GetFileNameWithoutExtension(moved);
        }
        if (active is not null)
        {
            Title = $"{active.Title} – Blad";
            PageTitle.Text = active.Title;
        }
        Persist();
    }

    // MARK: Look

    private void ApplySettings()
    {
        theme = Theme.Current;
        Root.RequestedTheme = theme.ElementTheme;
        PaperColor.Fill = Theme.Brush(theme.Background);
        PaperGrain.Visibility = theme.HasGrain && settings.PaperGrain ? Visibility.Visible : Visibility.Collapsed;
        StatusPill.Background = Theme.Brush(Theme.WithAlpha(theme.Text, 0.06));
        WordCount.Foreground = Theme.Brush(theme.Secondary);
        Tabs.Visibility = settings.ShowTabs && !isFocusMode ? Visibility.Visible : Visibility.Collapsed;
        PageTitle.Visibility = settings.ShowTabs ? Visibility.Collapsed : Visibility.Visible;

        var titleBar = AppWindow.TitleBar;
        titleBar.ButtonBackgroundColor = Colors.Transparent;
        titleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        titleBar.ButtonForegroundColor = theme.IsDark ? Colors.White : Colors.Black;

        if (active is null)
        {
            BuildWelcome();
            return;
        }
        StatusPill.Visibility = settings.ShowWordCount ? Visibility.Visible : Visibility.Collapsed;
        Editor.ApplyTheme(theme);
        if (active.IsReading) UpdateMode();
    }

    private async Task LoadPaperAsync() => PaperGrain.Source = await PaperTexture.CreateAsync();

    private void BuildWelcome()
    {
        WelcomeContent.Children.Clear();
        WelcomeContent.Children.Add(new TextBlock
        {
            Text = "Blad",
            FontFamily = new FontFamily("Sitka Heading, Georgia"),
            FontSize = 60,
            FontWeight = FontWeights.SemiBold,
            Foreground = Theme.Brush(theme.Text),
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        WelcomeContent.Children.Add(new TextBlock
        {
            Text = "Een rustige plek voor notities en README's.",
            FontFamily = new FontFamily("Sitka Text, Georgia"),
            FontSize = 17,
            Foreground = Theme.Brush(theme.Secondary),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, -18, 0, 0),
        });

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Center };
        if (library.Spaces.Count > 0)
        {
            actions.Children.Add(ActionButton("Nieuwe pagina", "\uE8A5", () => NewPage(null), accent: true));
        }
        actions.Children.Add(ActionButton("Nieuwe ruimte", "\uE8F1", () => _ = NewSpaceAsync(), accent: library.Spaces.Count == 0));
        actions.Children.Add(ActionButton("Open een bestaande map", "\uE8DA", () => _ = OpenFolderAsync(), accent: false));
        WelcomeContent.Children.Add(actions);

        var recent = settings.RecentPages.Where(File.Exists).Take(5).ToList();
        if (recent.Count == 0) return;
        var list = new StackPanel { Spacing = 2 };
        list.Children.Add(new TextBlock
        {
            Text = "RECENT",
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            CharacterSpacing = 80,
            Foreground = Theme.Brush(theme.Secondary),
            Margin = new Thickness(12, 0, 0, 6),
        });
        foreach (var path in recent)
        {
            var row = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Background = Theme.Brush(Colors.Transparent),
                BorderThickness = new Thickness(0),
                Content = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = 10,
                    Children =
                    {
                        new FontIcon { Glyph = "\uE8A5", FontSize = 14, Foreground = Theme.Brush(theme.Secondary) },
                        new TextBlock { Text = Path.GetFileNameWithoutExtension(path), Foreground = Theme.Brush(theme.Text) },
                        new TextBlock { Text = Path.GetFileName(Path.GetDirectoryName(path)), Foreground = Theme.Brush(theme.Secondary) },
                    },
                },
            };
            row.Click += (_, _) => Show(path);
            list.Children.Add(row);
        }
        WelcomeContent.Children.Add(list);
    }

    private static Button ActionButton(string label, string glyph, Action action, bool accent)
    {
        var button = new Button
        {
            Padding = new Thickness(16, 10, 16, 10),
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 10,
                Children = { new FontIcon { Glyph = glyph, FontSize = 16 }, new TextBlock { Text = label } },
            },
        };
        if (accent) button.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        button.Click += (_, _) => action();
        return button;
    }

    // MARK: Session

    private void RestoreSession()
    {
        foreach (var path in settings.OpenPages.Where(File.Exists))
        {
            if (library.Document(path) is { } document) AddTab(document);
        }
        var start = settings.ActivePage is { } saved && File.Exists(saved) ? saved : settings.OpenPages.FirstOrDefault(File.Exists);
        if (start is not null) Show(start);
        else ShowActive();
    }

    private void Remember(string path)
    {
        settings.RecentPages.RemoveAll(item => Library.SamePath(item, path));
        settings.RecentPages.Insert(0, path);
        if (settings.RecentPages.Count > 8) settings.RecentPages.RemoveRange(8, settings.RecentPages.Count - 8);
        Persist();
    }

    private void Persist()
    {
        settings.OpenPages = Tabs.TabItems.OfType<TabViewItem>().Select(tab => (string)tab.Tag).ToList();
        settings.ActivePage = active?.Path;
        settings.Save(notify: false);
    }

    private async void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            library.SaveAll();
            return;
        }
        // Pick up changes made in other apps, like git or another editor.
        if (active is not null && !active.IsDirty && active.ReloadFromDisk())
        {
            if (active.IsReading) UpdateMode();
            else Editor.Load(active, theme);
            UpdateWordCount();
        }
        await library.RefreshAsync();
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        if (active is not null) library.FinishEditing(active);
        library.SaveAll();
        Persist();
    }

    private void ShowError(string message)
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            // Only one dialog can be open at a time.
            if (isShowingDialog || Root.XamlRoot is null) return;
            isShowingDialog = true;
            try
            {
                await Dialogs.ShowErrorAsync(Root.XamlRoot, message);
            }
            finally
            {
                isShowingDialog = false;
            }
        });
    }
}
