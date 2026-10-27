import Foundation

/// The time of day (or weather) a piece is played for. Each mood is a handful of dials, not a different
/// method: the same player, in a different frame of mind.
public enum PieceMood: String, CaseIterable, Sendable, Codable {
    case dawn, day, dusk, night, rain

    public var parameters: MoodParameters {
        switch self {
        case .dawn:
            // High, sparse and a little hopeful.
            return MoodParameters(bpm: 66...75, phraseLength: 3...6, rest: 4.5...9, restCap: 13,
                                  register: 7.0, registerRise: 0.6, velocity: 0.34, timingJitter: 0.018,
                                  motifChance: 0.55, repeatChance: 0.10, doubleStrikeChance: 0.05,
                                  anchorEvery: 60)
        case .day:
            // The fullest mood, which is still only a few notes a breath.
            return MoodParameters(bpm: 68...75, phraseLength: 4...8, rest: 3.2...7, restCap: 11,
                                  register: 5.0, registerRise: 0.8, velocity: 0.40, timingJitter: 0.020,
                                  motifChance: 0.55, repeatChance: 0.12, doubleStrikeChance: 0.14,
                                  anchorEvery: 55)
        case .dusk:
            // Lower and slower, with the ding coming round more often.
            return MoodParameters(bpm: 60...66, phraseLength: 3...7, rest: 4.5...9, restCap: 13,
                                  register: 2.8, registerRise: 0.5, velocity: 0.34, timingJitter: 0.022,
                                  motifChance: 0.55, repeatChance: 0.15, doubleStrikeChance: 0.08,
                                  anchorEvery: 45)
        case .night:
            // Rare, soft, and very long silences.
            return MoodParameters(bpm: 60...64, phraseLength: 3...5, rest: 8...18, restCap: 24,
                                  register: 4.0, registerRise: 0.3, velocity: 0.27, timingJitter: 0.025,
                                  motifChance: 0.50, repeatChance: 0.20, doubleStrikeChance: 0,
                                  anchorEvery: 70)
        case .rain:
            // Slow and low, circling the same few ideas like drops on a roof.
            return MoodParameters(bpm: 60...65, phraseLength: 3...6, rest: 5...10, restCap: 13,
                                  register: 2.6, registerRise: 0.4, velocity: 0.32, timingJitter: 0.022,
                                  motifChance: 0.65, repeatChance: 0.35, doubleStrikeChance: 0.05,
                                  anchorEvery: 40)
        }
    }
}

/// The dials behind a mood. Plain numbers so they are easy to retune by ear.
public struct MoodParameters: Sendable {
    /// Pulse of the notes inside a phrase. There is no metre; this is how fast a player's hand falls.
    public var bpm: ClosedRange<Double>
    /// Notes per phrase in the fullest part of the piece (the opening and ending use fewer).
    public var phraseLength: ClosedRange<Int>
    /// Silence after a phrase, in seconds: the long end when the piece is sparse, the short end when full.
    public var rest: ClosedRange<Double>
    public var restCap: Double
    /// Where the hand sits on the ring, as a scale index (4 is D4, 8 is A4).
    public var register: Double
    /// How far the hand drifts upward at the fullest point of the piece.
    public var registerRise: Double
    /// Typical strike strength, 0...1.
    public var velocity: Double
    /// Human timing wobble, seconds either side of the pulse.
    public var timingJitter: Double
    /// Chance a phrase is a statement of one of the piece's motifs rather than free wandering.
    public var motifChance: Double
    /// Chance a phrase repeats the previous one almost exactly.
    public var repeatChance: Double
    /// Chance, in the fuller part, that a note is struck together with the ding.
    public var doubleStrikeChance: Double
    /// About how often (seconds) the low ding comes round as an anchor.
    public var anchorEvery: Double
}

/// A phrase as played: its notes and where it sat.
public struct ImprovisedPhrase: Sendable {
    public var events: [HandpanEvent]
    /// Time of the first and last melodic note.
    public var start: Double
    public var end: Double
}

public struct ImprovisedPiece: Sendable {
    public var mood: PieceMood
    public var seed: UInt64
    public var duration: Double
    public var phrases: [ImprovisedPhrase]
    /// Every event, sorted by time.
    public var events: [HandpanEvent]
}

