using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Blad;

/// <summary>Find and replace inside the open page: the bar above the paper (Ctrl+F).</summary>
public sealed partial class MainWindow
{
    private readonly List<int> matches = [];
    private int matchIndex = -1;

    private bool IsFindOpen => FindBar.Visibility == Visibility.Visible;

    private void WireFind()
    {
        FindBox.TextChanged += (_, _) => FindMatches(keepPlace: false);
        FindBox.KeyDown += OnFindKey;
        ReplaceBox.KeyDown += OnFindKey;
        FindNextButton.Click += (_, _) => Step(1);
        FindPreviousButton.Click += (_, _) => Step(-1);
        ReplaceButton.Click += (_, _) => ReplaceCurrent();
        ReplaceAllButton.Click += (_, _) => ReplaceEvery();
        CloseFindButton.Click += (_, _) => CloseFind();
    }

    private void OnFindKey(object sender, KeyRoutedEventArgs args)
    {
        var shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        switch (args.Key)
        {
            case VirtualKey.Enter when sender == ReplaceBox:
                ReplaceCurrent();
                args.Handled = true;
                break;
            case VirtualKey.Enter:
                Step(shift ? -1 : 1);
                args.Handled = true;
                break;
            case VirtualKey.Escape:
                CloseFind();
                args.Handled = true;
                break;
        }
    }

    /// <summary>Opens the bar, starting from whatever is selected in the page.</summary>
    private void ShowFind()
    {
        if (active is null) return;
        if (active.IsReading) ToggleReading();

        var (start, length) = Editor.Selection;
        if (length is > 0 and < 120)
        {
            var selected = Editor.Text.Substring(start, length);
            if (!selected.Contains('\r')) FindBox.Text = selected;
        }
        FindBar.Visibility = Visibility.Visible;
        FindBox.Focus(FocusState.Programmatic);
        FindBox.SelectAll();
        FindMatches(keepPlace: false);
    }

    private void CloseFind()
    {
        FindBar.Visibility = Visibility.Collapsed;
        matches.Clear();
        matchIndex = -1;
        Editor.Focus();
    }

    /// <summary>Looks up every match and moves to the one after the caret.</summary>
    private void FindMatches(bool keepPlace)
    {
        var atNow = matchIndex >= 0 && matchIndex < matches.Count ? matches[matchIndex] : Editor.Selection.Start;
        matches.Clear();
        matchIndex = -1;

        var needle = FindBox.Text;
        var text = Editor.Text;
        if (needle.Length > 0)
        {
            var at = 0;
            while (at <= text.Length - needle.Length)
            {
                var next = text.IndexOf(needle, at, StringComparison.CurrentCultureIgnoreCase);
                if (next < 0) break;
                matches.Add(next);
                at = next + 1;
            }
        }

        if (matches.Count > 0)
        {
            matchIndex = matches.FindIndex(start => start >= atNow);
            if (matchIndex < 0) matchIndex = 0;
            if (!keepPlace) Editor.Select(matches[matchIndex], needle.Length);
        }
        ShowMatchCount();
    }

    private void Step(int direction)
    {
        if (FindBox.Text.Length == 0) return;
        if (matches.Count == 0)
        {
            FindMatches(keepPlace: false);
            if (matches.Count == 0) return;
        }
        matchIndex = (matchIndex + direction + matches.Count) % matches.Count;
        Editor.Select(matches[matchIndex], FindBox.Text.Length);
        ShowMatchCount();
    }

    private void ReplaceCurrent()
    {
        if (matches.Count == 0 || matchIndex < 0) return;
        var start = matches[matchIndex];
        Editor.ReplaceRange(start, FindBox.Text.Length, ReplaceBox.Text);
        FindMatches(keepPlace: true);
        if (matches.Count > 0)
        {
            matchIndex = matches.FindIndex(at => at >= start + ReplaceBox.Text.Length);
            if (matchIndex < 0) matchIndex = 0;
            Editor.Select(matches[matchIndex], FindBox.Text.Length);
            ShowMatchCount();
        }
    }

    private void ReplaceEvery()
    {
        if (FindBox.Text.Length == 0) return;
        var replaced = Editor.ReplaceAll(FindBox.Text, ReplaceBox.Text);
        FindMatches(keepPlace: true);
        FindCount.Text = replaced switch
        {
            0 => "Niets gevonden",
            1 => "1 vervangen",
            _ => $"{replaced} vervangen",
        };
    }

    private void ShowMatchCount() =>
        FindCount.Text = matches.Count == 0
            ? FindBox.Text.Length == 0 ? "" : "Niets gevonden"
            : $"{matchIndex + 1} van {matches.Count}";
}
