import Foundation
import SwiftUI
import DharmaGardenCore

/// Makes visitors for the garden view. The view keeps the list and the timers; this hands out ids and seeds
/// so each roll is different, and turns a roll into a visitor the scene can show.
struct VisitorController {
    /// Seconds between the early rolls that run until the first visitor turns up (about two minutes in all).
    static let earlyRollSeconds: TimeInterval = 20
    static let earlyRollTries = 6

    /// Rolls so far, mixed into each seed so no two rolls share one.
    private(set) var rolls = 0
    /// Ids handed out so far. Ids only grow, so a visitor's id is unique for the session.
    private var lastID = 0

    /// One check for a visitor. Returns nil when none arrives this time (see `VisitorSpawner.roll`).
    mutating func roll(garden: Garden, context: VisitorContext, now: Date, live: [Visitor]) -> Visitor? {
        rolls += 1
        let seed = UInt64(bitPattern: Int64(now.timeIntervalSince1970 * 1000)) ^ (UInt64(rolls) &* 0x9E37_79B9_7F4A_7C15)
        guard var visitor = VisitorSpawner.roll(garden: garden, context: context, now: now,
                                                liveCount: live.count, seed: seed) else { return nil }
        visitor.id = nextID()
        return visitor
    }

    /// A visitor of a chosen species at a random point on the patch, for the debug panel.
    mutating func spawn(_ species: VisitorSpecies, garden: Garden, now: Date) -> Visitor {
        rolls += 1
        let seed = UInt64.random(in: 0...UInt64.max)
        let position = garden.plot.point(seed: seed, inset: Tuning.sowInset)
        let lifetime = Tuning.visitorMinLifetimeSeconds
            + Double(seed % 1000) / 1000 * (Tuning.visitorMaxLifetimeSeconds - Tuning.visitorMinLifetimeSeconds)
        return Visitor(id: nextID(), species: species, position: position, spawnedAt: now, lifetime: lifetime)
    }

    private mutating func nextID() -> Int {
        lastID += 1
        return lastID
    }

    /// The context for a roll: the live weather when it is known, otherwise the defaults. Blooms come from the garden either way.
    static func context(report: WeatherReport?, garden: Garden, now: Date) -> VisitorContext {
        if let report {
            return VisitorContext.make(report: report, garden: garden, now: now)
        }
        return VisitorContext(bloomingPlants: VisitorContext.blooming(in: garden))
    }
}

/// "New entry: <name>!" shown near the top of the scene when a species is spotted for the first time.
/// It holds for a moment, then fades like the coin float.
struct EntryToast: View {
    let name: String
    @State private var faded = false

    var body: some View {
        Text("New entry: \(name)!")
            .font(.callout.bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.orange))
            .opacity(faded ? 0 : 1)
            .fixedSize()
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 1.4).delay(0.8)) { faded = true } }
    }
}
