using Blad.Core;
using Microsoft.UI.Xaml;

namespace Blad;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Greeting.Text = WordCounter.Count("Blad") == 1 ? "Blad" : "?";
    }
}
