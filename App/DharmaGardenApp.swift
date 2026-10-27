import SwiftUI

@main
struct DharmaGardenApp: App {
    // The app body must not observe the store, weather or settings objects: a change published while SwiftUI
    // builds the scene list re-runs this body, which loops until the stack overflows. The menu bar toggle is read
    // straight from UserDefaults (AppSettings writes the same key), and the views take the shared objects themselves.
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        Window("Dharma Garden", id: GardenWindow.id) { GardenView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1000, height: 760)
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarGarden(store: GardenShared.shared.store, settings: GardenShared.shared.settings,
                          weather: GardenShared.shared.weather)
        } label: {
            MenuBarLeaf()
        }
        .menuBarExtraStyle(.window)
    }
}
