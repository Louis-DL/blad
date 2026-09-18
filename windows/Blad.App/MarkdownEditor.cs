using System.Text.RegularExpressions;
using Blad.Core.Images;
using Blad.Core.Markdown;
using Blad.Core.Pages;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;
using Windows.System;
using Windows.UI.Core;

namespace Blad;

/// <summary>
/// The markdown editor: a RichEditBox holding plain markdown, styled like the Mac editor. The syntax stays
/// visible but quiet, and heading, quote and list markers hang in the margin so the text lines up.
/// </summary>
public sealed partial class MarkdownEditor : UserControl
{
    private static readonly double[] HeadingScale = [1.7, 1.4, 1.2, 1.08, 1.0, 1.0];

    private readonly RichEditBox box = new();
    private readonly List<(string Text, int Caret)> undo = [];
    private readonly List<(string Text, int Caret)> redo = [];
    private readonly Dictionary<(string, string, double, bool), double> widths = [];

    private PageDocument? document;
    private Theme theme = Theme.Paper;
    private string lastText = "";
    private int lastFenceCount;
    private DateTime lastUndoPoint;
    private bool isApplying;
    private double gutter;

    /// <summary>The page's text changed (with \n line breaks).</summary>
    public event Action<string>? Edited;

    /// <summary>Typed [[: show the link picker at this point, relative to the editor.</summary>
    public event Action<Point>? LinkRequested;

    /// <summary>Ctrl+click on a link: a page name for [[links]], otherwise a URL or relative path.</summary>
    public event Action<string, bool>? LinkOpened;

    public event Action<string>? ErrorOccurred;

    public MarkdownEditor()
    {
        box.AcceptsReturn = true;
        box.TextWrapping = TextWrapping.Wrap;
        box.IsSpellCheckEnabled = false;
        box.IsTextPredictionEnabled = false;
        box.ClipboardCopyFormat = RichEditClipboardFormat.PlainText;
        box.DisabledFormattingAccelerators = DisabledFormattingAccelerators.All;
        box.BorderThickness = new Thickness(0);
        box.AllowDrop = true;

        // No box around the text: the page is the paper behind it.
        var clear = new SolidColorBrush(Colors.Transparent);
        foreach (var key in new[]
        {
            "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused", "TextControlBackgroundDisabled",
            "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused", "TextControlBorderBrushDisabled",
        })
        {
            box.Resources[key] = clear;
        }

        // Blad keeps its own undo history, so restyling never ends up in it.
        box.Document.UndoLimit = 0;

        box.TextChanged += OnTextChanged;
        box.PreviewKeyDown += OnPreviewKeyDown;
        box.Paste += OnPaste;
        box.DragOver += OnDragOver;
        box.Drop += OnDrop;
        box.AddHandler(PointerPressedEvent, new PointerEventHandler(OnPointerPressed), handledEventsToo: true);
        SizeChanged += (_, _) => UpdateLayout(restyleIfNeeded: true);

        Content = box;
    }

    public void Load(PageDocument page, Theme pageTheme)
    {
        document = page;
        theme = pageTheme;
        undo.Clear();
        redo.Clear();
        SetText(page.Text.Replace('\n', '\r'), 0);
        ApplyTheme(pageTheme);
    }

    public void ApplyTheme(Theme pageTheme)
    {
        theme = pageTheme;
        box.SelectionHighlightColor = new SolidColorBrush(Theme.WithAlpha(pageTheme.Accent, 0.35));
        // The text box can miss fonts by name that the rest of the window finds (Sitka on Windows 11);
        // it then falls back to its own font, so that has to be the page font too.
        box.FontFamily = new FontFamily(Family);
        // In a dark theme the text box paints every character in its own foreground colour, which
        // would erase the quiet syntax and coloured links. Blad sets all colours itself, so keep it light.
        box.RequestedTheme = ElementTheme.Light;
        UpdateLayout(restyleIfNeeded: false);
        Restyle(full: true);
    }

    public new void Focus() => box.Focus(FocusState.Programmatic);

    /// <summary>Finishes a link after [[: the page name, then ]] unless it's already there.</summary>
    public void CompleteLink(string title)
    {
        var text = ReadText();
        var caret = Math.Min(box.Document.Selection.StartPosition, text.Length);
        var hasOpening = caret >= 2 && text.Substring(caret - 2, 2) == "[[";
        var isClosed = caret + 2 <= text.Length && text.Substring(caret, 2) == "]]";
        Insert((hasOpening ? "" : "[[") + title + (isClosed ? "" : "]]"));
        if (isClosed) MoveCaret(box.Document.Selection.StartPosition + 2);
        Focus();
    }

