import Foundation
import WeedsCore

/// Live weather for the active place. Each place keeps its own last good report, so the garden shows
/// that report when the network is down or the location is refused. It never invents weather.
@MainActor
final class WeatherService: ObservableObject {
    /// The report for `place`, or nil while nothing is known for it.
    @Published private(set) var report: WeatherReport?
    /// True when `report` is from an earlier fetch (shown with its age).
    @Published private(set) var isStale = false
    /// True when the last fetch for `place` failed.
    @Published private(set) var lastFetchFailed = false
    /// True while a fetch is in flight.
    @Published private(set) var isFetching = false
    /// The place the report is for. Nil until the first refresh.
    @Published private(set) var place: Town?

    /// How long a report is trusted before the open app fetches a fresh one.
    static let refreshInterval: TimeInterval = 30 * 60

    private let client = OpenMeteoClient()
    /// When the last fetch started, so an open window refreshes now and then without retrying every minute offline.
    private var lastAttempt: Date?
    /// Last good report for each place, keyed by its coordinates.
    private var cache: [String: WeatherReport]
    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("weather-cache.json")
    }()

    init() {
        // An older cache (a single report, not a dictionary) fails to decode and is simply ignored.
        if let d = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: WeatherReport].self, from: d) {
            cache = saved
        } else {
            cache = [:]
        }
    }

    /// Shows what is known for `place` straight away, then fetches a fresh report. When the place has
    /// changed, the new place's cached report (if any) replaces the old one.
    func refresh(for place: Town) async {
        if self.place != place {
            self.place = place
            report = cache[Self.key(place)]
            isStale = report != nil
        }
        lastFetchFailed = false
        lastAttempt = Date()
        isFetching = true
        defer { isFetching = false }
        do {
            let fresh = try await client.fetch(latitude: place.latitude, longitude: place.longitude)
            cache[Self.key(place)] = fresh
            save()
            // The user may have moved to another place while this was loading.
            guard self.place == place else { return }
            report = fresh
            isStale = false
        } catch {
            guard self.place == place else { return }
            lastFetchFailed = true
            isStale = report != nil
        }
    }

    /// True when `place` differs from the report's place, or the last fetch started `refreshInterval` ago or more.
    func needsRefresh(for place: Town, at now: Date = Date()) -> Bool {
        guard self.place == place, let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Self.refreshInterval
    }

    /// Latitude of the place (Mount Duneed until the first refresh), for the season.
    var season: Season {
        SeasonProvider.season(on: Date(), latitude: (place ?? .mountDuneed).latitude)
    }

    func palette(at now: Date = Date(), theme: GardenTheme = .farm) -> ScenePalette? {
        guard let r = report else { return nil }
        let here = place ?? .mountDuneed
        let times = r.sunTimes(at: now)
        let phase = SunPhaseResolver.phase(at: now, sunrise: times.sunrise, sunset: times.sunset)
        let sun = SunPosition.light(at: now, sunrise: times.sunrise, sunset: times.sunset, latitude: here.latitude,
                                    cloudCover: r.current.cloudCover)
        return ScenePalette.resolve(season: season, phase: phase, condition: r.current.condition,
                                    temperatureC: r.current.temperatureC, cloudCover: r.current.cloudCover,
                                    sun: sun, theme: theme)
    }

    /// The music's mood: time of day from the report's sunrise and sunset, the weather, the season and the garden
    /// theme. A plain clear day while no report is known.
    func mood(at now: Date = Date(), theme: GardenTheme = .farm) -> GardenMood {
        guard let r = report else { return .plainDay(season: season, theme: theme) }
        let times = r.sunTimes(at: now)
        let phase = SunPhaseResolver.phase(at: now, sunrise: times.sunrise, sunset: times.sunset)
        return GardenMood(phase: phase, condition: r.current.condition, season: season, theme: theme)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(cache) { try? d.write(to: cacheURL, options: .atomic) }
    }

    private static func key(_ place: Town) -> String {
        String(format: "%.4f,%.4f", place.latitude, place.longitude)
    }
}
