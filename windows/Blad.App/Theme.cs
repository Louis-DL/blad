using Blad.Core.Export;
using Blad.Core.Markdown;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace Blad;

public enum ThemeId { Paper, Light, Night, System }

/// <summary>The four colours a code block uses.</summary>
public sealed record CodeColors(Color Keyword, Color String, Color Number, Color Comment)
{
    public Color For(CodeToken token) => token switch
    {
        CodeToken.Keyword => Keyword,
        CodeToken.String => String,
        CodeToken.Number => Number,
        _ => Comment,
    };
}

/// <summary>Blad's colours: the same Papier, Licht and Nacht as on the Mac and iPhone.</summary>
public sealed record Theme(
    Color Background,
    Color Text,
    Color Secondary,
    Color Accent,
    Color CodeBackground,
    Color Selection,
    /// <summary>Keyword, string, number and comment colours inside a code block.</summary>
    CodeColors Code,
    bool IsDark,
    bool HasGrain)
{
    public static Theme Paper { get; } = new(
        Hex(0xF4EFE5), Hex(0x2F2A23), Hex(0xA69D8E), Hex(0xB4532A), Hex(0x6B5A3E, 0.075), Hex(0xB4532A, 0.17),
        new CodeColors(Hex(0xA24A22), Hex(0x5E7444), Hex(0x3F6E72), Hex(0xA69D8E)), false, true);

    public static Theme Light { get; } = new(
        Hex(0xFBFBFA), Hex(0x1D1D1F), Hex(0xA1A1A6), Hex(0x3569DE), Hex(0x1D1D1F, 0.05), Hex(0x3569DE, 0.16),
        new CodeColors(Hex(0xCF222E), Hex(0x0A3069), Hex(0x0550AE), Hex(0x8E8E93)), false, false);

    public static Theme Night { get; } = new(
        Hex(0x1B1A19), Hex(0xE5E1D8), Hex(0x6F6A62), Hex(0xE39A5B), Hex(0xFFFFFF, 0.06), Hex(0xE39A5B, 0.24),
        new CodeColors(Hex(0xE5A06A), Hex(0xA8C58A), Hex(0x8FC0D0), Hex(0x8A8177)), true, false);

    public static ThemeId Parse(string id) => id switch
    {
        "light" => ThemeId.Light,
        "night" => ThemeId.Night,
        "system" => ThemeId.System,
        _ => ThemeId.Paper,
    };

    public static string Key(ThemeId id) => id.ToString().ToLowerInvariant();

    public static string Label(ThemeId id) => id switch
    {
        ThemeId.Paper => "Papier",
        ThemeId.Light => "Licht",
        ThemeId.Night => "Nacht",
        _ => "Automatisch",
    };

    public static Theme For(ThemeId id) => id switch
    {
        ThemeId.Paper => Paper,
        ThemeId.Light => Light,
        ThemeId.Night => Night,
        _ => SystemIsDark() ? Night : Paper,
    };

    public static Theme Current => For(Parse(AppSettings.Current.Theme));

    public ElementTheme ElementTheme => IsDark ? ElementTheme.Dark : ElementTheme.Light;

    public static SolidColorBrush Brush(Color color) => new(color);

    public static Color WithAlpha(Color color, double alpha) =>
        Color.FromArgb((byte)Math.Round(alpha * 255), color.R, color.G, color.B);

    public ExportStyle ToExportStyle(string fontId, double fontSize) => new(
        Css(Background), Css(Text), Css(Secondary), Css(Accent), Css(CodeBackground),
        new CodeColours(Css(Code.Keyword), Css(Code.String), Css(Code.Number), Css(Code.Comment)), IsDark,
        EditorFonts.CssFamily(fontId), fontSize);

    private static bool SystemIsDark()
    {
        var background = new UISettings().GetColorValue(UIColorType.Background);
        return background.R + background.G + background.B < 382;
    }

    private static string Css(Color color) =>
        $"rgba({color.R}, {color.G}, {color.B}, {(color.A / 255.0).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)})";

    private static Color Hex(uint hex, double alpha = 1) =>
        Color.FromArgb((byte)Math.Round(alpha * 255), (byte)(hex >> 16), (byte)(hex >> 8), (byte)hex);
}

/// <summary>
/// Fonts for writing. New York doesn't exist on Windows, and Windows 11's Sitka is a variable font that the
/// editor's text box doesn't take reliably, so these are fonts that come with Windows as plain font files.
/// </summary>
public static class EditorFonts
{
    public const string DefaultId = "georgia";

    /// <summary>Cascadia Mono comes with Windows 11; Windows 10 has Consolas.</summary>
    public static string CodeFamily { get; } = HasFont("CascadiaMono") ? "Cascadia Mono" : "Consolas";

    public static IReadOnlyList<(string Id, string Name, string Family)> Presets { get; } =
    [
        ("georgia", "Georgia", "Georgia"),
        ("cambria", "Cambria", "Cambria"),
        ("segoe", "Segoe UI", "Segoe UI"),
        ("cascadia", "Monospace", CodeFamily),
    ];

    public static string Family(string id) =>
        Presets.FirstOrDefault(preset => preset.Id == id).Family ?? "Georgia";

    public static FontFamily FontFamily(string id) => new(Family(id));

    public static string CssFamily(string id) => id switch
    {
        "segoe" => "'Segoe UI Variable Text', 'Segoe UI', system-ui, sans-serif",
        "cascadia" => "'Cascadia Mono', Consolas, monospace",
        "cambria" => "Cambria, Georgia, serif",
        _ => "Georgia, Cambria, serif",
    };

    private static bool HasFont(string filePrefix)
    {
        try
        {
            return Directory.EnumerateFiles(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), filePrefix + "*").Any();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
