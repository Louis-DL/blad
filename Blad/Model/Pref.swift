import Foundation

/// UserDefaults keys for everything the user can change in Instellingen.
enum Pref {
    static let theme = "theme"
    static let paperGrain = "paperGrain"
    static let font = "font"
    static let fontSize = "fontSize"
    static let lineWidth = "lineWidth"
    static let showTabs = "showTabs"
    static let showSidebar = "showSidebar"
    static let showWordCount = "showWordCount"
    static let dimParagraphs = "focusDimParagraphs"
    static let typewriter = "focusTypewriter"
    static let sortOrder = "sortOrder"

    static let defaultFontSize = 17.0
    static let defaultLineWidth = 680.0
}
