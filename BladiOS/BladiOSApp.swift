import SwiftUI

@main
struct BladiOSApp: App {
    @State private var library = Library.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.refreshAll()
            case .inactive, .background:
                library.saveAll()
            @unknown default:
                break
            }
        }
    }
}
