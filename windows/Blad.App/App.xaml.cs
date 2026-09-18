using Microsoft.UI.Xaml;

namespace Blad;

public partial class App : Application
{
    private Window? window;

    public App()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) => WriteCrashLog(args.ExceptionObject as Exception);
        InitializeComponent();
        UnhandledException += (_, args) => WriteCrashLog(args.Exception);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        window = new MainWindow();
        window.Activate();
    }

    /// <summary>Keeps the reason Blad stopped in %LOCALAPPDATA%\Blad\crash.log, so it can be sent along with a bug report.</summary>
    private static void WriteCrashLog(Exception? exception)
    {
        try
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Blad");
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, "crash.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}\n{exception}\n\n");
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
