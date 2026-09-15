import AppKit

/// Draws the install window's background: Blad's paper, a title, and an arrow from the app to Programma's.
/// Compiled together with Blad's Theme.swift and EditorFont.swift by make-dmg.sh.
@main
enum DMGBackground {
    /// The Finder window's content size, in points. make-dmg.sh places the icons to match.
    static let size = NSSize(width: 660, height: 420)
    static let appIconCenter = NSPoint(x: 180, y: 230)
    static let applicationsIconCenter = NSPoint(x: 480, y: 230)

    static func main() {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for scale in [1, 2] {
            let name = scale == 1 ? "background.png" : "background@2x.png"
            try! render(scale: scale).write(to: output.appendingPathComponent(name))
        }
    }

    private static func render(scale: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])!
    }

    private static func draw() {
        let theme = Theme.paper
        let bounds = NSRect(origin: .zero, size: size)

        // Paper, lit a little brighter in the middle.
        theme.background.setFill()
        bounds.fill()
        NSColor(patternImage: PaperTexture.tile).setFill()
        bounds.fill(using: .sourceOver)
        NSGradient(starting: NSColor(white: 1, alpha: 0.4), ending: NSColor(white: 1, alpha: 0))?
            .draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0.15))

        // Title. Finder's coordinates run top-down; AppKit's bottom-up, hence `size.height - y`.
        drawCentered("Blad", font: EditorFont.font(id: "system-serif", size: 46, weight: .semibold), color: theme.text, top: 44)
        drawCentered(
            "Een rustige plek voor notities en README's.",
            font: EditorFont.font(id: "system-serif", size: 15),
            color: theme.secondary,
            top: 104
        )

        // A hand-drawn arrow between the two icons.
        let y = size.height - appIconCenter.y + 6
        let start = NSPoint(x: appIconCenter.x + 78, y: y)
        let end = NSPoint(x: applicationsIconCenter.x - 80, y: y)
        let control = NSPoint(x: (start.x + end.x) / 2, y: y + 34)
        let arrow = NSBezierPath()
        arrow.move(to: start)
        arrow.curve(to: end, controlPoint1: control, controlPoint2: control)
        arrow.lineWidth = 2.5
        arrow.lineCapStyle = .round
        theme.accent.setStroke()
        arrow.stroke()

        let angle = atan2(end.y - control.y, end.x - control.x)
        let head = NSBezierPath()
        for side in [-1.0, 1.0] {
            head.move(to: end)
            head.line(to: NSPoint(
                x: end.x - 12 * cos(angle + side * 0.5),
                y: end.y - 12 * sin(angle + side * 0.5)
            ))
        }
        head.lineWidth = 2.5
        head.lineCapStyle = .round
        head.stroke()

        drawCentered(
            "Sleep naar Programma's",
            font: .systemFont(ofSize: 12.5, weight: .medium),
            color: theme.accent,
            top: appIconCenter.y - 56
        )

        // A quiet first-launch tip at the bottom.
        theme.secondary.withAlphaComponent(0.25).setFill()
        NSRect(x: 60, y: 54, width: size.width - 120, height: 0.5).fill()
        drawCentered(
            "Eerste keer openen? Ga naar Systeeminstellingen › Privacy en beveiliging en sta Blad daar toe.",
            font: .systemFont(ofSize: 10.5),
            color: theme.secondary,
            top: size.height - 40
        )
    }

    /// Draws a line of text centred horizontally, `top` points below the top edge.
    private static func drawCentered(_ text: String, font: NSFont, color: NSColor, top: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (size.width - textSize.width) / 2, y: size.height - top - textSize.height)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
