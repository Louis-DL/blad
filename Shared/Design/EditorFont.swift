import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum EditorFont {
    static let defaultID = "system-serif"

    static let presets: [(id: String, name: String)] = [
        ("system-serif", "New York"),
        ("system", "SF Pro"),
        ("system-rounded", "SF Pro Rounded"),
        ("system-mono", "SF Mono"),
    ]

    static func name(for id: String) -> String {
        presets.first { $0.id == id }?.name ?? id
    }

    /// `id` is either one of the presets or the family name of an installed font.
    static func font(id: String, size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        switch id {
        case "system":
            return .systemFont(ofSize: size, weight: weight)
        case "system-serif":
            return systemFont(size: size, weight: weight, design: .serif)
        case "system-rounded":
            return systemFont(size: size, weight: weight, design: .rounded)
        case "system-mono":
            return .monospacedSystemFont(ofSize: size, weight: weight)
        default:
            return installedFont(family: id, size: size, weight: weight)
                ?? systemFont(size: size, weight: weight, design: .serif)
        }
    }

    private static func systemFont(size: CGFloat, weight: PlatformFont.Weight, design: PlatformFontDescriptor.SystemDesign) -> PlatformFont {
        let base = PlatformFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        #if os(macOS)
        return NSFont(descriptor: descriptor, size: size) ?? base
        #else
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }

    #if os(macOS)
    static var installedFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
    }

    private static func installedFont(family: String, size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let manager = NSFontManager.shared
        let traits: NSFontTraitMask = weight.rawValue >= NSFont.Weight.semibold.rawValue ? .boldFontMask : []
        return manager.font(withFamily: family, traits: traits, weight: 5, size: size)
            ?? manager.font(withFamily: family, traits: [], weight: 5, size: size)
    }
    #else
    static var installedFamilies: [String] {
        UIFont.familyNames.sorted()
    }

    private static func installedFont(family: String, size: CGFloat, weight: UIFont.Weight) -> UIFont? {
        guard UIFont.familyNames.contains(family) else { return nil }
        let base = UIFontDescriptor(fontAttributes: [.family: family])
        let isBold = weight.rawValue >= UIFont.Weight.semibold.rawValue
        let descriptor = isBold ? (base.withSymbolicTraits(.traitBold) ?? base) : base
        return UIFont(descriptor: descriptor, size: size)
    }
    #endif
}

extension PlatformFont {
    /// The same font with bold and/or italic added, where the family has them.
    func adding(bold: Bool = false, italic: Bool = false) -> PlatformFont {
        #if os(macOS)
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
        #else
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #endif
    }
}
