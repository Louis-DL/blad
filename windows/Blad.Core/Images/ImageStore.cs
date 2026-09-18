using System.Globalization;

namespace Blad.Core.Images;

/// <summary>
/// Saves pasted, dropped or chosen images into an <c>assets</c> folder next to the page and returns
/// the markdown that shows them. Plain files and relative links, so they work on GitHub and on the Mac too.
/// </summary>
public static class ImageStore
{
    public const string FolderName = "assets";

    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tif", ".tiff", ".heic", ".svg",
    };

    public static bool IsImageFile(string path) => ImageExtensions.Contains(Path.GetExtension(path));

    /// <summary>A pasted screenshot or picture, named after the page and the time.</summary>
    public static string SaveImage(byte[] data, string extension, string pagePath)
    {
        var assets = AssetsFolder(pagePath);
        var name = Slug(Path.GetFileNameWithoutExtension(pagePath)) + "-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        var destination = UniquePath(assets, name, "." + extension.TrimStart('.').ToLowerInvariant());
        File.WriteAllBytes(destination, data);
        return Markdown(destination, "", pagePath);
    }

    /// <summary>An image file dropped or chosen. Images already in the page's folder are linked where they are.</summary>
    public static string AddImageFile(string sourcePath, string pagePath)
    {
        var name = Path.GetFileNameWithoutExtension(sourcePath);
        var pageFolder = Path.GetDirectoryName(pagePath)!;
        if (Path.GetFullPath(sourcePath).StartsWith(Path.GetFullPath(pageFolder) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return Markdown(sourcePath, name, pagePath);
        }
        var destination = UniquePath(AssetsFolder(pagePath), Slug(name), Path.GetExtension(sourcePath).ToLowerInvariant());
        File.Copy(sourcePath, destination);
        return Markdown(destination, name, pagePath);
    }

    /// <summary>The file an image link on a page points to, or null for a web image.</summary>
    public static string? Resolve(string source, string pagePath)
    {
        if (source.Contains("://", StringComparison.Ordinal)) return null;
        var relative = Uri.UnescapeDataString(source).Replace('/', Path.DirectorySeparatorChar);
        return Path.GetFullPath(Path.Combine(Path.GetDirectoryName(pagePath)!, relative));
    }

    private static string AssetsFolder(string pagePath)
    {
        var folder = Path.Combine(Path.GetDirectoryName(pagePath)!, FolderName);
        Directory.CreateDirectory(folder);
        return folder;
    }

    private static string Markdown(string imagePath, string alt, string pagePath)
    {
        var relative = Path.GetRelativePath(Path.GetDirectoryName(pagePath)!, imagePath);
        var encoded = string.Join('/', relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Select(Uri.EscapeDataString));
        return $"![{alt.Replace("[", "").Replace("]", "")}]({encoded})";
    }

    /// <summary>"Schermafbeelding 2026-09-15 om 14.30" becomes "schermafbeelding-2026-09-15-om-14-30".</summary>
    private static string Slug(string name)
    {
        var words = new List<string>();
        var word = new System.Text.StringBuilder();
        foreach (var c in name.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(c))
            {
                word.Append(c);
            }
            else if (word.Length > 0)
            {
                words.Add(word.ToString());
                word.Clear();
            }
        }
        if (word.Length > 0) words.Add(word.ToString());
        var slug = string.Join('-', words);
        return slug.Length == 0 ? "afbeelding" : slug[..Math.Min(60, slug.Length)];
    }

    private static string UniquePath(string folder, string name, string extension)
    {
        for (var number = 1; ; number++)
        {
            var candidate = Path.Combine(folder, (number == 1 ? name : $"{name}-{number}") + extension);
            if (!File.Exists(candidate)) return candidate;
        }
    }
}
