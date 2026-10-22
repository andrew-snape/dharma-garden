import Foundation

/// A goal that earns a Game Center achievement. What each one is worth is set in App Store Connect, not here.
/// Whether a goal is reached is worked out from the garden alone, so reporting it again is harmless.
public enum GardenAchievement: String, CaseIterable, Sendable {
    case firstBloom, fourVisitors, eightVisitors, fullBook, weekStreak

    /// Days in a row the app must be opened for `weekStreak`.
    public static let streakDays = 7

    /// The achievement's id in App Store Connect.
    public var identifier: String { "weeds.achievement.\(rawValue)" }

    /// The visitor milestone this achievement mirrors (`VisitorMilestone.species`), if it is one.
    var milestoneSpecies: Int? {
        switch self {
        case .fourVisitors: 4
        case .eightVisitors: 8
        case .fullBook: VisitorSpecies.allCases.count
        case .firstBloom, .weekStreak: nil
        }
    }

    /// The goals the garden has reached so far.
    public static func earned(in g: Garden) -> Set<GardenAchievement> {
        Set(allCases.filter { $0.isReached(in: g) })
    }

    private func isReached(in g: Garden) -> Bool {
        switch self {
        case .firstBloom: g.plants.contains { $0.progress >= 1 }
        case .weekStreak: g.openStreak >= Self.streakDays
        case .fourVisitors, .eightVisitors, .fullBook:
            milestoneSpecies.map { g.claimedMilestones.contains($0) } ?? false
        }
    }
}
