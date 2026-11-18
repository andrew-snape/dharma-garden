/// Broad grouping of a plant, used for the seed shop and rules text.
public enum FlowerCategory: String, Codable, Sendable { case nativeFlower, exoticFlower, herb, vegetable }

public enum FlowerType: String, CaseIterable, Codable, Sendable {
    // The original four come first: DebugTools tests rely on the order of `allCases`.
    case sunflower, daisy, lavender, poppy
    case chocolateLily, commonEverlasting, calendula, cosmos, basil, zucchini, lettuce
    case beetroot, broccoli, carrot, rocket, corn, broadBean, radish, spinach
    case alyssum, nativeViolet, zinnia, billyButtons, bulbineLily, marigold
    case parsley, chives, coriander, dill, thyme

    public var daysToBloom: Double {
        switch self {
        case .sunflower: Tuning.sunflowerDaysToBloom
        case .daisy: Tuning.daisyDaysToBloom
        case .lavender: Tuning.lavenderDaysToBloom
        case .poppy: Tuning.poppyDaysToBloom
        case .chocolateLily: Tuning.chocolateLilyDaysToBloom
        case .commonEverlasting: Tuning.commonEverlastingDaysToBloom
        case .calendula: Tuning.calendulaDaysToBloom
        case .cosmos: Tuning.cosmosDaysToBloom
        case .basil: Tuning.basilDaysToBloom
        case .zucchini: Tuning.zucchiniDaysToBloom
        case .lettuce: Tuning.lettuceDaysToBloom
        case .beetroot: Tuning.beetrootDaysToBloom
        case .broccoli: Tuning.broccoliDaysToBloom
        case .carrot: Tuning.carrotDaysToBloom
        case .rocket: Tuning.rocketDaysToBloom
        case .corn: Tuning.cornDaysToBloom
        case .broadBean: Tuning.broadBeanDaysToBloom
        case .radish: Tuning.radishDaysToBloom
        case .spinach: Tuning.spinachDaysToBloom
        case .alyssum: Tuning.alyssumDaysToBloom
        case .nativeViolet: Tuning.nativeVioletDaysToBloom
        case .zinnia: Tuning.zinniaDaysToBloom
        case .billyButtons: Tuning.billyButtonsDaysToBloom
        case .bulbineLily: Tuning.bulbineLilyDaysToBloom
        case .marigold: Tuning.marigoldDaysToBloom
        case .parsley: Tuning.parsleyDaysToBloom
        case .chives: Tuning.chivesDaysToBloom
        case .coriander: Tuning.corianderDaysToBloom
        case .dill: Tuning.dillDaysToBloom
        case .thyme: Tuning.thymeDaysToBloom
        }
    }

    public var category: FlowerCategory {
        switch self {
        case .sunflower, .daisy, .lavender, .poppy, .calendula, .cosmos, .alyssum, .zinnia, .marigold: .exoticFlower
        case .chocolateLily, .commonEverlasting, .nativeViolet, .billyButtons, .bulbineLily: .nativeFlower
        case .basil, .parsley, .chives, .coriander, .dill, .thyme: .herb
        case .zucchini, .lettuce, .beetroot, .broccoli, .carrot, .rocket, .corn, .broadBean, .radish, .spinach: .vegetable
        }
    }

    public var isNative: Bool { category == .nativeFlower }

    public var displayName: String {
        switch self {
        case .sunflower: "Sunflower"
        case .daisy: "Daisy"
        case .lavender: "Lavender"
        case .poppy: "Poppy"
        case .chocolateLily: "Chocolate lily"
        case .commonEverlasting: "Common everlasting"
        case .calendula: "Calendula"
        case .cosmos: "Cosmos"
        case .basil: "Basil"
        case .zucchini: "Zucchini"
        case .lettuce: "Lettuce"
        case .beetroot: "Beetroot"
        case .broccoli: "Broccoli"
        case .carrot: "Carrot"
        case .rocket: "Rocket"
        case .corn: "Corn"
        case .broadBean: "Broad bean"
        case .radish: "Radish"
        case .spinach: "Spinach"
        case .alyssum: "Alyssum"
        case .nativeViolet: "Native violet"
        case .zinnia: "Zinnia"
        case .billyButtons: "Billy buttons"
        case .bulbineLily: "Bulbine lily"
        case .marigold: "Marigold"
        case .parsley: "Parsley"
        case .chives: "Chives"
        case .coriander: "Coriander"
        case .dill: "Dill"
        case .thyme: "Thyme"
        }
    }

    /// Short planting-season text for the seed shop.
    public var sowSeasonHint: String {
        switch self {
        case .sunflower, .cosmos, .basil, .zucchini, .corn, .zinnia, .marigold, .parsley: "Sow spring to summer"
        case .daisy, .calendula, .nativeViolet, .billyButtons: "Sow autumn or spring"
        case .lavender: "Sow spring"
        case .poppy, .chocolateLily, .commonEverlasting: "Sow autumn"
        case .lettuce: "Sow autumn to winter"
        case .broccoli: "Sow late summer to autumn"
        case .rocket: "Sow late summer or spring"
        case .broadBean: "Sow autumn to spring"
        case .alyssum: "Sow spring or autumn"
        case .chives: "Sow spring or summer"
        case .radish, .spinach: "Sow most of the year"
        case .beetroot, .carrot, .bulbineLily, .coriander, .dill, .thyme: "Sow spring to autumn"
        }
    }

    /// Herbs and vegetables are picked for "harvest"; flowers for "bloom".
    public var readyWord: String {
        switch category {
        case .herb, .vegetable: "harvest"
        case .nativeFlower, .exoticFlower: "bloom"
        }
    }

    // Traits
    public var lovesHeat: Bool { [.sunflower, .basil, .zucchini, .corn, .zinnia].contains(self) }
    public var dryTolerant: Bool { [.lavender, .chocolateLily, .commonEverlasting, .billyButtons, .bulbineLily, .thyme].contains(self) }
    public var frostTender: Bool { [.poppy, .cosmos, .basil, .zucchini, .corn, .zinnia, .marigold].contains(self) }
    public var frostTolerant: Bool {
        [.chocolateLily, .commonEverlasting, .calendula, .lettuce, .beetroot, .broccoli, .rocket, .radish, .spinach,
         .broadBean, .alyssum, .nativeViolet, .billyButtons, .bulbineLily, .parsley, .chives, .thyme].contains(self)
    }
    /// Cool-season plant that bolts in heat.
    public var coolSeason: Bool { [.lettuce, .rocket, .spinach].contains(self) }
    /// Drains soil moisture faster than other plants.
    public var thirsty: Bool { self == .zucchini || self == .corn }

    /// Carrots paid for a harvested flower: a quarter of its days to bloom.
    public var sellValue: Int { Int(daysToBloom / 4) }
    /// Seed price in carrots: 1 for quick crops (up to 60 days to bloom), 2 for slow ones.
    public var seedPrice: Int { daysToBloom <= 60 ? 1 : 2 }
}

public enum GrowthStage: Int, Codable, Sendable { case seed, sprout, bud, bloom }
