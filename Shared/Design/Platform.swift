import SwiftUI

// The few types that differ between the Mac and iPhone/iPad apps, under one name each,
// so the shared code (themes, styling, reading mode, export) is written once.

#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
typealias PlatformImage = NSImage
#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
typealias PlatformImage = UIImage
#endif

extension Color {
    init(platform color: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: color)
        #else
        self.init(uiColor: color)
        #endif
    }
}

extension Image {
    init(platformImage image: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}

extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        #if os(macOS)
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        self.init(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// Red, green, blue and alpha in sRGB, each from 0 to 1.
    var srgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if os(macOS)
        let color = usingColorSpace(.sRGB) ?? self
        return (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
        #endif
    }
}

extension PlatformImage {
    static func load(contentsOf url: URL) -> PlatformImage? {
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        return UIImage(contentsOfFile: url.path)
        #endif
    }
}
