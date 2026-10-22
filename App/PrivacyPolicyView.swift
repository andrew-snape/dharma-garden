import SwiftUI
import DharmaGardenArt
import DharmaGardenCore

/// The privacy policy, opened from Settings > About. The same text is in PRIVACY.md at the project root.
struct PrivacyPolicyView: View {
    let palette: ScenePalette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GardenSheetFrame(title: "Privacy Policy", palette: palette, onDone: { dismiss() }) { style in
            Form {
                Section {
                    Text("Dharma Garden does not collect, track or share your data. There are no analytics, no advertising, no tracking and no accounts. The developer runs no servers and receives nothing from the app.")
                }
                Section("What stays on your Mac") {
                    Text("Your garden, settings, reading progress and downloaded book text are saved in the app's own sandbox on your Mac. Deleting the app removes them.")
                }
                Section("Location") {
                    Text("Location is off unless you turn on \"Use my location\". When it is on, macOS gives the app your position so it can find your town. The app uses only the town name and coordinates, and sends the coordinates to Open-Meteo to get local weather. Otherwise the garden uses the town you choose, Melbourne by default.")
                }
                Section("Online services") {
                    Text("Weather and town search: Open-Meteo (open-meteo.com). Your search text, and the coordinates of your town, are sent so it can answer.")
                    Text("Reading: Project Gutenberg (gutenberg.org), when you open a book for the first time. Like any web request, the server sees your internet address.")
                    Text("Achievements: optional Game Center sign-in by Apple. Its own privacy policy applies.")
                }
                Section("Notifications") {
                    Text("Garden reminders are local notifications on your Mac. Nothing is sent anywhere.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .panel(style)
        }
        .frame(width: 500, height: 680)
    }
}