/// The notes a player has under the hand, and which of them are home.
///
/// The improviser thinks in indices into `notes`, never in pitches, so the same player can sit at a handpan, a
/// kalimba, a piano or an electric piano. `handpan` reproduces the original D Kurd player exactly (same seed,
/// same events); the others only change which notes the indices mean and a few dials.
public struct PieceScale: Sendable {
    /// MIDI numbers, lowest first.
    public var notes: [Int]
    /// The low anchor (the handpan's ding): sounded alone to open, and the note the player returns to now and then.
    public var anchor: Int
    /// The playable ring. The anchor sits outside it on a handpan; on other instruments it can be anywhere.
    public var ring: ClosedRange<Int>
    /// Cadence notes: D in the middle of the ring, a low A, and a high A.
    public var home: Int
    public var lowFifth: Int
    public var high: Int
    /// Notes a phrase can end on while leaving a question hanging (F and C on the handpan).
    public var questions: [Int]
    /// Added to a mood's `register` (which is written in handpan indices) to find where the hand sits here.
    public var registerOffset: Double
    /// Stretches the silences, for an instrument that wants to be even sparser.
    public var restScale: Double
    /// Whether a note may be struck together with the anchor (a handpan trick; wrong for a keyboard).
    public var doubleStrikeAnchor: Bool
    /// An occasional soft low note under the first note of a phrase (a left hand on a piano). Never used on the handpan.
    public var underlay: Underlay?

    public struct Underlay: Sendable {
        /// Indices into `notes`, e.g. a low fifth and the octave below home.
        public var indices: [Int]
        public var chance: Double
        public init(indices: [Int], chance: Double) { self.indices = indices; self.chance = chance }
    }

    public init(notes: [Int], anchor: Int, ring: ClosedRange<Int>, home: Int, lowFifth: Int, high: Int,
                questions: [Int], registerOffset: Double = 0, restScale: Double = 1,
                doubleStrikeAnchor: Bool = false, underlay: Underlay? = nil) {
        self.notes = notes; self.anchor = anchor; self.ring = ring; self.home = home
        self.lowFifth = lowFifth; self.high = high; self.questions = questions
        self.registerOffset = registerOffset; self.restScale = restScale
        self.doubleStrikeAnchor = doubleStrikeAnchor; self.underlay = underlay
    }

    /// D Kurd: D3 A3 Bb3 C4 D4 E4 F4 G4 A4. The default, and exactly the original behaviour.
    public static let handpan = PieceScale(
        notes: ModalInstrument.scale, anchor: 0, ring: 1...8, home: 4, lowFifth: 1, high: 8, questions: [6, 3],
        doubleStrikeAnchor: true)
}

/// A solo handpan player, in code.
///
/// The model: a hand rests near one part of the ring and plays short phrases on a loose pulse, mostly by step,
/// then lets the last note ring while it breathes. A couple of small motifs come back changed so the piece
/// sounds meant. Over the whole piece the player opens with single notes, builds a little, and thins out to a
/// last long D. Deterministic for a seed, and pure, so it can be tested without rendering a sample.
public enum Improviser {
    /// Indices into `ModalInstrument.scale`. 0 is the low ding; 1...8 are the playable ring.
    static let ringRange = 1...8

    public static func piece(mood: PieceMood, seed: UInt64, minutes: Double,
                             scale: PieceScale = .handpan) -> [HandpanEvent] {
        compose(mood: mood, seed: seed, minutes: minutes, scale: scale).events
    }

