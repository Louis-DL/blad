using System.Text.Json;
using System.Text.Json.Serialization;

namespace Blad;

/// <summary>Everything Blad remembers between launches, in %LOCALAPPDATA%\Blad\settings.json.</summary>
public sealed class AppSettings
{
    public List<string> Spaces { get; set; } = [];
    public List<string> OpenPages { get; set; } = [];
    public string? ActivePage { get; set; }
    public List<string> RecentPages { get; set; } = [];

    public string Theme { get; set; } = "paper";
    public bool PaperGrain { get; set; } = true;
    public string Font { get; set; } = EditorFonts.DefaultId;
    public double FontSize { get; set; } = 17;
    public double LineWidth { get; set; } = 680;
    public bool ShowTabs { get; set; } = true;
    public bool ShowWordCount { get; set; } = true;
    public string Sort { get; set; } = "name";

    [JsonIgnore]
    public static AppSettings Current { get; } = Load();

    /// <summary>Raised after a change is saved, so open views can restyle.</summary>
    public event Action? Changed;

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Blad", "settings.json");

    /// <param name="notify">False for bookkeeping like open tabs, which doesn't change how anything looks.</param>
    public void Save(bool notify = true)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
        if (notify) Changed?.Invoke();
    }

    private static AppSettings Load()
    {
        try
        {
            return File.Exists(FilePath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            // A damaged settings file shouldn't keep Blad from opening.
            return new AppSettings();
        }
    }
}
