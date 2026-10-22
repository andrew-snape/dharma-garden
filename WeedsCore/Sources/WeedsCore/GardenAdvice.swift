import Foundation

/// What the garden needs doing right now, as short lines the player can act on. Pure: the app passes in the
/// garden and the forecast. The wording is shared with the daily reminder (`ReminderText`).
public struct GardenAdvice: Equatable, Sendable {
    /// The tool (or place) that answers the advice.
    public enum Action: Equatable, Sendable { case pick, water, weed, sow, shop }

    public var action: Action
    public var text: String

    /// Rain over this many millimetres in the next day counts as "rain on the way".
    static let rainThresholdMM = 2.0

    /// Advice in order of how much it matters: ready plants, then thirsty ones, then weeds, then (for an empty
    /// bed) getting started. Empty when the garden is fine.
    public static func tips(for garden: Garden) -> [GardenAdvice] {
        var out: [GardenAdvice] = []
        let living = garden.plants.filter { !$0.isDead }

        let ready = living.filter { $0.lifeStage == .blooming }
        if !ready.isEmpty { out.append(GardenAdvice(action: .pick, text: ReminderText.readyText(ready.map(\.flower)))) }

        let thirsty = living.filter { $0.moisture < Tuning.growthPauseBelowMoisture }
        if !thirsty.isEmpty { out.append(GardenAdvice(action: .water, text: ReminderText.thirstyText(thirsty.map(\.flower)))) }

        if !garden.weeds.isEmpty {
            let text = garden.weeds.count == 1 ? "A weed is growing" : "\(garden.weeds.count) weeds are growing"
            out.append(GardenAdvice(action: .weed, text: text))
        }

        if living.isEmpty {
            if garden.seeds.isEmpty {
                out.append(GardenAdvice(action: .shop, text: "Buy some seeds in the shop"))
            } else {
                out.append(GardenAdvice(action: .sow, text: "Sow a seed to get started"))
            }
        }
        return out
    }

    /// True when enough rain is forecast in the 24 hours from `now` that watering can wait.
    public static func rainExpected(in hourly: [WeatherSample], from now: Date) -> Bool {
        let end = now.addingTimeInterval(24 * 3600)
        let total = hourly.filter { $0.date >= now.addingTimeInterval(-3600) && $0.date < end }
            .reduce(0) { $0 + $1.precipitationMM }
        return total >= rainThresholdMM
    }

    /// "Good morning", "Good afternoon" or "Good evening" for the hour of `date`.
    public static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
