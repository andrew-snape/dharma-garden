import SwiftUI
import WeedsArt
import WeedsCore

/// Settings sheet, opened from the gear button in the garden header. A normal form, on the garden's own backdrop.
struct SettingsView: View {
    @ObservedObject var store: GardenStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var location: LocationService
    @ObservedObject var reminders: ReminderService
    let palette: ScenePalette
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Town] = []
    @State private var searching = false
    @State private var searchMessage: String?
    @State private var reminderNote: String?
    @State private var bedNote: String?

    var body: some View {
        GardenSheetFrame(title: "Settings", palette: palette, onDone: { dismiss() }) { style in
            Form {
                Section("Location") {
                    Toggle("Use my location", isOn: $settings.useDeviceLocation)
                    LabeledContent("Current place") {
                        Text(settings.activePlace.displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    if settings.useDeviceLocation && location.isDenied {
                        Text("Location is off for Dharma Garden. To change it, open System Settings > Privacy & Security > Location Services.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Search for a town", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { search() }
                        Button("Search") { search() }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                    }
                    if searching {
                        ProgressView().controlSize(.small)
                    }
                    if let searchMessage {
                        Text(searchMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.self) { town in
                        Button {
                            choose(town)
                        } label: {
                            Text(town.displayName)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Reset to Mount Duneed") {
                        settings.manualTown = .mountDuneed
                        settings.useDeviceLocation = false
                        results = []
                        searchMessage = nil
                    }
                }

                Section {
                    Picker("Bed style", selection: bedStyleBinding) {
                        ForEach(BedStyle.allCases, id: \.self) { style in
                            BedStyleRow(style: style).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if let bedNote {
                        Text(bedNote).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Garden bed")
                }

                Section("View") {
                    Picker("Scene view", selection: $settings.sceneStyle) {
                        ForEach(SceneStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Picker("Garden theme", selection: $settings.sceneTheme) {
                        ForEach(SceneTheme.allCases, id: \.self) { theme in
                            ThemeRow(theme: theme, bed: store.garden.plot.style, selected: theme == settings.sceneTheme).tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Reminder") {
                    Toggle("Daily reminder", isOn: reminderBinding)
                    if settings.reminderEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    if let reminderNote {
                        Text(reminderNote).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Music") {
                    Toggle("Garden music", isOn: $settings.musicEnabled)
                    LabeledContent("Volume") {
                        Slider(value: $settings.musicVolume, in: 0...1)
                            .frame(width: 200)
                            .disabled(!settings.musicEnabled)
                    }
                    Text("Soft koto and flute, made live on this Mac. It fades in gently and pauses when Dharma Garden is in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sound effects") {
                    Toggle("Tool sounds", isOn: $settings.soundEffectsEnabled)
                    Text("Soft sounds for watering, forking, picking and spotting visitors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Ambient sounds", isOn: $settings.ambientEnabled)
                    Text("Birdsong by day, crickets on warm nights, and rain when it rains where you are.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Motion") {
                    Toggle("Gentle camera drift", isOn: $settings.gentleDrift)
                    Text("A slow, subtle sway of the view. Reduce Motion in System Settings also stops it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Dharma Garden", value: Self.versionText)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .panel(style)
        }
        .frame(width: 500, height: 680)
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    // MARK: Town search

    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        searchMessage = nil
        Task {
            do {
                let found = try await Geocoding.search(q)
                results = found
                searchMessage = found.isEmpty ? "No towns found for \"\(q)\"." : nil
            } catch {
                results = []
                searchMessage = "Couldn't search right now. Check your connection and try again."
            }
            searching = false
        }
    }

    /// Picking a town means the user wants that town, so "Use my location" turns off.
    private func choose(_ town: Town) {
        settings.manualTown = town
        settings.useDeviceLocation = false
        results = []
        query = ""
        searchMessage = nil
    }

    // MARK: Garden bed

    /// Switching the bed can move plants or return their seeds, so the change is reported after it happens.
    private var bedStyleBinding: Binding<BedStyle> {
        Binding(
            get: { store.garden.plot.style },
            set: { style in
                guard style != store.garden.plot.style else { return }
                var note: String?
                store.apply { note = Self.bedNote(for: GardenEngine.setBedStyle(style, in: &$0)) }
                bedNote = note
            })
    }

    /// "3 plants moved, 1 seed packet returned", or nil when nothing moved.
    private static func bedNote(for change: GardenEngine.BedStyleChange) -> String? {
        var parts: [String] = []
        if change.plantsMoved > 0 {
            parts.append("\(change.plantsMoved) \(change.plantsMoved == 1 ? "plant" : "plants") moved")
        }
        if change.seedsReturned > 0 {
            parts.append("\(change.seedsReturned) seed \(change.seedsReturned == 1 ? "packet" : "packets") returned")
        }
        if change.weedsRemoved > 0 {
            parts.append("\(change.weedsRemoved) \(change.weedsRemoved == 1 ? "weed" : "weeds") cleared")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Reminder

    /// Turning the reminder on asks for notification permission first; it stays off if the user says no.
    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { settings.reminderEnabled },
            set: { on in
                guard on else {
                    settings.reminderEnabled = false
                    reminderNote = nil
                    return
                }
                Task {
                    let granted = await reminders.requestPermission()
                    settings.reminderEnabled = granted
                    reminderNote = granted ? nil
                        : "Notifications for Dharma Garden are off. Turn them on in System Settings, under Notifications."
                }
            })
    }

    /// The reminder time as a Date for the picker; only hour and minute are stored.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.reminderMinutes / 60,
                                      minute: settings.reminderMinutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.reminderMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            })
    }
}

/// One garden theme in the picker: a still preview of its scene, then its name and a short blurb. The selected row
/// gets an accent ring on the preview (plus the picker's own radio mark), and the whole row reads as the theme's name.
private struct ThemeRow: View {
    let theme: SceneTheme
    let bed: BedStyle
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ThemePreviewImage(theme: theme, bed: bed, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                Text(theme.blurb).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(theme.displayName)
        .accessibilityHint(theme.blurb)
    }
}

/// One bed style in the picker: a swatch, then its name and a short blurb.
private struct BedStyleRow: View {
    let style: BedStyle

    var body: some View {
        HStack(spacing: 12) {
            BedSwatch(style: style)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.displayName)
                Text(style.blurb).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A flat, small drawing of a bed's plantable regions, on lawn green. The ground square is fitted to the swatch height.
private struct BedSwatch: View {
    let style: BedStyle

    private static let lawn = Color(red: 0.42, green: 0.66, blue: 0.33)
    private static let soil = Color(red: 0.42, green: 0.29, blue: 0.18)
    private static let wood = Color(red: 0.62, green: 0.44, blue: 0.24)

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 4
            let side = min(size.width, size.height) - 2 * inset
            let origin = CGPoint(x: (size.width - side) / 2, y: inset)
            let plank = CGFloat(PlotShape.plankThickness) * side

            for region in PlotShape(style: style).regions {
                let rect = CGRect(x: origin.x + (region.centre.x - region.halfWidth) * side,
                                  y: origin.y + (region.centre.y - region.halfHeight) * side,
                                  width: 2 * region.halfWidth * side,
                                  height: 2 * region.halfHeight * side)
                let path: Path
                switch region.shape {
                case .wobblyOval, .ellipse, .mound:
                    path = Path(ellipseIn: rect)
                case .roundedRect:
                    // A planter's soil is drawn square (only the plantable ground is rounded, to keep seeds off the posts).
                    path = Path(roundedRect: rect, cornerRadius: style == .plantersBoxes ? 0 : CGFloat(region.cornerRadius) * side)
                }
                context.fill(path, with: .color(Self.soil))

                // Planter boxes: the timber is the region's outline grown by one plank thickness.
                if style == .plantersBoxes {
                    let frame = rect.insetBy(dx: -plank, dy: -plank)
                    context.stroke(Path(frame), with: .color(Self.wood), lineWidth: 1.5)
                }
            }
        }
        .frame(width: 64, height: 44)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.lawn))
        .accessibilityHidden(true)
    }
}
