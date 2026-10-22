import Foundation

/// A collection-book reward, paid once when the player has spotted enough different visitor species.
public struct VisitorMilestone: Equatable, Sendable, Identifiable {
    /// Different species spotted that unlock the reward. Also the id, and the value stored in `Garden.claimedMilestones`.
    public var species: Int
    public var title: String
    public var coins: Int
    /// Seed packets granted with the coins.
    public var seeds: [FlowerType: Int]

    public var id: Int { species }

    public init(species: Int, title: String, coins: Int, seeds: [FlowerType: Int] = [:]) {
        self.species = species
        self.title = title
        self.coins = coins
        self.seeds = seeds
    }

    /// The rewards in order. The last one needs every species in the book, so it tracks `VisitorSpecies.allCases`.
    public static let all: [VisitorMilestone] = [
        VisitorMilestone(species: 4, title: "Four visitors", coins: 10),
        VisitorMilestone(species: 8, title: "Eight visitors", coins: 15, seeds: [.lavender: 2]),
        VisitorMilestone(species: VisitorSpecies.allCases.count, title: "Full book", coins: 60,
                         seeds: [.chocolateLily: 3]),
    ]
}
