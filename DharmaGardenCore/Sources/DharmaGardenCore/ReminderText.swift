import Foundation

/// Words for the daily reminder. Pure: the app passes in the garden, the time the notification fires,
/// and the cached forecast, and gets back one short line.
public enum ReminderText {
    /// Used when nothing needs attention.
    public static let fallback = "Your garden is doing fine"

    /// The message for the garden as it will be at `time`. The garden is first projected forward with the
    /// forecast (neutral weather where the forecast has no hour), then the message is chosen.
    public static func message(for garden: Garden, at time: Date, weather: [WeatherSample] = []) -> String {
        message(for: GardenEngine.advance(garden, weather: weather, to: time))
    }

    /// The message for the garden as it is now. Priority: ready to pick, then thirsty, then weeds, then fallback.
    public static func message(for garden: Garden) -> String {
        let living = garden.plants.filter { !$0.isDead }

        let ready = living.filter { $0.lifeStage == .blooming }
        if !ready.isEmpty { return readyText(ready.map(\.flower)) }

        let thirsty = living.filter { $0.moisture < Tuning.growthPauseBelowMoisture }
        if !thirsty.isEmpty { return thirstyText(thirsty.map(\.flower)) }

        // DharmaGarden count when two or more sit near a living plant.
        let creeping = living.contains { plant in
            garden.weeds.filter { $0.position.distance(to: plant.position) <= 0.12 }.count >= 2
        }
        if creeping { return "DharmaGarden are creeping in" }

        return fallback
    }

    // MARK: Sentences

    /// The verb for a ready plant: herbs and vegetables are harvested, flowers are picked. Built on
    /// `FlowerType.readyWord`, which is "harvest" for those and "bloom" for flowers.
    static func verb(for flower: FlowerType) -> String {
        flower.readyWord == "harvest" ? "harvest" : "pick"
    }

    /// "Your daisy is ready to pick", "2 basil are ready to harvest", "3 flowers are ready to pick".
    /// Flowers are picked when they bloom; herbs and vegetables are harvested. Mixed kinds that need different
    /// words fall back to "N plants are ready".
    static func readyText(_ flowers: [FlowerType]) -> String {
        let words = Set(flowers.map(verb))
        guard words.count == 1, let word = words.first else {
            return "\(flowers.count) plants are ready"
        }
        if flowers.count == 1 { return "Your \(name(for: flowers[0])) is ready to \(word)" }
        if let only = sameFlower(flowers) {
            return "\(flowers.count) \(plural(name(for: only))) are ready to \(word)"
        }
        return "\(flowers.count) \(word == "pick" ? "flowers" : "plants") are ready to \(word)"
    }

    static func thirstyText(_ flowers: [FlowerType]) -> String {
        if flowers.count == 1 { return "Your \(name(for: flowers[0])) is thirsty" }
        if let only = sameFlower(flowers) { return "Your \(plural(name(for: only))) are thirsty" }
        return "Some of your flowers are thirsty"
    }

    /// The flower type if every entry is the same one, otherwise nil.
    static func sameFlower(_ flowers: [FlowerType]) -> FlowerType? {
        guard let first = flowers.first, flowers.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: Names

    /// Lower-case name for use mid-sentence: "Common everlasting" -> "common everlasting".
    public static func name(for flower: FlowerType) -> String {
        flower.displayName.lowercased()
    }

    /// Names that do not take a plural ending when counted: "2 basil", "3 cosmos".
    static let uncountable: Set<String> = ["basil", "cosmos"]

    /// English plural of a lower-case name, using its last word: "daisy" -> "daisies", "chocolate lily" -> "chocolate lilies",
    /// "lettuce" -> "lettuces", "common everlasting" -> "common everlastings".
    static func plural(_ word: String) -> String {
        let lower = word.lowercased()
        if uncountable.contains(lower) { return word }
        if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) {
            return String(word.dropLast()) + "ies"
        }
        if ["s", "x", "z", "ch", "sh"].contains(where: { lower.hasSuffix($0) }) {
            return word + "es"
        }
        return word + "s"
    }
}
