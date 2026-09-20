using Blad.Core.Markdown;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Blad;

/// <summary>The headings of the open page, to jump through a long note (Ctrl+Shift+O).</summary>
public sealed partial class MainWindow
{
    private void WireOutline() => OutlineFlyout.Opening += (_, _) => FillOutline();

    private void ShowOutline()
    {
        if (active is null) return;
        OutlineFlyout.ShowAt(OutlineButton);
    }

    private void FillOutline()
    {
        OutlinePanel.Children.Clear();
        if (active is null) return;

        var headings = Outline.Headings(active.IsReading ? active.Text : Editor.Text);
        if (headings.Count == 0)
        {
            OutlinePanel.Children.Add(new TextBlock
            {
                Text = "Nog geen kopjes",
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(4, 4, 4, 2),
            });
            OutlinePanel.Children.Add(new TextBlock
            {
                Text = "Begin een regel met # voor een kopje.",
                Opacity = 0.7,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(4, 0, 4, 4),
            });
            return;
        }

        foreach (var heading in headings)
        {
            var row = new Button
            {
                Background = null,
                BorderThickness = new Thickness(0),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(8 + (heading.Level - 1) * 14, 6, 8, 6),
                Content = new TextBlock
                {
                    Text = heading.Title,
                    FontSize = heading.Level == 1 ? 14 : 13,
                    FontWeight = heading.Level == 1 ? FontWeights.SemiBold : FontWeights.Normal,
                    Opacity = heading.Level <= 2 ? 1 : 0.7,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                },
            };
            row.Click += (_, _) =>
            {
                OutlineFlyout.Hide();
                JumpTo(heading);
            };
            OutlinePanel.Children.Add(row);
        }
    }

    private void JumpTo(Heading heading)
    {
        if (active is null) return;
        if (active.IsReading)
        {
            Reading.ScrollToHeading(heading.Index);
        }
        else
        {
            Editor.Select(heading.Offset, 0);
            Editor.Focus();
        }
    }
}