    // MARK: Text and undo

    private string ReadText()
    {
        box.Document.GetText(TextGetOptions.None, out var text);
        // The text box always ends with one paragraph mark of its own.
        return text.EndsWith('\r') ? text[..^1] : text;
    }

    private void SetText(string text, int caret)
    {
        isApplying = true;
        box.Document.SetText(TextSetOptions.None, text);
        isApplying = false;
        lastText = text;
        lastFenceCount = FenceCount(text);
        MoveCaret(Math.Min(caret, text.Length));
        Restyle(full: true);
    }

    private void Insert(string text)
    {
        var selection = box.Document.Selection;
        selection.SetText(TextSetOptions.None, text);
        selection.StartPosition = selection.EndPosition;
    }

    private void MoveCaret(int position)
    {
        var selection = box.Document.Selection;
        selection.StartPosition = position;
        selection.EndPosition = position;
    }

    private void OnTextChanged(object sender, RoutedEventArgs e)
    {
        if (isApplying) return;
        var text = ReadText();
        if (text == lastText) return;

        // Group quick typing into one undo step; start a new step after a pause or a bigger change.
        var delta = text.Length - lastText.Length;
        if (DateTime.Now - lastUndoPoint > TimeSpan.FromMilliseconds(800) || Math.Abs(delta) > 1)
        {
            undo.Add((lastText, box.Document.Selection.StartPosition - Math.Max(0, delta)));
            if (undo.Count > 500) undo.RemoveAt(0);
            redo.Clear();
        }
        lastUndoPoint = DateTime.Now;

        var fences = FenceCount(text);
        var full = fences != lastFenceCount || Math.Abs(delta) > 1;
        lastFenceCount = fences;
        lastText = text;
        Restyle(full);
        Edited?.Invoke(text.Replace('\r', '\n'));

        var caret = box.Document.Selection.StartPosition;
        if (delta == 1 && caret >= 2 && caret <= text.Length && text.Substring(caret - 2, 2) == "[[")
        {
            LinkRequested?.Invoke(CaretPoint());
        }
    }

    private void Undo()
    {
        if (undo.Count == 0) return;
        redo.Add((lastText, box.Document.Selection.StartPosition));
        var (text, caret) = undo[^1];
        undo.RemoveAt(undo.Count - 1);
        SetText(text, caret);
        Edited?.Invoke(text.Replace('\r', '\n'));
    }

    private void Redo()
    {
        if (redo.Count == 0) return;
        undo.Add((lastText, box.Document.Selection.StartPosition));
        var (text, caret) = redo[^1];
        redo.RemoveAt(redo.Count - 1);
        SetText(text, caret);
        Edited?.Invoke(text.Replace('\r', '\n'));
    }

    // MARK: Keys

    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var control = IsDown(VirtualKey.Control);
        var shift = IsDown(VirtualKey.Shift);

        if (control && e.Key == VirtualKey.Z) { if (shift) Redo(); else Undo(); e.Handled = true; }
        else if (control && e.Key == VirtualKey.Y) { Redo(); e.Handled = true; }
        else if (control && e.Key == VirtualKey.B) { Wrap("**"); e.Handled = true; }
        else if (control && e.Key == VirtualKey.I) { Wrap("*"); e.Handled = true; }
        else if (e.Key == VirtualKey.Enter && !shift && !control) { e.Handled = ContinueList(); }
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private void Wrap(string marker)
    {
        var selection = box.Document.Selection;
        var start = selection.StartPosition;
        selection.GetText(TextGetOptions.None, out var selected);
        selection.SetText(TextSetOptions.None, marker + selected + marker);
        selection.StartPosition = start + marker.Length;
        selection.EndPosition = start + marker.Length + selected.Length;
    }

