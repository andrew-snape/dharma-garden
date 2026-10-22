import Foundation
import WeedsArt
import WeedsCore

/// The user's choices, saved in UserDefaults. The garden, the weather and the reminder all read from here.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let useDeviceLocation = "useDeviceLocation"
        static let manualTown = "manualTown"
        static let devicePlace = "devicePlace"
        static let reminderEnabled = "reminderEnabled"
        static let reminderMinutes = "reminderMinutes"
        static let gentleDrift = "gentleDrift"
        static let sceneStyle = "sceneStyle"
        static let sceneTheme = "sceneTheme"
        static let hasAskedLocation = "hasAskedLocation"
        static let musicEnabled = "musicEnabled"
        static let musicVolume = "musicVolume"
        static let soundEffectsEnabled = "soundEffectsEnabled"
        static let ambientEnabled = "ambientEnabled"
        static let choreReadyAt = "choreReadyAt"
        static let lastSummaryDay = "lastSummaryDay"
    }

    /// Music volume when the user has not chosen one.
    static let defaultMusicVolume = 0.6

    /// 09:00, in minutes after midnight.
    static let defaultReminderMinutes = 9 * 60

    private let defaults: UserDefaults

    /// True when the garden should use the Mac's location instead of the town the user picked.
    @Published var useDeviceLocation: Bool {
        didSet { defaults.set(useDeviceLocation, forKey: Key.useDeviceLocation) }
    }
    /// The town picked by hand (Mount Duneed until changed).
    @Published var manualTown: Town {
        didSet { store(manualTown, Key.manualTown) }
    }
    /// The last place found from the Mac's location, kept so the garden still has a place when location is unavailable.
    @Published var devicePlace: Town? {
        didSet { store(devicePlace, Key.devicePlace) }
    }
    @Published var reminderEnabled: Bool {
        didSet { defaults.set(reminderEnabled, forKey: Key.reminderEnabled) }
    }
    /// Reminder time in minutes after midnight, 0..<1440.
    @Published var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: Key.reminderMinutes) }
    }
    /// Turns the slow camera drift on or off.
    @Published var gentleDrift: Bool {
        didSet { defaults.set(gentleDrift, forKey: Key.gentleDrift) }
    }

    /// Which framing the garden scene uses. First person until the user picks the backyard view.
    @Published var sceneStyle: SceneStyle {
        didSet { defaults.set(sceneStyle.rawValue, forKey: Key.sceneStyle) }
    }
    /// The garden's surroundings, the look and (later) the music. The farm until the user picks another.
    @Published var sceneTheme: SceneTheme {
        didSet { defaults.set(sceneTheme.rawValue, forKey: Key.sceneTheme) }
    }
    /// True once the first-launch location question has been answered (either way). It is never asked again;
    /// the "Use my location" toggle in Settings is the way to change it.
    @Published var hasAskedLocation: Bool {
        didSet { defaults.set(hasAskedLocation, forKey: Key.hasAskedLocation) }
    }

    /// Plays the garden's generative music. Off is the mute: the header speaker button toggles this.
    @Published var musicEnabled: Bool {
        didSet { defaults.set(musicEnabled, forKey: Key.musicEnabled) }
    }
    /// Music volume, 0...1.
    @Published var musicVolume: Double {
        didSet {
            let clamped = min(max(musicVolume, 0), 1)
            if clamped != musicVolume { musicVolume = clamped; return }
            defaults.set(musicVolume, forKey: Key.musicVolume)
        }
    }

    /// Plays the short sounds of watering, forking, picking and so on.
    @Published var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: Key.soundEffectsEnabled) }
    }
    /// Plays the ambience: birdsong by day, crickets by night and rain with the weather.
    @Published var ambientEnabled: Bool {
        didSet { defaults.set(ambientEnabled, forKey: Key.ambientEnabled) }
    }
    /// When each side chore (see `SideChore`) can next be done, keyed by the chore's raw value. Kept across launches.
    var choreReadyAt: [String: Date] {
        get {
            guard let data = defaults.data(forKey: Key.choreReadyAt),
                  let saved = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.choreReadyAt) }
    }
    /// The calendar day (yyyy-MM-dd) the daily summary was last shown, so it appears once a day.
    var lastSummaryDay: String? {
        get { defaults.string(forKey: Key.lastSummaryDay) }
        set { defaults.set(newValue, forKey: Key.lastSummaryDay) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        useDeviceLocation = defaults.object(forKey: Key.useDeviceLocation) as? Bool ?? false
        manualTown = Self.loadTown(defaults, Key.manualTown) ?? .mountDuneed
        devicePlace = Self.loadTown(defaults, Key.devicePlace)
        reminderEnabled = defaults.object(forKey: Key.reminderEnabled) as? Bool ?? false
        let minutes = defaults.object(forKey: Key.reminderMinutes) as? Int ?? Self.defaultReminderMinutes
        reminderMinutes = min(max(minutes, 0), 1439)
        gentleDrift = defaults.object(forKey: Key.gentleDrift) as? Bool ?? true
        sceneStyle = (defaults.string(forKey: Key.sceneStyle)).flatMap(SceneStyle.init(rawValue:)) ?? .firstPerson
        sceneTheme = (defaults.string(forKey: Key.sceneTheme)).flatMap(SceneTheme.init(rawValue:)) ?? .farm
        hasAskedLocation = defaults.object(forKey: Key.hasAskedLocation) as? Bool ?? false
        musicEnabled = defaults.object(forKey: Key.musicEnabled) as? Bool ?? true
        let volume = defaults.object(forKey: Key.musicVolume) as? Double ?? Self.defaultMusicVolume
        musicVolume = min(max(volume, 0), 1)
        soundEffectsEnabled = defaults.object(forKey: Key.soundEffectsEnabled) as? Bool ?? true
        ambientEnabled = defaults.object(forKey: Key.ambientEnabled) as? Bool ?? true
    }

    /// The place the weather and the season are worked out for.
    var activePlace: Town {
        if useDeviceLocation, let devicePlace { return devicePlace }
        return manualTown
    }

    private func store(_ town: Town?, _ key: String) {
        guard let town, let data = try? JSONEncoder().encode(town) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func loadTown(_ defaults: UserDefaults, _ key: String) -> Town? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Town.self, from: data)
    }
}
