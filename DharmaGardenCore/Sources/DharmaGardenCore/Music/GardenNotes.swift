import Foundation

/// Things that happen in the garden and may answer with a note or two on the handpan.
public enum GardenNoteEvent: Equatable, Sendable {
    case plant, water, harvest, visitorSpotted, flowerOpened, rainBegan
}

/// One note to play: `delay` seconds after the event, `scaleIndex` into `ModalInstrument.scale` (0 is the low
/// ding, 8 the top), `velocity` 0...1 and `pan` -1...1.
public struct GardenNote: Equatable, Sendable {
    public var delay: Double
    public var scaleIndex: Int
    public var velocity: Double
    public var pan: Double

    public init(delay: Double, scaleIndex: Int, velocity: Double, pan: Double) {
        self.delay = delay
        self.scaleIndex = scaleIndex
        self.velocity = velocity
        self.pan = pan
    }
}

/// Turns garden events into handpan notes: the same instrument as the pieces, so it is always in key. It is
/// meant to be rare and soft. Only one event in a few seconds gets a sound, so a long drag with the can or the
/// rake gives one note rather than a stream.
public struct GardenNotes: Sendable {
    /// Least time between two events that sound, by how often the player wants music.
    public static func window(for density: MusicDensity) -> TimeInterval {
        density == .often ? 3 : 6
    }
    /// An opening flower sounds at most this often, however many open.
    public static let flowerWindow: TimeInterval = 120
    public static let velocityRange: ClosedRange<Double> = 0.15...0.35
    public static let nightFactor = 0.7
    public static let scaleCount = 9

    private var rng: SplitMix
    private var lastTrigger: Date?
    private var lastFlower: Date?
    private var lastIndex: Int?

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        rng = SplitMix(seed: seed)
    }

    /// The notes for `event` at `now`, or none when the event falls inside the rate-limit window, music is off,
    /// or (for a flower) one opened too recently. `x` is where on screen it happened, 0 (left) to 1 (right).
    public mutating func notes(for event: GardenNoteEvent, at now: Date, x: Double = 0.5,
                               density: MusicDensity, night: Bool) -> [GardenNote] {
        guard density != .off else { return [] }
        if event == .flowerOpened, let last = lastFlower, now.timeIntervalSince(last) < Self.flowerWindow { return [] }
        if let last = lastTrigger, now.timeIntervalSince(last) < Self.window(for: density) { return [] }
        lastTrigger = now
        if event == .flowerOpened { lastFlower = now }

        let pan = (min(max(x, 0), 1) - 0.5) * 1.2
        var plan: [(delay: Double, index: Int)]
        switch event {
        case .plant:
            plan = [(0, rng.unit() < 0.5 ? 0 : 1)]
        case .water:
            // Two or three notes climbing the ring, a breath apart.
            let count = rng.unit() < 0.5 ? 2 : 3
            var index = int(1...3)
            var delay = 0.0
            plan = []
            for _ in 0..<count {
                plan.append((delay, index))
                index += rng.unit() < 0.35 ? 2 : 1
                delay += 0.4 + 0.4 * rng.unit()
            }
        case .harvest:
            plan = [(0, 4)]
        case .visitorSpotted, .flowerOpened:
            plan = [(0, int(5...8))]
        case .rainBegan:
            // A slow falling run, like the first drops.
            var index = int(6...8)
            plan = []
            for step in 0..<3 {
                plan.append((Double(step) * (1.1 + 0.4 * rng.unit()), index))
                index -= rng.unit() < 0.35 ? 2 : 1
            }
        }

        var result: [GardenNote] = []
        for item in plan {
            var index = min(max(item.index, 0), Self.scaleCount - 1)
            // Never the same note twice running: move one step instead.
            if index == lastIndex { index = index == Self.scaleCount - 1 ? index - 1 : index + 1 }
            lastIndex = index
            var velocity = Self.velocityRange.lowerBound
                + rng.unit() * (Self.velocityRange.upperBound - Self.velocityRange.lowerBound)
            if night { velocity *= Self.nightFactor }
            result.append(GardenNote(delay: item.delay, scaleIndex: index, velocity: velocity, pan: pan))
        }
        return result
    }

    private mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + min(range.count - 1, Int(rng.unit() * Double(range.count)))
    }
}
