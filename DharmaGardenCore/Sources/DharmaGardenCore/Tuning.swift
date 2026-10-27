/// All balance numbers in one place.
public enum Tuning {
    // Growth durations: days from seed to first bloom at ideal conditions.
    public static let daisyDaysToBloom = 49.0
    public static let poppyDaysToBloom = 70.0
    public static let sunflowerDaysToBloom = 84.0
    public static let lavenderDaysToBloom = 120.0
    public static let chocolateLilyDaysToBloom = 100.0
    public static let commonEverlastingDaysToBloom = 80.0
    public static let calendulaDaysToBloom = 56.0
    public static let cosmosDaysToBloom = 60.0
    public static let basilDaysToBloom = 28.0
    public static let zucchiniDaysToBloom = 63.0
    public static let lettuceDaysToBloom = 42.0
    // New vegetables, herbs and flowers. Days come from The Seed Collection pages and plant-research.md where
    // they give a figure; the rest are game estimates (see plant-research.md, section 9).
    public static let beetrootDaysToBloom = 55.0
    public static let broccoliDaysToBloom = 150.0
    public static let carrotDaysToBloom = 130.0
    public static let rocketDaysToBloom = 45.0
    public static let cornDaysToBloom = 90.0
    public static let broadBeanDaysToBloom = 100.0
    public static let radishDaysToBloom = 30.0
    public static let spinachDaysToBloom = 45.0
    public static let alyssumDaysToBloom = 60.0
    public static let nativeVioletDaysToBloom = 60.0
    public static let zinniaDaysToBloom = 60.0
    public static let billyButtonsDaysToBloom = 90.0
    public static let bulbineLilyDaysToBloom = 90.0
    public static let marigoldDaysToBloom = 55.0
    public static let parsleyDaysToBloom = 60.0
    public static let chivesDaysToBloom = 120.0
    public static let corianderDaysToBloom = 45.0
    public static let dillDaysToBloom = 60.0
    public static let thymeDaysToBloom = 90.0

    // Life cycle after progress reaches 1 (whole days).
    public static let bloomDays = 10
    public static let fadeDays = 7
    public static let seedHeadDays = 3
    public static var lifeCycleHours: Int { (bloomDays + fadeDays + seedHeadDays) * 24 }

    /// Per-plant growth speed varies by +/- this fraction.
    public static let speedVariation = 0.08
    /// Moisture at or above this gives no droop; droop reaches 1 at moisture 0.
    public static let droopFullMoisture = 40.0

    public static let baseDrainPerHour = 1.0
    public static let heatThresholdC = 30.0
    public static let heatDrainMultiplier = 2.0
    /// Dry-tolerant plants (lavender, chocolate lily, common everlasting) lose moisture this much more slowly.
    public static let dryTolerantDrainMultiplier = 0.7
    /// Zucchini is thirsty and drains moisture faster than other plants.
    public static let thirstyDrainMultiplier = 1.2
    public static let windThresholdKmh = 30.0
    public static let windDrainMultiplier = 1.3
    public static let moisturePerRainMM = 10.0
    public static let growthPauseBelowMoisture = 20.0
    public static let wiltAfterDryHours = 48
    public static let deathAfterDryHours = 96
    public static let frostThresholdC = 2.0
    public static let frostGrowthMultiplier = 0.5
    public static let frostDurationHours = 24

    // Temperature growth rules
    /// Heat-loving plants (sunflower, basil, zucchini): growth is slowed below this temperature...
    public static let coldGrowthBelowC = 12.0
    public static let coldGrowthMultiplier = 0.6
    /// ...and boosted above this one.
    public static let heatGrowthAboveC = 25.0
    public static let heatGrowthMultiplier = 1.15
    /// Cool-season lettuce bolts above this temperature and its growth slows to 40 percent.
    public static let lettuceBoltAboveC = 28.0
    public static let lettuceBoltGrowthMultiplier = 0.4
    /// Lettuce gets a small bonus below this temperature.
    public static let lettuceCoolBelowC = 15.0
    public static let lettuceCoolGrowthMultiplier = 1.1
    /// DharmaGarden are checked for every this many hours (on the hour index), and each check may add one weed.
    public static let weedCheckEveryHours = 4
    public static let weedChancePerCheck = 0.08
    /// Weed spawns per check on the default plot: half the old rate (16 cells at 8 percent).
    public static let weedSpawnsPerCheckAtDefaultPlot = 8 * weedChancePerCheck
    /// Most weeds on the patch at once.
    public static let maxDharmaGarden = 12
    /// DharmaGarden reach full slowdown strength after this many hours; they start at half strength.
    public static let weedFullStrengthHours = 96
    /// Plants within this distance of a weed slow down.
    public static let weedSlowdownRadius = 0.07
    /// Slowdown per weed at full strength (times the weed's strength), and the cap on the total.
    public static let weedSlowdownPerWeed = 0.1
    public static let weedSlowdownCap = 0.3
    public static let waterAmount = 60.0
    public static let startingCoins = 25
    /// Daisy seed packets in a new garden. Planting uses one; the shop sells more.
    public static let startingDaisySeeds = 3

