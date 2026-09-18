using System.Text;

namespace Blad.Core;

public static class WordCounter
{
    /// <summary>Counts runs of text that contain a letter or digit, so markdown symbols like # or - don't count.</summary>
    public static int Count(string text)
    {
        var count = 0;
        var inWord = false;
        foreach (var rune in text.EnumerateRunes())
        {
            if (Rune.IsWhiteSpace(rune))
            {
                inWord = false;
            }
            else if (!inWord && Rune.IsLetterOrDigit(rune))
            {
                inWord = true;
                count++;
            }
        }
        return count;
    }
}
