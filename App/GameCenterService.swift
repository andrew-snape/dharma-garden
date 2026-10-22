import AppKit
import GameKit
import WeedsCore

/// Signs the player in to Game Center and reports the garden's achievements (see `GardenAchievement`).
/// Does nothing while nobody is signed in, and reports again once they are.
@MainActor
final class GameCenterService {
    /// Goals the garden has reached, whether or not they are reported yet.
    private var earned: Set<GardenAchievement> = []
    /// Goals Game Center has accepted, or that are on their way.
    private var reported: Set<GardenAchievement> = []

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                if let viewController {
                    NSApp.keyWindow?.contentViewController?.presentAsSheet(viewController)
                } else if GKLocalPlayer.local.isAuthenticated {
                    self?.flush()
                } else if let error {
                    print("Game Center sign-in failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Takes note of the goals the garden has reached and reports any new ones.
    func update(with garden: Garden) {
        earned = GardenAchievement.earned(in: garden)
        flush()
    }

    private func flush() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let fresh = earned.subtracting(reported)
        guard !fresh.isEmpty else { return }
        reported.formUnion(fresh)
        let achievements = fresh.map { goal -> GKAchievement in
            let achievement = GKAchievement(identifier: goal.identifier)
            achievement.percentComplete = 100
            achievement.showsCompletionBanner = true
            return achievement
        }
        Task {
            do {
                try await GKAchievement.report(achievements)
            } catch {
                // Let the next update try again.
                reported.subtract(fresh)
                print("Game Center achievement report failed: \(error.localizedDescription)")
            }
        }
    }
}