    /// <summary>Enter in a list or quote continues it; on an empty item it ends the list.</summary>
    private bool ContinueList()
    {
        var selection = box.Document.Selection;
        if (selection.StartPosition != selection.EndPosition) return false;
        var text = ReadText();
        var caret = Math.Min(selection.StartPosition, text.Length);
        var lineStart = caret == 0 ? 0 : text.LastIndexOf('\r', caret - 1) + 1;
        var lineEnd = text.IndexOf('\r', caret) is var end and >= 0 ? end : text.Length;
        var before = text[lineStart..caret];
        var after = text[caret..lineEnd];

        string continuation;
        int prefixLength;
        if (EditorStyler.ListItem().Match(before) is { Success: true } item)
        {
            var marker = item.Groups[2].Value;
            if (int.TryParse(marker[..^1], out var number)) marker = $"{number + 1}{marker[^1]}";
            var task = item.Groups[4].Success ? "[ ] " : "";
            continuation = item.Groups[1].Value + marker + item.Groups[3].Value + task;
            prefixLength = item.Length;
        }
        else if (QuotePrefix().Match(before) is { Success: true } quote)
        {
            continuation = quote.Value;
            prefixLength = quote.Length;
        }
        else
        {
            return false;
        }

        if (prefixLength == before.Length && after.Trim().Length == 0)
        {
            // Empty item: remove the marker and leave the list.
            var range = box.Document.GetRange(lineStart, lineStart + prefixLength);
            range.SetText(TextSetOptions.None, "");
            MoveCaret(lineStart);
        }
        else
        {
            Insert("\r" + continuation);
        }
        return true;
    }

    // MARK: Links

    private Point CaretPoint()
    {
        box.Document.Selection.GetRect(PointOptions.ClientCoordinates, out var rect, out _);
        return new Point(rect.X, rect.Y + rect.Height);
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (!IsDown(VirtualKey.Control)) return;
        var point = e.GetCurrentPoint(box).Position;
        var range = box.Document.GetRangeFromPoint(point, PointOptions.ClientCoordinates);
        var text = ReadText();
        var offset = range.StartPosition;
        var lineStart = offset == 0 ? 0 : text.LastIndexOf('\r', Math.Max(0, offset - 1)) + 1;
        var lineEnd = text.IndexOf('\r', offset) is var end and >= 0 ? end : text.Length;
        var line = text[lineStart..lineEnd];
        var column = offset - lineStart;

        foreach (Match match in WikiLinks.Pattern().Matches(line))
        {
            if (column >= match.Index && column <= match.Index + match.Length)
            {
                LinkOpened?.Invoke(match.Groups[1].Value.Trim(), true);
                return;
            }
        }
        foreach (Match match in LinkOrUrl().Matches(line))
        {
            if (column >= match.Index && column <= match.Index + match.Length)
            {
                LinkOpened?.Invoke(match.Groups[1].Success ? match.Groups[1].Value : match.Value, false);
                return;
            }
        }
    }

    // MARK: Paste and drop

