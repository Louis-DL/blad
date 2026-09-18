using System.Diagnostics;
using Blad.Core.Pages;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Blad;

/// <summary>One row in the sidebar: a space, a folder or a page.</summary>
internal sealed record SidebarEntry(string Path, bool IsFolder, bool IsSpace);

public sealed partial class MainWindow
{
    private readonly HashSet<string> expandedFolders = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> collapsedSpaces = new(StringComparer.OrdinalIgnoreCase);

    private void WireSidebar()
    {
        PagesTree.ItemInvoked += (_, args) =>
        {
            if (args.InvokedItem is not TreeViewNode { Content: FrameworkElement { Tag: SidebarEntry entry } } node) return;
            if (entry.IsFolder) node.IsExpanded = !node.IsExpanded;
            else Show(entry.Path);
        };
        PagesTree.Expanding += (_, args) => Remember(args.Node, expanded: true);
        PagesTree.Collapsed += (_, args) => Remember(args.Node, expanded: false);
    }

    private void Remember(TreeViewNode node, bool expanded)
    {
        if (node.Content is not FrameworkElement { Tag: SidebarEntry entry }) return;
        if (entry.IsSpace)
        {
            if (expanded) collapsedSpaces.Remove(entry.Path);
            else collapsedSpaces.Add(entry.Path);
        }
        else if (expanded)
        {
            expandedFolders.Add(entry.Path);
        }
        else
        {
            expandedFolders.Remove(entry.Path);
        }
    }

    private void RebuildTree()
    {
        PagesTree.RootNodes.Clear();
        EmptySidebar.Visibility = library.Spaces.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var space in library.Spaces)
        {
            var node = new TreeViewNode
            {
                Content = Row(new SidebarEntry(space, IsFolder: true, IsSpace: true), Path.GetFileName(space)),
                IsExpanded = !collapsedSpaces.Contains(space),
            };
            AddChildren(node, library.Tree(space));
            PagesTree.RootNodes.Add(node);
        }
        if (active is not null) SelectInTree(active.Path);
        if (active is null) BuildWelcome();
    }

    private void AddChildren(TreeViewNode parent, IReadOnlyList<PageNode> pages)
    {
        foreach (var page in pages)
        {
            var node = new TreeViewNode
            {
                Content = Row(new SidebarEntry(page.Path, page.IsFolder, IsSpace: false), page.Name),
                IsExpanded = page.IsFolder && expandedFolders.Contains(page.Path),
            };
            if (page.IsFolder) AddChildren(node, page.Children);
            parent.Children.Add(node);
        }
    }

    private FrameworkElement Row(SidebarEntry entry, string name)
    {
        var glyph = entry.IsSpace ? "" : entry.IsFolder ? "" : "";
        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            Tag = entry,
            ContextFlyout = Menu(entry),
            Children =
            {
                new FontIcon { Glyph = glyph, FontSize = 14, Opacity = entry.IsSpace ? 1 : 0.75 },
                new TextBlock
                {
                    Text = name,
                    FontWeight = entry.IsSpace ? FontWeights.SemiBold : FontWeights.Normal,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                },
            },
        };
    }

    private MenuFlyout Menu(SidebarEntry entry)
    {
        var menu = new MenuFlyout();
        void Add(string text, string glyph, Action action)
        {
            var item = new MenuFlyoutItem { Text = text, Icon = new FontIcon { Glyph = glyph } };
            item.Click += (_, _) => action();
            menu.Items.Add(item);
        }

        if (entry.IsFolder)
        {
            Add("Nieuwe pagina", "", () => NewPage(entry.Path));
            Add("Nieuwe map", "", () => library.NewFolder(entry.Path));
            menu.Items.Add(new MenuFlyoutSeparator());
        }
        if (!entry.IsSpace) Add("Wijzig naam…", "", () => _ = RenameAsync(entry.Path));
        Add("Toon in Verkenner", "", () => ShowInExplorer(entry.Path));
        menu.Items.Add(new MenuFlyoutSeparator());
        if (entry.IsSpace) Add("Verwijder uit Blad", "", () => library.RemoveSpace(entry.Path));
        else Add("Verplaats naar de Prullenbak", "", () => _ = DeleteAsync(entry.Path));
        return menu;
    }

    private void SelectInTree(string path)
    {
        TreeViewNode? Find(IEnumerable<TreeViewNode> nodes)
        {
            foreach (var node in nodes)
            {
                if (node.Content is FrameworkElement { Tag: SidebarEntry entry } && Library.SamePath(entry.Path, path)) return node;
                if (Find(node.Children) is { } found) return found;
            }
            return null;
        }
        if (Find(PagesTree.RootNodes) is { } match) PagesTree.SelectedNode = match;
    }

    private async Task RenameAsync(string path)
    {
        var current = Directory.Exists(path) ? Path.GetFileName(path) : Path.GetFileNameWithoutExtension(path);
        var name = await Dialogs.AskNameAsync(Root.XamlRoot, "Wijzig naam", "Naam", initial: current, confirm: "Wijzig naam");
        if (name is not null) library.Rename(path, name);
    }

    private async Task DeleteAsync(string path)
    {
        var name = Directory.Exists(path) ? Path.GetFileName(path) : Path.GetFileNameWithoutExtension(path);
        var confirmed = await Dialogs.ConfirmAsync(Root.XamlRoot, $"{name} verwijderen?",
            "Het gaat naar de Prullenbak; daar kun je het terugzetten.", "Verplaats naar de Prullenbak");
        if (!confirmed) return;
        foreach (var tab in Tabs.TabItems.OfType<TabViewItem>().Where(tab => Library.IsInside((string)tab.Tag, path)).ToList())
        {
            ClosePage((string)tab.Tag);
        }
        await library.DeleteAsync(path);
    }

    private static void ShowInExplorer(string path) =>
        Process.Start("explorer.exe", $"/select,\"{path}\"");
}
