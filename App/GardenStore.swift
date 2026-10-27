import Foundation
import DharmaGardenCore

/// Holds the garden, saves it as JSON, and catches it up with the weather.
/// (JSON file for now; the Garden type is Codable so SwiftData can replace it later.)
/// Saves from an unsupported format version (see `Garden.decodeSave`) are discarded.
@MainActor
final class GardenStore: ObservableObject {
    @Published var garden: Garden
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garden.json")
    }()

    init() {
        // Saves from an unsupported format version are discarded and the garden starts fresh.
        if let data = try? Data(contentsOf: url) {
            if let g = Garden.decodeSave(data) {
                garden = g
            } else {
                // Unreadable or from another version: keep a copy so the first save does not destroy it.
                let backup = url.deletingLastPathComponent().appendingPathComponent("garden.unreadable.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: url, to: backup)
                garden = Garden(now: Date())
            }
        } else {
            garden = Garden(now: Date())
        }
        // No catch-up here: the view catches up once the weather is known, so the time away is simulated with the
        // real past hours (the forecast carries the last week) instead of mild neutral weather.
        gameCenter.authenticate()
        gameCenter.update(with: garden)
    }

    /// Reports the goals the garden has reached to Game Center.
    private let gameCenter = GameCenterService()

    /// What changed while the player was away, set by a catch-up that covered `Tuning.awaySummaryMinHours` or more
    /// and changed something. The view shows it and clears it.
    @Published var awaySummary: AwaySummary?

    /// Garden speed (1, 2 or 4): how many times faster plants, weeds and soil move per real hour. The clock,
    /// weather and seasons stay real. Set from the settings.
    var speed: Double = 1

    /// Simulates the garden up to now with the forecast's hourly samples (missing hours use mild neutral weather).
    /// Does nothing while `now` is in the same hour as the last catch-up, since the engine steps whole hours.
    func catchUp(weather: [WeatherSample] = [], now: Date = Date()) {
        // Opening the app counts as a visit today, even when no whole hour has passed to simulate.
        apply { GardenEngine.recordOpen(in: &$0, now: now) }
        guard Self.hourIndex(now) > Self.hourIndex(garden.lastSimulatedAt) else { return }
        let before = garden
        garden = GardenEngine.advance(garden, weather: weather, to: now, speed: speed)
        let summary = GardenEngine.awaySummary(from: before, to: garden)
        if summary.hoursAway >= Tuning.awaySummaryMinHours, !summary.isEmpty { awaySummary = summary }
        gameCenter.update(with: garden)
        save()
    }

    /// Writes the garden now and cancels any pending delayed save.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        // Atomic, so a crash or power cut mid-write never leaves a half-written (and so unreadable) save.
        if let data = try? JSONEncoder().encode(garden) { try? data.write(to: url, options: .atomic) }
    }

    /// Changes the garden and saves it a moment later, so a burst of actions (sprinkling while dragging) writes
    /// once. The app calls `save` when it goes to the background or quits.
    func apply(_ change: (inout Garden) -> Void) {
        change(&garden)
        gameCenter.update(with: garden)
        scheduleSave()
    }

    private var pendingSave: Task<Void, Never>?
    private static let saveDelay: Duration = .seconds(1)

    private func scheduleSave() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    private static func hourIndex(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / 3600).rounded(.down)) }

#if DEBUG
    /// Fast-forwards the garden by whole days using mild neutral weather.
    func debugAdvance(days: Int, autoWater: Bool) {
        apply { $0 = DebugTools.advance(garden: $0, days: days, autoWater: autoWater) }
    }

    /// Scatters 20 plants across the patch, a rotation of every flower type (no coins or seeds spent).
    func debugScatter() {
        apply { $0 = DebugTools.fillWithPlants(garden: $0, count: 20) }
    }

    /// Empties the collection book (sightings only; coins and plants stay).
    func debugClearSightings() {
        apply { $0.sightings = [:] }
    }

    /// Starts a fresh garden at the real current time.
    func debugReset() {
        apply { $0 = DebugTools.reset(now: Date()) }
    }
#endif
}
