import SwiftUI
import AppKit

enum ThemeID: String, CaseIterable, Identifiable {
    case paper, light, night, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: "Papier"
        case .light: "Licht"
        case .night: "Nacht"
        case .system: "Automatisch"
        }
    }

    /// The window appearance this theme asks for; `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .paper, .light: .light
        case .night: .dark
        case .system: nil
        }
    }
}

struct Theme: Equatable {
    let background: NSColor
    let text: NSColor
    /// Markdown syntax and other quiet details.
    let secondary: NSColor
    let accent: NSColor
    let codeBackground: NSColor
    let selection: NSColor
    let isDark: Bool
    let hasGrain: Bool

    static let paper = Theme(
        background: NSColor(hex: 0xF4EFE5),
        text: NSColor(hex: 0x2F2A23),
        secondary: NSColor(hex: 0xA69D8E),
        accent: NSColor(hex: 0xB4532A),
        codeBackground: NSColor(hex: 0x6B5A3E, alpha: 0.075),
        selection: NSColor(hex: 0xB4532A, alpha: 0.17),
        isDark: false,
        hasGrain: true
    )

    static let light = Theme(
        background: NSColor(hex: 0xFBFBFA),
        text: NSColor(hex: 0x1D1D1F),
        secondary: NSColor(hex: 0xA1A1A6),
        accent: NSColor(hex: 0x3569DE),
        codeBackground: NSColor(hex: 0x1D1D1F, alpha: 0.05),
        selection: NSColor(hex: 0x3569DE, alpha: 0.16),
        isDark: false,
        hasGrain: false
    )

    static let night = Theme(
        background: NSColor(hex: 0x1B1A19),
        text: NSColor(hex: 0xE5E1D8),
        secondary: NSColor(hex: 0x6F6A62),
        accent: NSColor(hex: 0xE39A5B),
        codeBackground: NSColor(hex: 0xFFFFFF, alpha: 0.06),
        selection: NSColor(hex: 0xE39A5B, alpha: 0.24),
        isDark: true,
        hasGrain: false
    )

    static func resolve(_ id: ThemeID, scheme: ColorScheme) -> Theme {
        switch id {
        case .paper: .paper
        case .light: .light
        case .night: .night
        case .system: scheme == .dark ? .night : .paper
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The page colour, with a very fine grain for the paper theme.
struct PaperBackground: View {
    let theme: Theme
    let showsGrain: Bool

    var body: some View {
        Color(nsColor: theme.background)
            .overlay {
                if showsGrain && theme.hasGrain {
                    Image(nsImage: PaperTexture.tile)
                        .resizable(resizingMode: .tile)
                        .allowsHitTesting(false)
                }
            }
    }
}

enum PaperTexture {
    /// A seamless tile with soft, cloudy changes in tone and a few faint fibres.
    /// Per-pixel specks read as static on screen; paper is uneven at a larger scale.
    static let tile: NSImage = {
        // 1024 px drawn at 2× is a 512 pt tile: large enough that the repeat doesn't read as a pattern.
        let size = 1024
        // Tone changes are low-frequency, so they are computed small and scaled up smoothly.
        let cloudSize = 256
        guard let clouds = bitmap(cloudSize), let cloudData = clouds.bitmapData,
              let rep = bitmap(size) else { return NSImage() }

        var random = SplitMix64(state: 0x5EED_B1AD)

        // Value noise on wrapping lattices, so the tile repeats without seams.
        let octaves: [(cells: Int, weight: Double)] = [(5, 0.42), (12, 0.36), (28, 0.22)]
        let lattices = octaves.map { octave in
            (0..<(octave.cells * octave.cells)).map { _ in random.nextUnit() * 2 - 1 }
        }

        for y in 0..<cloudSize {
            for x in 0..<cloudSize {
                var value = 0.0
                for (index, octave) in octaves.enumerated() {
                    value += octave.weight * sample(lattices[index], cells: octave.cells, x: Double(x) / Double(cloudSize), y: Double(y) / Double(cloudSize))
                }
                let a = Double(UInt8(min(1, abs(value) * 1.6) * 0.09 * 255))
                let offset = (y * cloudSize + x) * 4
                // Premultiplied: lighter patches are white, denser patches a warm brown.
                let tint: (Double, Double, Double) = value > 0 ? (1, 1, 1) : (0.55, 0.42, 0.25)
                cloudData[offset] = UInt8(a * tint.0)
                cloudData[offset + 1] = UInt8(a * tint.1)
                cloudData[offset + 2] = UInt8(a * tint.2)
                cloudData[offset + 3] = UInt8(a)
            }
        }

        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            clouds.draw(in: NSRect(x: 0, y: 0, width: size, height: size))

            for _ in 0..<520 {
                let start = CGPoint(x: random.nextUnit() * Double(size), y: random.nextUnit() * Double(size))
                let angle = random.nextUnit() * .pi * 2
                let length = 14 + random.nextUnit() * 44
                let bend = (random.nextUnit() - 0.5) * 12
                let end = CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
                let control = CGPoint(x: (start.x + end.x) / 2 - sin(angle) * bend, y: (start.y + end.y) / 2 + cos(angle) * bend)
                let width = 1.0 + random.nextUnit() * 0.9
                let color = random.nextUnit() < 0.35
                    ? NSColor(white: 1, alpha: 0.35)
                    : NSColor(srgbRed: 0.45, green: 0.36, blue: 0.24, alpha: 0.10 + random.nextUnit() * 0.08)
                color.setStroke()
                // Draw each fibre at the neighbouring tile offsets too, so fibres cross edges seamlessly.
                for dx in [-size, 0, size] {
                    for dy in [-size, 0, size] {
                        let shift = { (point: CGPoint) in CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy)) }
                        let path = NSBezierPath()
                        path.move(to: shift(start))
                        path.curve(to: shift(end), controlPoint1: shift(control), controlPoint2: shift(control))
                        path.lineWidth = width
                        path.lineCapStyle = .round
                        path.stroke()
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        rep.size = NSSize(width: size / 2, height: size / 2)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }()

    private static func sample(_ lattice: [Double], cells: Int, x: Double, y: Double) -> Double {
        let fx = x * Double(cells)
        let fy = y * Double(cells)
        let x0 = Int(fx) % cells, y0 = Int(fy) % cells
        let x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells
        let tx = smooth(fx - fx.rounded(.down))
        let ty = smooth(fy - fy.rounded(.down))
        let top = lattice[y0 * cells + x0] + (lattice[y0 * cells + x1] - lattice[y0 * cells + x0]) * tx
        let bottom = lattice[y1 * cells + x0] + (lattice[y1 * cells + x1] - lattice[y1 * cells + x0]) * tx
        return top + (bottom - top) * ty
    }

    private static func smooth(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    private static func bitmap(_ pixels: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
    }
}

private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}
