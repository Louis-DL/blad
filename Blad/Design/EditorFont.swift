import AppKit

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
    static func font(id: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
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
            let manager = NSFontManager.shared
            let traits: NSFontTraitMask = weight.rawValue >= NSFont.Weight.semibold.rawValue ? .boldFontMask : []
            return manager.font(withFamily: id, traits: traits, weight: 5, size: size)
                ?? manager.font(withFamily: id, traits: [], weight: 5, size: size)
                ?? systemFont(size: size, weight: weight, design: .serif)
        }
    }

    private static func systemFont(size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

extension NSFont {
    func adding(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
