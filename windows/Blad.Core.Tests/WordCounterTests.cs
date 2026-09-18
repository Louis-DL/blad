using Blad.Core;

namespace Blad.Core.Tests;

public class WordCounterTests
{
    [Theory]
    [InlineData("", 0)]
    [InlineData("# Welkom in Blad", 3)]
    [InlineData("- een\n- twee", 2)]
    [InlineData("Ideeën, café's en 2026!", 4)]
    public void CountsWordsButNotMarkdownSymbols(string text, int expected)
    {
        Assert.Equal(expected, WordCounter.Count(text));
    }
}
