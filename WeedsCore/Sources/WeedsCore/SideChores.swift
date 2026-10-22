import Foundation

/// Small jobs for when nothing needs doing: scatter seed for the birds, deadhead fading flowers, turn the compost.
/// Each has a cooldown (kept by the app, since it is real time) and is only offered when it would do something.
public enum SideChore: String, CaseIterable, Sendable, Codable {
    case feedBirds, deadhead, compost

    public var title: String {
        switch self {
        case .feedBirds: "Feed the birds"
        case .deadhead: "Deadhead the fading flowers"
        case .compost: "Turn the compost"
        }
    }

    /// What it does, in a few words for the chip's tooltip.
    public var detail: String {
        switch self {
        case .feedBirds: "Scatter some seed. A bird will drop in."
        case .deadhead: "Fading flowers bloom again for a couple of days."
        case .compost: "Feeds the soil under every plant a little."
        }
    }

    public var cost: Int { self == .feedBirds ? Tuning.birdFeedCost : 0 }

    public var cooldown: TimeInterval {
        switch self {
        case .feedBirds: Tuning.birdFeedCooldownMinutes * 60
        case .deadhead: Tuning.deadheadCooldownMinutes * 60
        case .compost: Tuning.compostCooldownMinutes * 60
        }
    }

    /// The chores worth offering now, in order: off cooldown (`readyAt` holds the time each is next allowed) and
    /// able to do something. `visitorCount` is how many visitors are on the patch.
    public static func available(garden g: Garden, readyAt: [String: Date], now: Date, visitorCount: Int) -> [SideChore] {
        allCases.filter { chore in
            if let ready = readyAt[chore.rawValue], ready > now { return false }
            let living = g.plants.filter { !$0.isDead }
            switch chore {
            case .feedBirds: return g.coins >= chore.cost && visitorCount < Tuning.maxVisitors
            case .deadhead: return living.contains { $0.lifeStage == .fading }
            case .compost: return living.contains { g.soil.fertiliserHours[SoilField.cellIndex(of: $0.position)] == 0 }
            }
        }
    }
}

extension GardenEngine {
    /// Pays for the bird seed. False (and nothing changes) when the player cannot afford it.
    @discardableResult
    public static func feedBirds(in g: inout Garden) -> Bool {
        guard g.coins >= Tuning.birdFeedCost else { return false }
        g.coins -= Tuning.birdFeedCost
        return true
    }

    /// Puts every fading plant back into bloom with `Tuning.deadheadBloomHours` of bloom left. Returns how many.
    @discardableResult
    public static func deadhead(in g: inout Garden) -> Int {
        var count = 0
        for i in g.plants.indices where !g.plants[i].isDead && g.plants[i].lifeStage == .fading {
            g.plants[i].bloomHoursElapsed = max(0, Tuning.bloomDays * 24 - Tuning.deadheadBloomHours)
            count += 1
        }
        return count
    }

    /// Feeds the soil under each living plant for `Tuning.compostHours` (soil that is already fed keeps its
    /// treatment). Returns how many plants got something.
    @discardableResult
    public static func compost(in g: inout Garden) -> Int {
        var count = 0
        for plant in g.plants where !plant.isDead {
            if g.soil.treat(\.fertiliserHours, hours: Tuning.compostHours, at: plant.position, radius: Tuning.treatRadius) {
                count += 1
            }
        }
        return count
    }
}
