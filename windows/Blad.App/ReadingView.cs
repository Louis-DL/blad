using Blad.Core.Images;
using Blad.Core.Markdown;
using Blad.Core.Pages;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using Windows.UI.Text;

namespace Blad;

/// <summary>Reading mode: the same page, rendered without the markdown syntax.</summary>
public sealed class ReadingView : UserControl
{
    private static readonly double[] HeadingScale = [1.7, 1.4, 1.2, 1.08, 1.0, 1.0];

    private readonly StackPanel column = new();
    private Theme theme = Theme.Paper;
    private string pagePath = "";

    /// <summary>A task was clicked; the argument is its line in the source.</summary>
    public event Action<int>? TaskToggled;

    /// <summary>A link was clicked: a page name for [[links]], otherwise a URL or relative path.</summary>
    public event Action<string, bool>? LinkOpened;

    /// <summary>A backlink was clicked; the argument is that page's path.</summary>
    public event Action<string>? PageOpened;

    public ReadingView()
    {
        Content = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = column,
        };
    }

    private double Size => AppSettings.Current.FontSize;
    private FontFamily Family => EditorFonts.FontFamily(AppSettings.Current.Font);

    public void Show(PageDocument document, Theme pageTheme, IReadOnlyList<Backlink> backlinks)
    {
        theme = pageTheme;
        pagePath = document.Path;
        column.Children.Clear();
        column.MaxWidth = AppSettings.Current.LineWidth + 80;
        column.Padding = new Thickness(40, 40, 40, 100);
        column.Spacing = Size * 0.95;

        var blocks = MarkdownParser.Parse(document.Text);
        for (var i = 0; i < blocks.Count; i++)
        {
            column.Children.Add(View(blocks[i], isFirst: i == 0));
        }
        if (backlinks.Count > 0)
        {
            column.Children.Add(Backlinks(backlinks));
        }
    }

    private FrameworkElement View(MarkdownBlock block, bool isFirst) => block switch
    {
        MarkdownBlock.Heading heading => Text(heading.Text, Size * HeadingScale[heading.Level - 1], FontWeights.SemiBold,
            margin: new Thickness(0, isFirst ? 0 : Size * (heading.Level <= 2 ? 0.9 : 0.4), 0, 0)),
        MarkdownBlock.Paragraph paragraph => Text(paragraph.Text, Size),
        MarkdownBlock.ListBlock list => List(list),
        MarkdownBlock.Quote quote => Quote(quote),
        MarkdownBlock.CodeBlock code => Code(code),
        MarkdownBlock.Table table => Table(table),
        MarkdownBlock.Image image => Picture(image),
        _ => new Rectangle
        {
            Height = 1,
            Fill = Theme.Brush(Theme.WithAlpha(theme.Secondary, 0.35)),
            Margin = new Thickness(0, Size * 0.5, 0, Size * 0.5),
        },
    };

    private RichTextBlock Text(string markdown, double size, FontWeight? weight = null, Thickness? margin = null, Color? color = null, bool italic = false)
    {
        var paragraph = new Paragraph();
        foreach (var run in InlineParser.Parse(markdown))
        {
            paragraph.Inlines.Add(Inline(run, size));
        }
        return new RichTextBlock
        {
            Blocks = { paragraph },
            FontFamily = Family,
            FontSize = size,
            FontWeight = weight ?? FontWeights.Normal,
            FontStyle = italic ? FontStyle.Italic : FontStyle.Normal,
            Foreground = Theme.Brush(color ?? theme.Text),
            LineHeight = size * 1.6,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true,
            Margin = margin ?? new Thickness(0),
        };
    }

    private Inline Inline(InlineRun run, double size)
    {
        var text = new Run { Text = run.Text };
        if (run.Style.HasFlag(InlineStyle.Bold)) text.FontWeight = FontWeights.SemiBold;
        if (run.Style.HasFlag(InlineStyle.Italic)) text.FontStyle = FontStyle.Italic;
        if (run.Style.HasFlag(InlineStyle.Strike)) text.TextDecorations = TextDecorations.Strikethrough;
        if (run.Style.HasFlag(InlineStyle.Code))
        {
            text.FontFamily = new FontFamily(EditorFonts.CodeFamily);
            text.FontSize = size * 0.88;
        }
        if (run.Link is not { } link) return text;

        var hyperlink = new Hyperlink
        {
            Foreground = Theme.Brush(theme.Accent),
            UnderlineStyle = UnderlineStyle.None,
            Inlines = { text },
        };
        hyperlink.Click += (_, _) =>
        {
            if (WikiLinks.PageName(link) is { } page) LinkOpened?.Invoke(page, true);
            else LinkOpened?.Invoke(link, false);
        };
        return hyperlink;
    }

    private StackPanel List(MarkdownBlock.ListBlock list)
    {
        var panel = new StackPanel { Spacing = Size * 0.4 };
        foreach (var item in list.Items)
        {
            var row = new Grid { Margin = new Thickness(item.Depth * Size * 1.4, 0, 0, 0), ColumnSpacing = 10 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Size * 1.1) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            FrameworkElement marker = item.Kind switch
            {
                ListKind.Task => TaskMarker(item),
                ListKind.Number => new TextBlock
                {
                    Text = item.Marker,
                    FontFamily = Family,
                    FontSize = Size,
                    Foreground = Theme.Brush(theme.Accent),
                    HorizontalAlignment = HorizontalAlignment.Right,
                },
                _ => new TextBlock
                {
                    Text = "•",
                    FontSize = Size,
                    Foreground = Theme.Brush(theme.Accent),
                    HorizontalAlignment = HorizontalAlignment.Center,
                },
            };
            var text = Text(item.Text, Size, color: item.Done ? theme.Secondary : null);
            if (item.Done)
            {
                foreach (var block in text.Blocks.OfType<Paragraph>())
                {
                    foreach (var inline in block.Inlines.OfType<Run>()) inline.TextDecorations = TextDecorations.Strikethrough;
                }
            }
            Grid.SetColumn(text, 1);
            row.Children.Add(marker);
            row.Children.Add(text);
            panel.Children.Add(row);
        }
        return panel;
    }

    private Button TaskMarker(ListItem item)
    {
        var button = new Button
        {
            Content = new FontIcon
            {
                // Segoe Fluent Icons: a filled circle with a tick, or an empty circle.
                Glyph = item.Done ? "\uEC61" : "\uEA3A",
                FontSize = Size,
                Foreground = Theme.Brush(item.Done ? theme.Accent : theme.Secondary),
            },
            Padding = new Thickness(0),
            Background = Theme.Brush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, Size * 0.25, 0, 0),
        };
        ToolTipService.SetToolTip(button, item.Done ? "Markeer als niet gedaan" : "Markeer als gedaan");
        button.Click += (_, _) => TaskToggled?.Invoke(item.Line);
        return button;
    }

    private Grid Quote(MarkdownBlock.Quote quote)
    {
        var grid = new Grid { ColumnSpacing = 14 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new Border { CornerRadius = new CornerRadius(1.5), Background = Theme.Brush(Theme.WithAlpha(theme.Accent, 0.5)) });
        var text = Text(quote.Text, Size, italic: true, color: Theme.WithAlpha(theme.Text, 0.75));
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        return grid;
    }

    private Border Code(MarkdownBlock.CodeBlock code)
    {
        var grid = new Grid();
        grid.Children.Add(new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = new TextBlock
            {
                Text = code.Code,
                FontFamily = new FontFamily(EditorFonts.CodeFamily),
                FontSize = Size * 0.84,
                LineHeight = Size * 1.3,
                Foreground = Theme.Brush(theme.Text),
                IsTextSelectionEnabled = true,
                Padding = new Thickness(18, 16, 18, 16),
            },
        });
        if (code.Language.Length > 0)
        {
            grid.Children.Add(new TextBlock
            {
                Text = code.Language.ToLowerInvariant(),
                FontSize = 11,
                Foreground = Theme.Brush(theme.Secondary),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, 8, 12, 0),
            });
        }
        return new Border { Background = Theme.Brush(theme.CodeBackground), CornerRadius = new CornerRadius(12), Child = grid };
    }

    private Border Table(MarkdownBlock.Table table)
    {
        var columns = Math.Max(table.Header.Count, table.Rows.Select(row => row.Count).DefaultIfEmpty(0).Max());
        var grid = new Grid();
        for (var c = 0; c < columns; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        void AddRow(IReadOnlyList<string> cells, int row, bool header, bool shaded)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            for (var c = 0; c < columns; c++)
            {
                var cell = new Border
                {
                    Background = Theme.Brush(shaded ? theme.CodeBackground : Microsoft.UI.Colors.Transparent),
                    Padding = new Thickness(12, 8, 12, 8),
                    Child = Text(c < cells.Count ? cells[c] : "", Size * 0.92, header ? FontWeights.SemiBold : null),
                };
                Grid.SetRow(cell, row);
                Grid.SetColumn(cell, c);
                grid.Children.Add(cell);
            }
        }

        AddRow(table.Header, 0, header: true, shaded: true);
        for (var r = 0; r < table.Rows.Count; r++) AddRow(table.Rows[r], r + 1, header: false, shaded: r % 2 == 1);

        return new Border
        {
            CornerRadius = new CornerRadius(10),
            BorderThickness = new Thickness(1),
            BorderBrush = Theme.Brush(Theme.WithAlpha(theme.Secondary, 0.3)),
            Child = grid,
        };
    }

    private FrameworkElement Picture(MarkdownBlock.Image image)
    {
        Uri? uri = ImageStore.Resolve(image.Source, pagePath) is { } file && File.Exists(file)
            ? new Uri(file)
            : Uri.TryCreate(image.Source, UriKind.Absolute, out var web) && web.Scheme.StartsWith("http") ? web : null;
        if (uri is null)
        {
            return new TextBlock
            {
                Text = "🖼 " + (image.Alt.Length > 0 ? image.Alt : image.Source),
                Foreground = Theme.Brush(theme.Secondary),
                FontSize = Size * 0.9,
            };
        }
        var bitmap = new BitmapImage(uri);
        var picture = new Image { Source = bitmap, Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Left };
        // Never scale a small image up.
        bitmap.ImageOpened += (_, _) => picture.MaxWidth = bitmap.PixelWidth;
        return new Border { CornerRadius = new CornerRadius(8), Child = picture, HorizontalAlignment = HorizontalAlignment.Left };
    }

    private StackPanel Backlinks(IReadOnlyList<Backlink> backlinks)
    {
        var panel = new StackPanel { Spacing = 8, Margin = new Thickness(0, Size * 2, 0, 0) };
        panel.Children.Add(new TextBlock
        {
            Text = "GELINKT VANUIT",
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            CharacterSpacing = 80,
            Foreground = Theme.Brush(theme.Secondary),
        });
        foreach (var backlink in backlinks)
        {
            var card = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(14, 10, 14, 10),
                CornerRadius = new CornerRadius(12),
                Background = Theme.Brush(theme.CodeBackground),
                BorderThickness = new Thickness(0),
                Content = new StackPanel
                {
                    Spacing = 3,
                    Children =
                    {
                        new TextBlock { Text = backlink.Title, FontWeight = FontWeights.SemiBold, FontSize = 14, Foreground = Theme.Brush(theme.Text) },
                        new TextBlock { Text = backlink.Snippet, FontSize = 12.5, Foreground = Theme.Brush(theme.Secondary), TextTrimming = TextTrimming.CharacterEllipsis },
                    },
                },
            };
            card.Click += (_, _) => PageOpened?.Invoke(backlink.Path);
            panel.Children.Add(card);
        }
        return panel;
    }
}
