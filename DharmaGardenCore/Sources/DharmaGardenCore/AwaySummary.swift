import Foundation

/// What changed in the garden while the player was away: the card shown on return ("3 plants ripened while you were away").
public struct AwaySummary: Equatable, Sendable {
    public var hoursAway: Int
    /// Plants that went from growing to blooming.
    public var ripened: Int
    /// Plants that were blooming and have begun to fade (or have gone to seed and left).
    public var faded: Int
    /// Plants that died of thirst or frost.
    public var withered: Int
    public var newDharmaGarden: Int
    /// Living plants that are dry now.
    public var thirsty: Int

    public var isEmpty: Bool { ripened + faded + withered + newDharmaGarden + thirsty == 0 }

    /// "3 hours", "1 day", "2 days".
    public var awayText: String {
        if hoursAway < 24 { return hoursAway == 1 ? "1 hour" : "\(hoursAway) hours" }
        let days = hoursAway / 24
        return days == 1 ? "1 day" : "\(days) days"
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }

    /// One line per thing that changed, most welcome news first.
    public var lines: [String] {
        var out: [String] = []
        if ripened > 0 { out.append("\(Self.count(ripened, "plant", "plants")) ripened") }
        if faded > 0 { out.append("\(Self.count(faded, "flower", "flowers")) started to fade") }
        if newDharmaGarden > 0 { out.append("\(Self.count(newDharmaGarden, "weed", "weeds")) appeared") }
        if withered > 0 { out.append("\(Self.count(withered, "plant", "plants")) withered") }
        if thirsty > 0 { out.append(thirsty == 1 ? "1 plant is thirsty" : "\(thirsty) plants are thirsty") }
        return out
    }
}

extension GardenEngine {
    /// Compares the garden before and after a catch-up. Plants are matched by id, so a plant that is new in `after`
    /// (a volunteer) is not counted as ripened.
    public static func awaySummary(from before: Garden, to after: Garden) -> AwaySummary {
        let old = Dictionary(before.plants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Dictionary(after.plants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ripened = 0, faded = 0, withered = 0
        for (id, was) in old where !was.isDead {
            if let is_ = now[id] {
                if is_.isDead { withered += 1 }
                else if was.lifeStage == .growing, is_.lifeStage == .blooming { ripened += 1 }
                else if was.lifeStage == .blooming, is_.lifeStage != .blooming { faded += 1 }
            } else if was.lifeStage == .blooming || was.lifeStage == .fading {
                // Gone: it went through fading and seed head, and dropped its seed.
                faded += was.lifeStage == .blooming ? 1 : 0
            }
        }
        let oldDharmaGarden = Set(before.weeds.map(\.id))
        let newDharmaGarden = after.weeds.filter { !oldDharmaGarden.contains($0.id) }.count
        let thirsty = after.plants.filter { !$0.isDead && $0.moisture < Tuning.growthPauseBelowMoisture }.count
        let hours = max(0, Int(after.lastSimulatedAt.timeIntervalSince(before.lastSimulatedAt) / 3600))
        return AwaySummary(hoursAway: hours, ripened: ripened, faded: faded, withered: withered,
                           newDharmaGarden: newDharmaGarden, thirsty: thirsty)
    }
}
