using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Blad;

/// <summary>Instellingen: theme, type and layout. Changes apply right away.</summary>
public static class SettingsDialog
{
    public static async Task ShowAsync(XamlRoot root)
    {
        var settings = AppSettings.Current;

        var theme = new RadioButtons { Header = "Thema", MaxColumns = 4 };
        foreach (var id in Enum.GetValues<ThemeId>()) theme.Items.Add(Theme.Label(id));
        theme.SelectedIndex = (int)Theme.Parse(settings.Theme);
        theme.SelectionChanged += (_, _) => Apply(() => settings.Theme = Theme.Key((ThemeId)theme.SelectedIndex));

        var grain = new ToggleSwitch { Header = "Papierstructuur", IsOn = settings.PaperGrain };
        grain.Toggled += (_, _) => Apply(() => settings.PaperGrain = grain.IsOn);

        var font = new ComboBox { Header = "Lettertype", MinWidth = 220 };
        foreach (var preset in EditorFonts.Presets) font.Items.Add(new ComboBoxItem { Content = preset.Name, Tag = preset.Id });
        font.SelectedIndex = Math.Max(0, EditorFonts.Presets.ToList().FindIndex(preset => preset.Id == settings.Font));
        font.SelectionChanged += (_, _) => Apply(() => settings.Font = (string)((ComboBoxItem)font.SelectedItem).Tag);

        var size = new Slider { Header = "Grootte", Minimum = 12, Maximum = 28, StepFrequency = 1, Value = settings.FontSize };
        size.ValueChanged += (_, _) => Apply(() => settings.FontSize = size.Value);

        var width = new Slider { Header = "Regelbreedte", Minimum = 480, Maximum = 1000, StepFrequency = 20, Value = settings.LineWidth };
        width.ValueChanged += (_, _) => Apply(() => settings.LineWidth = width.Value);

        var tabs = new ToggleSwitch { Header = "Tabbladen", IsOn = settings.ShowTabs };
        tabs.Toggled += (_, _) => Apply(() => settings.ShowTabs = tabs.IsOn);

        var words = new ToggleSwitch { Header = "Woordentelling", IsOn = settings.ShowWordCount };
        words.Toggled += (_, _) => Apply(() => settings.ShowWordCount = words.IsOn);

        var sort = new ComboBox { Header = "Sorteer pagina's op", Items = { "Naam", "Laatst gewijzigd" } };
        sort.SelectedIndex = settings.Sort == "modified" ? 1 : 0;
        sort.SelectionChanged += (_, _) =>
        {
            Apply(() => settings.Sort = sort.SelectedIndex == 1 ? "modified" : "name");
            _ = Library.Shared.RefreshAsync();
        };

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Instellingen",
            CloseButtonText = "Klaar",
            Content = new ScrollViewer
            {
                Content = new StackPanel
                {
                    Spacing = 16,
                    Children = { theme, grain, font, size, width, tabs, words, sort },
                },
            },
        };
        await dialog.ShowAsync();
    }

    private static void Apply(Action change)
    {
        change();
        AppSettings.Current.Save();
    }
}
