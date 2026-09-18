using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Blad;

/// <summary>
/// The paper under the text: soft, cloudy changes in tone and faint fibres. The same recipe as the
/// Mac and iPhone apps, drawn pixel by pixel because WinUI has no drawing API for bitmaps.
/// </summary>
public static class PaperTexture
{
    private const int Width = 1600;
    private const int Height = 1200;
    private static Task<byte[]>? pixels;

    /// <summary>Drawn once, off the UI thread; shown with Stretch.UniformToFill behind the page.</summary>
    public static async Task<ImageSource> CreateAsync()
    {
        pixels ??= Task.Run(Draw);
        var data = await pixels;
        var bitmap = new WriteableBitmap(Width, Height);
        using (var stream = bitmap.PixelBuffer.AsStream())
        {
            await stream.WriteAsync(data);
        }
        bitmap.Invalidate();
        return bitmap;
    }

    /// <summary>Premultiplied BGRA pixels.</summary>
    private static byte[] Draw()
    {
        var data = new byte[Width * Height * 4];
        var random = new SplitMix64(0x5EED_B1AD);

        // Value noise at three scales; cell sizes in pixels match the Mac's texture.
        var octaves = new (int Size, double Weight)[] { (102, 0.42), (43, 0.36), (18, 0.22) };
        var lattices = octaves.Select(octave =>
        {
            var columns = Width / octave.Size + 2;
            var rows = Height / octave.Size + 2;
            var lattice = new double[columns * rows];
            for (var i = 0; i < lattice.Length; i++) lattice[i] = random.NextUnit() * 2 - 1;
            return (octave.Size, octave.Weight, Columns: columns, Lattice: lattice);
        }).ToArray();

        for (var y = 0; y < Height; y++)
        {
            for (var x = 0; x < Width; x++)
            {
                var value = 0.0;
                foreach (var (size, weight, columns, lattice) in lattices)
                {
                    value += weight * Sample(lattice, columns, (double)x / size, (double)y / size);
                }
                var alpha = Math.Min(1, Math.Abs(value) * 1.6) * 0.09;
                // Lighter patches are white, denser patches a warm brown.
                var (r, g, b) = value > 0 ? (1.0, 1.0, 1.0) : (0.55, 0.42, 0.25);
                var offset = (y * Width + x) * 4;
                data[offset] = (byte)(b * alpha * 255);
                data[offset + 1] = (byte)(g * alpha * 255);
                data[offset + 2] = (byte)(r * alpha * 255);
                data[offset + 3] = (byte)(alpha * 255);
            }
        }

        var fibres = Width * Height / 520;
        for (var i = 0; i < fibres; i++)
        {
            var startX = random.NextUnit() * Width;
            var startY = random.NextUnit() * Height;
            var angle = random.NextUnit() * Math.PI * 2;
            var length = 7 + random.NextUnit() * 22;
            var bend = (random.NextUnit() - 0.5) * 6;
            var endX = startX + Math.Cos(angle) * length;
            var endY = startY + Math.Sin(angle) * length;
            var controlX = (startX + endX) / 2 - Math.Sin(angle) * bend;
            var controlY = (startY + endY) / 2 + Math.Cos(angle) * bend;
            var light = random.NextUnit() < 0.35;
            var alpha = light ? 0.35 : 0.10 + random.NextUnit() * 0.08;
            var (r, g, b) = light ? (1.0, 1.0, 1.0) : (0.45, 0.36, 0.24);

            // Stamp soft dots along the curve.
            var steps = (int)(length * 2);
            for (var step = 0; step <= steps; step++)
            {
                var t = (double)step / steps;
                var px = (1 - t) * (1 - t) * startX + 2 * (1 - t) * t * controlX + t * t * endX;
                var py = (1 - t) * (1 - t) * startY + 2 * (1 - t) * t * controlY + t * t * endY;
                Stamp(data, px, py, alpha * 0.45, r, g, b);
            }
        }
        return data;
    }

    private static void Stamp(byte[] data, double px, double py, double alpha, double r, double g, double b)
    {
        var x0 = (int)Math.Floor(px);
        var y0 = (int)Math.Floor(py);
        for (var y = y0; y <= y0 + 1; y++)
        {
            for (var x = x0; x <= x0 + 1; x++)
            {
                if (x < 0 || y < 0 || x >= Width || y >= Height) continue;
                var coverage = (1 - Math.Abs(px - x)) * (1 - Math.Abs(py - y));
                if (coverage <= 0) continue;
                var a = alpha * coverage;
                var offset = (y * Width + x) * 4;
                data[offset] = Blend(data[offset], b * a);
                data[offset + 1] = Blend(data[offset + 1], g * a);
                data[offset + 2] = Blend(data[offset + 2], r * a);
                data[offset + 3] = Blend(data[offset + 3], a);

                byte Blend(byte destination, double source) =>
                    (byte)Math.Min(255, source * 255 + destination * (1 - a));
            }
        }
    }

    private static double Sample(double[] lattice, int columns, double fx, double fy)
    {
        var x0 = (int)fx;
        var y0 = (int)fy;
        var tx = Smooth(fx - x0);
        var ty = Smooth(fy - y0);
        double At(int x, int y) => lattice[y * columns + x];
        var top = At(x0, y0) + (At(x0 + 1, y0) - At(x0, y0)) * tx;
        var bottom = At(x0, y0 + 1) + (At(x0 + 1, y0 + 1) - At(x0, y0 + 1)) * tx;
        return top + (bottom - top) * ty;
    }

    private static double Smooth(double t) => t * t * (3 - 2 * t);

    private struct SplitMix64(ulong state)
    {
        private ulong state = state;

        public double NextUnit()
        {
            state += 0x9E3779B97F4A7C15;
            var z = state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
            return ((z ^ (z >> 31)) >> 11) / (double)(1UL << 53);
        }
    }
}
