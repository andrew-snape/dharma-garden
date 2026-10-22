import Foundation
import UserNotifications
import WeedsCore

/// Schedules the one daily reminder. Permission is asked only when the user turns the reminder on.
/// The notification is a one-shot for the next occurrence of the chosen time. The app calls `reschedule`
/// when it becomes inactive or closes, when the garden or the weather changes, and when settings change,
/// so the words always reflect the garden as it will be at that time.
@MainActor
final class ReminderService: ObservableObject {
    static let requestID = "daily-garden-reminder"

    private let center = UNUserNotificationCenter.current()

    /// Asks macOS for permission to show notifications. Returns false if the user says no
    /// (or has already refused earlier, in which case macOS shows nothing).
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Requests run one at a time, in order, and a request that a newer one has replaced is skipped, so the final
    /// state always matches the latest settings (an older request can no longer re-add a reminder just turned off).
    private var tail: Task<Void, Never>?
    private var generation = 0
    /// Whether notifications were allowed at the last check, for `rescheduleBeforeQuit` (which cannot wait to ask).
    private var lastKnownAuthorized = false

    /// Replaces the pending reminder with one for the next `minutes` after midnight, or removes it when disabled.
    /// `delay` waits first and lets a newer request replace this one, for bursts of garden changes.
    func reschedule(enabled: Bool, minutes: Int, garden: Garden, weather: [WeatherSample], now: Date = Date(),
                    delay: Duration = .zero) async {
        generation += 1
        let mine = generation
        let previous = tail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, mine == self.generation else { return }
            await self.apply(enabled: enabled, minutes: minutes, garden: garden, weather: weather, now: now,
                             generation: mine)
        }
        tail = task
        await task.value
    }

    private func apply(enabled: Bool, minutes: Int, garden: Garden, weather: [WeatherSample], now: Date,
                       generation mine: Int) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard enabled else { return }

        let settings = await center.notificationSettings()
        lastKnownAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        guard lastKnownAuthorized, mine == generation else { return }
        guard let fire = Self.nextOccurrence(minutes: minutes, after: now) else { return }

        // Projecting the garden to the fire time simulates up to a day, so it runs off the main thread.
        let body = await Task.detached(priority: .utility) {
            ReminderText.message(for: garden, at: fire, weather: weather)
        }.value
        guard mine == generation else { return }
        try? await center.add(Self.request(body: body, fire: fire))
    }

    /// The last write when the app quits. The process ends as soon as the quit notification returns, so this
    /// blocks (for at most a second) until macOS has the request, instead of starting a task that never finishes.
    /// Pending async requests are superseded.
    func rescheduleBeforeQuit(enabled: Bool, minutes: Int, garden: Garden, weather: [WeatherSample],
                              now: Date = Date()) {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard enabled, lastKnownAuthorized, let fire = Self.nextOccurrence(minutes: minutes, after: now) else { return }
        let request = Self.request(body: ReminderText.message(for: garden, at: fire, weather: weather), fire: fire)
        let done = DispatchSemaphore(value: 0)
        // The completion handler runs on a background queue, so waiting here on the main thread cannot deadlock.
        center.add(request) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 1)
    }

    private static func request(body: String, fire: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Garden"
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
    }

    /// The next local time of day (minutes after midnight) strictly after `now`.
    static func nextOccurrence(minutes: Int, after now: Date, calendar: Calendar = .current) -> Date? {
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime)
    }
}
