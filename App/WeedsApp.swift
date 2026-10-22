import SwiftUI

@main
struct WeedsApp: App {
    var body: some Scene {
        WindowGroup { GardenView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1000, height: 760)
    }
}
