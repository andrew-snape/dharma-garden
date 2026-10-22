import SwiftUI

@main
struct WeedsApp: App {
    var body: some Scene {
        WindowGroup { GardenView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 820, height: 860)
    }
}