    private async void OnPaste(object sender, TextControlPasteEventArgs e)
    {
        var content = Clipboard.GetContent();
        if (content.Contains(StandardDataFormats.StorageItems))
        {
            var files = (await content.GetStorageItemsAsync()).OfType<StorageFile>().Where(f => ImageStore.IsImageFile(f.Path)).ToList();
            if (files.Count > 0)
            {
                e.Handled = true;
                InsertImages(files.Select(f => f.Path));
                return;
            }
        }
        if (content.Contains(StandardDataFormats.Text))
        {
            // Paste as plain markdown, never as formatted text.
            e.Handled = true;
            var text = await content.GetTextAsync();
            Insert(text.Replace("\r\n", "\r").Replace('\n', '\r'));
            return;
        }
        if (content.Contains(StandardDataFormats.Bitmap) && document is not null)
        {
            e.Handled = true;
            try
            {
                var png = await ReadPngAsync(await content.GetBitmapAsync());
                InsertMarkdown([ImageStore.SaveImage(png, "png", document.Path)]);
            }
            catch (Exception exception)
            {
                ErrorOccurred?.Invoke($"Kon de afbeelding niet bewaren.\n\n{exception.Message}");
            }
        }
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Voeg afbeelding in";
            e.Handled = true;
        }
    }

    private async void OnDrop(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        e.Handled = true;
        var items = await e.DataView.GetStorageItemsAsync();
        InsertImages(items.OfType<StorageFile>().Select(file => file.Path).Where(ImageStore.IsImageFile));
    }

    public void InsertImages(IEnumerable<string> paths)
    {
        if (document is null) return;
        try
        {
            InsertMarkdown(paths.Select(path => ImageStore.AddImageFile(path, document.Path)).ToList());
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            ErrorOccurred?.Invoke($"Kon de afbeelding niet toevoegen.\n\n{exception.Message}");
        }
    }

    /// <summary>Each image on its own line.</summary>
    private void InsertMarkdown(IReadOnlyList<string> snippets)
    {
        if (snippets.Count == 0) return;
        var text = ReadText();
        var caret = Math.Min(box.Document.Selection.StartPosition, text.Length);
        var startsLine = caret == 0 || text[caret - 1] == '\r';
        var endsLine = caret >= text.Length || text[caret] == '\r';
        Insert((startsLine ? "" : "\r") + string.Join('\r', snippets) + (endsLine ? "" : "\r"));
    }

    private static async Task<byte[]> ReadPngAsync(RandomAccessStreamReference reference)
    {
        using var source = await reference.OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(source);
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        using var output = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, output);
        encoder.SetSoftwareBitmap(bitmap);
        await encoder.FlushAsync();
        var bytes = new byte[output.Size];
        using var reader = new DataReader(output.GetInputStreamAt(0));
        await reader.LoadAsync((uint)output.Size);
        reader.ReadBytes(bytes);
        return bytes;
    }

    // MARK: Styling

    private double FontSize => AppSettings.Current.FontSize;
    private string Family => EditorFonts.Family(AppSettings.Current.Font);

    /// <summary>Centres the text column; the margin for hanging markers is narrower in a small window.</summary>
    private void UpdateLayout(bool restyleIfNeeded)
    {
        var newGutter = FontSize * (ActualWidth > 0 && ActualWidth < 640 ? 1.2 : 3.2);
        var column = AppSettings.Current.LineWidth + newGutter * 2;
        var side = Math.Max(12, (ActualWidth - column) / 2);
        // Padding shrinks what's visible rather than adding room to scroll, so keep the bottom small.
        box.Padding = new Thickness(side, 36, side, 12);
        if (Math.Abs(newGutter - gutter) > 0.5)
        {
            gutter = newGutter;
            if (restyleIfNeeded) Restyle(full: true);
        }
    }

    /// <summary>Restyles the lines around the caret, or everything after bigger changes.</summary>
    private void Restyle(bool full)
    {
        var text = lastText;
        var styling = EditorStyler.Style(text);
        if (styling.Lines.Count == 0) return;

        int from = 0, to = text.Length;
        if (!full)
        {
            var caret = Math.Min(box.Document.Selection.StartPosition, text.Length);
            var index = styling.Lines.ToList().FindIndex(line => caret >= line.Start && caret <= line.Start + line.Length);
            if (index < 0) index = styling.Lines.Count - 1;
            var first = styling.Lines[Math.Max(0, index - 1)];
            var last = styling.Lines[Math.Min(styling.Lines.Count - 1, index + 1)];
            from = first.Start;
            to = last.Start + last.Length;
        }

        var points = FontSize * 0.75;
        var gutterPoints = (float)(gutter * 0.75);
        isApplying = true;
        box.Document.BatchDisplayUpdates();
        try
        {
            var all = box.Document.GetRange(from, to + 1);
            var format = all.CharacterFormat;
            format.Name = Family;
            format.Size = (float)points;
            format.ForegroundColor = theme.Text;
            format.BackgroundColor = Colors.Transparent;
            format.Bold = FormatEffect.Off;
            format.Italic = FormatEffect.Off;
            format.Strikethrough = FormatEffect.Off;
            var paragraph = all.ParagraphFormat;
            paragraph.SetIndents(0, gutterPoints, gutterPoints);
            paragraph.SetLineSpacing(LineSpacingRule.Multiple, 1.4f);
            paragraph.SpaceBefore = 0;
            paragraph.SpaceAfter = 0;

            foreach (var line in styling.Lines.Where(line => line.Start <= to && line.Start + line.Length >= from))
            {
                StyleLine(line, points, gutterPoints);
            }
            foreach (var span in styling.Spans.Where(span => span.Start <= to && span.Start + span.Length >= from))
            {
                StyleSpan(span, points);
            }
        }
        finally
        {
            box.Document.ApplyDisplayUpdates();
            isApplying = false;
        }
    }

    private void StyleLine(LineStyle line, double points, float gutterPoints)
    {
        var range = box.Document.GetRange(line.Start, line.Start + line.Length + 1);
        switch (line.Kind)
        {
            case LineKind.Heading:
            {
                var size = FontSize * HeadingScale[line.HeadingLevel - 1];
                range.CharacterFormat.Size = (float)(size * 0.75);
                range.CharacterFormat.Bold = FormatEffect.On;
                var marker = (float)(Measure(lastText.Substring(line.Start, line.MarkerLength), size, bold: true) * 0.75);
                range.ParagraphFormat.SetIndents(-Math.Min(marker, gutterPoints), gutterPoints, gutterPoints);
                if (line.Start > 0) range.ParagraphFormat.SpaceBefore = (float)(points * (line.HeadingLevel <= 2 ? 1.2 : 0.8));
                break;
            }
            case LineKind.Quote:
            {
                range.CharacterFormat.Italic = FormatEffect.On;
                range.CharacterFormat.ForegroundColor = Theme.WithAlpha(theme.Text, 0.75);
                var marker = (float)(Measure(lastText.Substring(line.Start, line.MarkerLength), FontSize, bold: false) * 0.75);
                range.ParagraphFormat.SetIndents(-Math.Min(marker, gutterPoints), gutterPoints, gutterPoints);
                break;
            }
            case LineKind.ListItem:
            {
                var prefix = (float)(Measure(lastText.Substring(line.Start, line.MarkerLength), FontSize, bold: false) * 0.75);
                range.ParagraphFormat.SetIndents(-prefix, gutterPoints + prefix, gutterPoints);
                break;
            }
            case LineKind.Code:
            case LineKind.CodeFence:
                range.CharacterFormat.Name = EditorFonts.CodeFamily;
                range.CharacterFormat.Size = (float)(points * 0.86);
                range.CharacterFormat.BackgroundColor = Opaque(theme.CodeBackground);
                range.ParagraphFormat.SetLineSpacing(LineSpacingRule.Multiple, 1.25f);
                break;
            case LineKind.Image:
                range.CharacterFormat.Name = EditorFonts.CodeFamily;
                range.CharacterFormat.Size = (float)(points * 0.86);
                break;
        }
    }

    private void StyleSpan(StyleSpan span, double points)
    {
        var format = box.Document.GetRange(span.Start, span.Start + span.Length).CharacterFormat;
        switch (span.Kind)
        {
            case SpanKind.Syntax:
                format.ForegroundColor = theme.Secondary;
                break;
            case SpanKind.Bold:
                format.Bold = FormatEffect.On;
                break;
            case SpanKind.Italic:
                format.Italic = FormatEffect.On;
                break;
            case SpanKind.Strike:
                format.Strikethrough = FormatEffect.On;
                break;
            case SpanKind.InlineCode:
                format.Name = EditorFonts.CodeFamily;
                format.Size = (float)(points * 0.88);
                format.BackgroundColor = Opaque(theme.CodeBackground);
                break;
            case SpanKind.LinkText:
            case SpanKind.Url:
            case SpanKind.ListMarker:
                format.ForegroundColor = theme.Accent;
                break;
            case SpanKind.DoneTask:
                format.ForegroundColor = theme.Secondary;
                format.Strikethrough = FormatEffect.On;
                break;
        }
    }

    /// <summary>Text box backgrounds can't be see-through; mix the tint into the page colour instead.</summary>
    private Windows.UI.Color Opaque(Windows.UI.Color tint)
    {
        var a = tint.A / 255.0;
        byte Mix(byte over, byte under) => (byte)Math.Round(over * a + under * (1 - a));
        return Windows.UI.Color.FromArgb(255, Mix(tint.R, theme.Background.R), Mix(tint.G, theme.Background.G), Mix(tint.B, theme.Background.B));
    }

    /// <summary>The width of a marker in DIPs, measured with the editor's font.</summary>
    private double Measure(string text, double size, bool bold)
    {
        var key = (text, Family, size, bold);
        if (widths.TryGetValue(key, out var width)) return width;
        var block = new TextBlock
        {
            Text = text.Replace(' ', ' '),
            FontFamily = new FontFamily(Family),
            FontSize = size,
            FontWeight = bold ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
        };
        block.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        widths[key] = block.DesiredSize.Width;
        return block.DesiredSize.Width;
    }

    private static int FenceCount(string text) => FenceLine().Count(text);

    [GeneratedRegex(@"(^|\r)[ \t]*(```|~~~)")]
    private static partial Regex FenceLine();

    [GeneratedRegex(@"^[ \t]*>[ \t]?")]
    private static partial Regex QuotePrefix();

    /// <summary>A markdown link (group 1 is the target) or a bare URL.</summary>
    [GeneratedRegex(@"!?\[[^\]\r]+\]\(([^)\s]+)\)|https?://[^\s)>\]]+")]
    private static partial Regex LinkOrUrl();
}