    /// How full the piece is at `progress` (0...1): rises over the opening, holds, falls toward the end.
    public static func fullness(at progress: Double) -> Double {
        func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
            let u = min(1, max(0, (x - a) / (b - a)))
            return u * u * (3 - 2 * u)
        }
        return smooth(0.05, 0.40, progress) * (1 - smooth(0.65, 0.95, progress))
    }

    // MARK: Motifs

    struct Motif {
        var steps: [Int]       // scale-degree moves between consecutive notes
        var beats: [Double]    // beats from each note to the next (count = steps.count + 1)
        var home: Int          // where it was first heard
    }

    static func makeMotif(register: Double, ring: ClosedRange<Int> = ringRange, rng: inout SplitMix) -> Motif {
        let count = 3 + Int(rng.unit() * 3)
        var steps: [Int] = []
        for _ in 0..<(count - 1) {
            let r = rng.unit()
            let size = r < 0.62 ? 1 : (r < 0.88 ? 2 : 3)
            steps.append(rng.unit() < 0.5 ? size : -size)
        }
        var beats: [Double] = []
        for i in 0..<count {
            let r = rng.unit()
            var b = r < 0.6 ? 1.0 : (r < 0.78 ? 0.5 : (r < 0.9 ? 1.5 : 2.0))
            if i == 0 && b < 1 { b = 1 }
            beats.append(b)
        }
        let home = min(ring.upperBound - 1, max(ring.lowerBound + 1, Int(register.rounded()) + Int(rng.signed() * 1.5)))
        return Motif(steps: steps, beats: beats, home: home)
    }

    /// Notes of a motif starting on `start`, shifted back into the ring if it would fall off an edge.
    static func degrees(of steps: [Int], start: Int, ring ringRange: ClosedRange<Int> = ringRange) -> [Int] {
        var d = [start]
        for s in steps { d.append(d.last! + s) }
        let low = d.min()!, high = d.max()!
        var shift = 0
        if low < ringRange.lowerBound { shift = ringRange.lowerBound - low }
        else if high > ringRange.upperBound { shift = ringRange.upperBound - high }
        return d.map { min(ringRange.upperBound, max(ringRange.lowerBound, $0 + shift)) }
    }

    // MARK: Walking

    /// A free stepwise line of `count` notes beginning on `start`, leaning back toward `centre`.
    static func walk(from start: Int, count: Int, centre: Double, ring ringRange: ClosedRange<Int> = ringRange,
                     rng: inout SplitMix) -> [Int] {
        var out = [start]
        var direction = rng.unit() < 0.5 ? 1 : -1
        while out.count < count {
            let pos = out.last!
            let pull = (centre - Double(pos)) * 0.3
            if rng.unit() > 0.6 { direction = rng.unit() < 0.5 + pull ? 1 : -1 }
            let r = rng.unit()
            let size = r < 0.08 ? 0 : (r < 0.66 ? 1 : (r < 0.90 ? 2 : 3))
            var next = pos + direction * size
            if next > ringRange.upperBound || next < ringRange.lowerBound {
                direction = -direction
                next = pos + direction * size
            }
            out.append(min(ringRange.upperBound, max(ringRange.lowerBound, next)))
        }
        return out
    }

    static func freeBeats(count: Int, rng: inout SplitMix) -> [Double] {
        var beats: [Double] = []
        var i = 0
        while i < count {
            let r = rng.unit()
            if r < 0.14 && i + 1 < count && i > 0 {
                // A half-beat pickup into the next note.
                beats.append(0.5); beats.append(rng.unit() < 0.5 ? 0.5 : 1.0); i += 2
            } else if r < 0.27 {
                beats.append(1.5); i += 1
            } else if r < 0.40 && i > 0 {
                beats.append(2.0); i += 1
            } else {
                beats.append(1.0); i += 1
            }
        }
        return Array(beats.prefix(count))
    }

    // MARK: Composing

    private struct Cadence {
        var degree: Int
        var isQuestion: Bool
    }

    private static func pickCadence(answering: Bool, dingDue: Bool, allowQuestion: Bool, scale: PieceScale,
                                    rng: inout SplitMix) -> Cadence {
        if dingDue && rng.unit() < 0.7 { return Cadence(degree: scale.anchor, isQuestion: false) }
        let r = rng.unit()
        if answering {
            // An answer always comes home.
            return Cadence(degree: r < 0.5 ? scale.home : (r < 0.72 ? scale.lowFifth : (r < 0.90 ? scale.high : scale.anchor)),
                           isQuestion: false)
        }
        if r < 0.28 { return Cadence(degree: scale.home, isQuestion: false) }
        if r < 0.50 { return Cadence(degree: scale.lowFifth, isQuestion: false) }
        if r < 0.66 { return Cadence(degree: scale.high, isQuestion: false) }
        if r < 0.74 { return Cadence(degree: scale.anchor, isQuestion: false) }
        if !allowQuestion { return Cadence(degree: scale.home, isQuestion: false) }
        return Cadence(degree: r < 0.88 ? scale.questions[0] : scale.questions[1], isQuestion: true)
    }

    public static func compose(mood: PieceMood, seed: UInt64, minutes: Double,
                               scale: PieceScale = .handpan) -> ImprovisedPiece {
        let p = mood.parameters
        let ring = scale.ring
        let anchor = scale.anchor
        let baseRegister = p.register + scale.registerOffset
        func clampRing(_ d: Int) -> Int { min(ring.upperBound, max(ring.lowerBound, d)) }
        // A second stream for anything only the other instruments do, so the handpan's stream is never disturbed.
        var extra = SplitMix(seed: seed &* 0xA24B_AED4_963E_E407 &+ UInt64(PieceMood.allCases.firstIndex(of: mood) ?? 0))
        let duration = minutes * 60
        let moodIndex = UInt64(PieceMood.allCases.firstIndex(of: mood) ?? 0) + 1
        var rng = SplitMix(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ moodIndex &* 0xD1B5_4A32_D192_ED03)
        _ = rng.next()

        let motifs = [makeMotif(register: baseRegister, ring: ring, rng: &rng),
                      makeMotif(register: baseRegister, ring: ring, rng: &rng)]
        var phrases: [ImprovisedPhrase] = []

        // The last melodic phrase must end early enough for the closing D to ring before the fade.
        let phraseLimit = duration - 22
        var time = 1.5 + 2 * rng.unit()
        var lastDing = -1000.0
        var degree = scale.home
        var owedAnswerMotif: Int? = nil
        var previousDegrees: [Int] = []
        var previousBeats: [Double] = []

        while true {
            let progress = time / duration
            let full = fullness(at: progress)
            let centre = baseRegister + p.registerRise * full
            let beatSeconds = 60 / (p.bpm.lowerBound + (p.bpm.upperBound - p.bpm.lowerBound) * rng.unit())
            let dingDue = time - lastDing > p.anchorEvery * (0.8 + 0.4 * rng.unit()) && full > 0.1
            let isFirst = phrases.isEmpty

            var degrees: [Int]
            var beats: [Double]
            if isFirst || full < 0.18 { owedAnswerMotif = nil }

            if isFirst {
                // Always open on the ding, alone.
                degrees = [anchor]; beats = [2.0]
            } else if full < 0.18 {
                // Sparse edges: one note, sometimes two.
                let cadence = pickCadence(answering: false, dingDue: dingDue, allowQuestion: false, scale: scale, rng: &rng)
                if rng.unit() < 0.6 {
                    degrees = [cadence.degree]; beats = [2.0]
                } else {
                    let first = clampRing(cadence.degree + (rng.unit() < 0.5 ? 1 : -1))
                    degrees = [first, cadence.degree]; beats = [1.5, 2.0]
                }
            } else if !previousDegrees.isEmpty && owedAnswerMotif == nil && rng.unit() < p.repeatChance {
                // Say it again, nearly: same line, perhaps one step off, ending where it ended.
                let shift = rng.unit() < 0.35 ? (rng.unit() < 0.5 ? 1 : -1) : 0
                degrees = previousDegrees.map { $0 == anchor ? anchor : clampRing($0 + shift) }
                beats = previousBeats
            } else {
                let allowQuestion = full > 0.3
                let target = (full * Double(p.phraseLength.upperBound - p.phraseLength.lowerBound)
                              * (0.6 + 0.4 * rng.unit()))
                let count = min(9, max(p.phraseLength.lowerBound, p.phraseLength.lowerBound + Int(target.rounded())))
                let answering = owedAnswerMotif != nil
                let cadence = pickCadence(answering: answering, dingDue: dingDue, allowQuestion: allowQuestion,
                                          scale: scale, rng: &rng)
                let question = cadence.isQuestion

                var usedMotif: Int? = owedAnswerMotif
                if usedMotif == nil && rng.unit() < p.motifChance { usedMotif = Int(rng.unit() * 2) }

                if let m = usedMotif {
                    let motif = motifs[m]
                    var steps = motif.steps
                    var mBeats = motif.beats
                    var start = motif.home
                    let r = rng.unit()
                    if answering {
                        // The answer is the question's idea again, mostly unchanged.
                        if r < 0.3 {
                            start = min(ring.upperBound - 1, max(ring.lowerBound + 1, start + (rng.unit() < 0.5 ? 1 : -1)))
                        }
                    } else if r < 0.28 {
                        start = clampRing(Int(centre.rounded()) + Int(rng.signed() * 2))        // transposed
                    } else if r < 0.46 {
                        steps = steps.map { -$0 }                                              // inverted
                    } else if r < 0.64 {
                        let more = walk(from: ring.lowerBound - 1, count: 3, centre: centre, ring: ring, rng: &rng)  // extended
                        steps += [more[1] - more[0], more[2] - more[1]]
                        mBeats += freeBeats(count: 2, rng: &rng)
                    } else if r < 0.80 {
                        mBeats = freeBeats(count: mBeats.count, rng: &rng)                      // new rhythm
                    }
                    degrees = Self.degrees(of: steps, start: start, ring: ring)
                    beats = mBeats
                    if degrees.count < count {
                        let more = walk(from: degrees.last!, count: count - degrees.count + 1, centre: centre, ring: ring, rng: &rng)
                        degrees += more.dropFirst()
                        beats += freeBeats(count: more.count - 1, rng: &rng)
                    }
                    if !answering && question { owedAnswerMotif = m } else { owedAnswerMotif = nil }
                } else {
                    let start = clampRing(degree == anchor ? scale.home : degree)
                    degrees = walk(from: start, count: count, centre: centre, ring: ring, rng: &rng)
                    beats = freeBeats(count: count, rng: &rng)
                    owedAnswerMotif = question ? Int(rng.unit() * 2) : nil
                }

                // Approach the cadence by step, then land on it.
                var last = degrees.last!
                if last != cadence.degree {
                    if cadence.degree == anchor {
                        degrees.append(anchor); beats.append(2.0)
                    } else {
                        while abs(cadence.degree - last) > 1 && degrees.count < 9 {
                            last += cadence.degree > last ? 1 : -1
                            degrees.append(last)
                            beats.append(1.0)
                            if abs(cadence.degree - last) > 2 { last += cadence.degree > last ? 1 : -1 }
                        }
                        degrees.append(cadence.degree)
                    }
                }
                // Keep the length within a hand's reach, always keeping the cadence note.
                if degrees.count > 9 { degrees = Array(degrees.prefix(8)) + [cadence.degree] }
                beats = Array((beats + [Double](repeating: 1, count: degrees.count)).prefix(degrees.count))
                beats[beats.count - 1] = cadence.degree == anchor ? 2.0 : (rng.unit() < 0.5 ? 2.0 : 1.5)
            }

            // Lay the notes on the loose pulse.
            var events: [HandpanEvent] = []
            var t = time
            let n = degrees.count
            var phraseEnd = time
            for (k, d) in degrees.enumerated() {
                let swell = sin(Double.pi * (Double(k) + 0.5) / Double(n))
                var v = p.velocity * (0.9 + 0.2 * full) * (0.8 + 0.35 * swell)
                if k == 0 && n > 1 { v *= 1.12 }
                v += rng.signed() * 0.02
                if isFirst { v = p.velocity * 0.9 }
                v = min(0.6, max(0.2, v))
                let when = max(0, t + rng.signed() * p.timingJitter)
                events.append(HandpanEvent(time: when, midi: scale.notes[d], velocity: v))
                // Occasionally strike the ding together with a melodic note, in the fuller part.
                if scale.doubleStrikeAnchor, d != anchor, full > 0.5, (k == 0 || k == n - 1),
                   rng.unit() < p.doubleStrikeChance {
                    events.append(HandpanEvent(time: when + 0.004 + 0.008 * rng.unit(),
                                               midi: scale.notes[anchor], velocity: min(0.6, max(0.2, v * 0.6))))
                }
                if d == anchor { lastDing = when }
                phraseEnd = when
                t += beats[k] * beatSeconds
            }
            // A left hand: now and then a soft low note under the phrase's first note, in the fuller part.
            if let under = scale.underlay, !isFirst, full > 0.25, extra.unit() < under.chance, let first = events.first {
                let index = under.indices[Int(extra.unit() * Double(under.indices.count)) % under.indices.count]
                events.append(HandpanEvent(time: first.time + 0.01 + 0.02 * extra.unit(), midi: scale.notes[index],
                                           velocity: min(0.6, max(0.15, first.velocity * 0.6))))
            }
            // `t` is now the time the last note's own length runs out.
            let ringEnd = t
            if ringEnd > phraseLimit && !phrases.isEmpty { break }
            phrases.append(ImprovisedPhrase(events: events, start: events[0].time, end: phraseEnd))
            degree = degrees.last!
            previousDegrees = degrees
            previousBeats = beats

            let restBase = p.rest.upperBound - (p.rest.upperBound - p.rest.lowerBound) * full
            var rest = restBase * (0.8 + 0.4 * rng.unit())
            rest = min(p.restCap, max(max(2.4, p.rest.lowerBound * 0.9), rest))
            if scale.restScale != 1 { rest = min(p.restCap * scale.restScale, rest * scale.restScale) }
            // A question hangs in the air a little less before its answer arrives.
            if owedAnswerMotif != nil { rest = max(2.4, rest * 0.8) }
            time = ringEnd + rest
        }

        // The last word: a single D, after a long breath, left to ring out under the fade.
        let lastEnd = phrases.last!.end
        let finalTime = min(duration - 10, lastEnd + 5.5 + 2.5 * rng.unit())
        let finalMidi = rng.unit() < 0.5 ? scale.notes[anchor] : scale.notes[scale.home]
        let finalEvent = HandpanEvent(time: finalTime, midi: finalMidi, velocity: min(0.6, max(0.2, p.velocity * 0.85)))
        phrases.append(ImprovisedPhrase(events: [finalEvent], start: finalTime, end: finalTime))

        let all = phrases.flatMap(\.events).sorted { $0.time < $1.time }
        return ImprovisedPiece(mood: mood, seed: seed, duration: duration, phrases: phrases, events: all)
    }
}