    /// Living plants the garden can hold.
    public static let maxPlants = 60
    /// Dead plants are only kept (for display) up to this many entries in total; the oldest go first.
    public static let maxEntriesKeptWithDead = 120
    /// Plants within this distance of another living plant grow more slowly.
    public static let crowdingRadius = 0.09
    /// Growth lost per neighbour, and the most that crowding can take in total.
    public static let crowdingPerNeighbour = 0.06
    public static let crowdingCap = 0.25
    /// Seeds may not land closer than this to a living plant.
    public static let sowSpacing = 0.045
    /// Volunteers and debug plants may land this close to a living plant.
    public static let volunteerSpacing = 0.04
    /// Volunteers land within this distance of the plant that dropped them.
    public static let volunteerRadius = 0.12
    public static let maxVolunteers = 3
    /// Nothing is planted or spawned closer than this to the plot edge.
    public static let sowInset = 0.01
    public static let weedSpawnInset = 0.03
    /// Default radius of a watering tap.
    public static let waterRadius = 0.14
    // Soil treatments. Each covers the cells within `treatRadius` and lasts a number of hours; a cell can only be
    // treated again once its treatment has run out.
    public static let treatRadius = 0.09
    /// Garden fork: aerated soil drains more slowly and plants in it grow a little faster. Free.
    public static let aerateHours = 120
    public static let aerateDrainMultiplier = 0.8
    public static let aerateGrowthBonus = 0.1
    /// Seasol seaweed tonic.
    public static let seasolHours = 72
    public static let seasolGrowthBonus = 0.15
    public static let seasolCost = 1
    /// Fertiliser.
    public static let fertiliserHours = 168
    public static let fertiliserGrowthBonus = 0.25
    public static let fertiliserCost = 2
    /// Default reach for pulling a weed (or clearing a withered plant).
    public static let pullReach = 0.05
    /// Default reach for picking a flower.
    public static let harvestReach = 0.06

    // Visitors (creatures that drop in on the garden; see Visitor.swift)
    /// Visitors on the patch at once.
    public static let maxVisitors = 3
    /// The app rolls for a visitor this often while it is open. Nothing spawns while it is closed.
    public static let visitorCheckSeconds = 300.0
    /// Chance that a check brings a visitor at all.
    public static let visitorArrivalChance = 0.35
    /// How long a visitor stays, from arrival to leaving.
    public static let visitorMinLifetimeSeconds = 20.0
    public static let visitorMaxLifetimeSeconds = 60.0
    /// How far from a bloom a flower visitor may land.
    public static let visitorPerchRadius = 0.05
    /// Carrots for spotting a visitor, by rarity.
    public static let visitorCommonReward = 1
    public static let visitorUncommonReward = 3
    public static let visitorRareReward = 8
    /// Rain counts as recent for this many hours (snails, frogs).
    public static let visitorRecentRainHours = 3.0
    /// Insects and birds stay away when the wind is at or above this.
    public static let visitorCalmWindKmh = 25.0
    /// Temperatures visitors need before they come out.
    public static let visitorWarmC = 14.0
    public static let visitorButterflyMinC = 12.0
    public static let visitorOrangeMinC = 15.0
    public static let visitorDragonflyMinC = 18.0
    public static let visitorLizardMinC = 20.0
    public static let visitorMothMinC = 12.0
    public static let visitorFrogMinC = 10.0
    /// Bees need at least this many flowers in bloom.
    public static let visitorBeeMinBlooms = 2

    // Side chores (things to do when the garden needs nothing; see SideChores.swift)
    /// Carrots to scatter seed for the birds.
    public static let birdFeedCost = 1
    /// Minutes before each chore can be done again.
    public static let birdFeedCooldownMinutes = 10.0
    public static let deadheadCooldownMinutes = 30.0
    public static let compostCooldownMinutes = 240.0
    /// Deadheading puts a fading plant back into bloom with this many hours of bloom left.
    public static let deadheadBloomHours = 48
    /// A turn of the compost feeds the soil under each plant for this many hours (a weaker fertiliser).
    public static let compostHours = 72
    /// A catch-up this long or longer gets a "while you were away" summary.
    public static let awaySummaryMinHours = 3
}