/// Numbers that describe a piece, used by the tests and by the batch renderer's first-cut filter.
public struct PieceMetrics: Sendable, Codable {
    public var onsets: Int
    public var notesPerMinute: Double
    /// Longest silence between consecutive note onsets, in seconds.
    public var longestGap: Double
    /// Most onsets in any 10 s window.
    public var maxIn10s: Int
    /// Shannon entropy of the pitch histogram, in bits (max log2(9) = 3.17).
    public var pitchEntropy: Double
    public var topNoteShare: Double
    public var topThreeShare: Double
    public var meanMidi: Double

    /// Strikes within 30 ms of each other (a double strike) count as one onset.
    public init(events: [HandpanEvent], duration: Double) {
        let sorted = events.sorted { $0.time < $1.time }
        var onsetTimes: [Double] = []
        var counts: [Int: Int] = [:]
        var total = 0, midiSum = 0.0
        for e in sorted {
            counts[e.midi, default: 0] += 1
            total += 1
            midiSum += Double(e.midi)
            if let last = onsetTimes.last, e.time - last < 0.03 { continue }
            onsetTimes.append(e.time)
        }
        onsets = onsetTimes.count
        notesPerMinute = Double(onsets) / max(duration / 60, 1e-9)
        longestGap = zip(onsetTimes, onsetTimes.dropFirst()).map { $1 - $0 }.max() ?? duration
        var best = 0
        var j = 0
        for i in 0..<onsetTimes.count {
            while onsetTimes[i] - onsetTimes[j] >= 10 { j += 1 }
            best = max(best, i - j + 1)
        }
        maxIn10s = best
        let shares = counts.values.map { Double($0) / Double(max(1, total)) }.sorted(by: >)
        pitchEntropy = -shares.reduce(0) { $0 + $1 * log2($1) }
        topNoteShare = shares.first ?? 0
        topThreeShare = shares.prefix(3).reduce(0, +)
        meanMidi = total > 0 ? midiSum / Double(total) : 0
    }
}
