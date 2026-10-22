import Foundation

/// Deterministic, seeded generator of the garden's music. Same seed and same moods give the same notes.
///
/// The music is a chain of phrases. Each phrase is a few melody notes (stepwise, leaps no larger than a fifth,
/// ending on the tonic or the fifth), then a rest of 4 to 12 seconds (measured from one phrase's last note to the
/// next phrase's first). Some phrases (in rain) are three high droplet notes. What plays the melody and what sits
/// under it depends on `GardenMood.theme`:
/// - Japanese: koto, an occasional flute note and a quiet drone of root and fifth (the original sound).
/// - Farm: fingerpicked guitar with a thumb-bass of root and fifth under each phrase.
/// - Rural UK: slow piano melodies in a folk mode over a sustained pad of slowly changing chords.
/// - Urban: sparse electric-piano motifs over a soft pad, with a light slow pulse in calm weather.
public struct MusicComposer: Sendable {
    /// Where the next phrase starts, in seconds from the start of the music.
    public private(set) var cursor: Double

    private var rng: SplitMixRandom
    private var lastNote: Int?
    private var nextDrone: Double
    private var nextPad: Double
    private var nextPulse: Double
    private var pulseCount = 0
    private var lastChord = -1

    /// Drone root D2 and fifth A2, restarted every `droneInterval` seconds, each lasting `droneLength`.
    static let droneInterval = 24.0
    static let droneLength = 28.0

    public init(seed: UInt64, startTime: Double = 0) {
        rng = SplitMixRandom(seed: seed)
        cursor = startTime
        nextDrone = startTime
        nextPad = startTime
        nextPulse = startTime
    }

    /// Generates the next phrase in `mood` (with its flute and drone notes), and moves the cursor past its rest.
    public mutating func nextPhrase(mood: GardenMood) -> [NoteEvent] {
        let style = PhraseStyle(mood)
        let start = cursor
        let droplet = style.dropletChance > 0 && rng.chance(style.dropletChance)
        let pool = droplet ? style.dropletPool : style.melodyPool
        let octave = style.pitchClasses.count // pool entries per octave (5 for the pentatonic Japanese scales)
        let count = droplet ? 3 : rng.int(style.notes)

        // Opening note: near the last melody note (a random spot after droplets), sometimes an octave lower.
        var index: Int
        if droplet || lastNote == nil {
            index = rng.int(0...(pool.count - 1))
        } else {
            index = Self.nearestIndex(in: pool, to: lastNote ?? 67) + rng.int(-1...1)
            index = min(max(index, 0), pool.count - 1)
        }
        if !droplet, index >= octave, rng.chance(0.12) {
            index -= octave
        }

        var indices = [index]
        var direction = rng.chance(0.5) ? 1 : -1
        while indices.count < count {
            index = stepIndex(from: index, pool: pool, direction: &direction)
            indices.append(index)
        }
        if indices.count >= 2 {
            indices[count - 1] = Self.cadenceIndex(pool: pool, last: indices[count - 1], previous: indices[count - 2],
                                                   cadence: style.cadence)
        }

        var events: [NoteEvent] = []
        var onset = start
        var gap = 0.0
        var onsets: [Double] = []
        for (i, poolIndex) in indices.enumerated() {
            if i > 0 {
                gap = rng.range(droplet ? 0.7...1.0 : style.spacing)
                onset += gap
            } else {
                gap = droplet ? 0.85 : style.spacing.lowerBound
            }
            let velocity = rng.range(style.velocity) * (i == 0 ? 1.0 : rng.range(0.85...1.0))
            onsets.append(onset)
            let length = droplet ? style.dropletLength : min(style.noteLength.upperBound,
                                                               max(style.noteLength.lowerBound, gap * style.noteLengthPerGap))
            events.append(NoteEvent(time: onset, midiNote: pool[poolIndex], duration: length,
                                    velocity: min(1, velocity), voice: style.melodyVoice))
        }
        if !droplet {
            lastNote = pool[indices[count - 1]]
        }

        // Occasional flute note, long and soft, somewhere during the phrase.
        if !droplet, style.fluteChance > 0, rng.chance(style.fluteChance) {
            let at = start + rng.range(0.0...max(0.5, onset - start))
            let note = style.fluteNotes[rng.int(0...(style.fluteNotes.count - 1))]
            events.append(NoteEvent(time: at, midiNote: note, duration: rng.range(3.0...6.0),
                                    velocity: rng.range(0.3...0.42), voice: .flute))
        }

        // Thumb-bass (farm): the root under the first note, the fifth under the third when the phrase is long enough.
        if style.thumbBass, !droplet {
            events.append(NoteEvent(time: onsets[0], midiNote: 38, duration: 3.5,
                                    velocity: style.velocity.lowerBound * rng.range(0.7...0.95), voice: .bass))
            if onsets.count >= 5, mood.phase != .night {
                events.append(NoteEvent(time: onsets[2], midiNote: 45, duration: 3.0,
                                        velocity: style.velocity.lowerBound * rng.range(0.6...0.85), voice: .bass))
            }
        }

        // The rest runs from this phrase's last onset to the next phrase's first; style.rest is already within 4...12.
        cursor = onset + rng.range(style.rest)

        // Drone (Japanese): root and fifth, every 24 s, for as long as the music plays.
        if style.drone {
            while nextDrone < cursor {
                events.append(NoteEvent(time: nextDrone, midiNote: 38, duration: Self.droneLength, velocity: 0.5, voice: .drone))
                events.append(NoteEvent(time: nextDrone, midiNote: 45, duration: Self.droneLength, velocity: 0.5, voice: .drone))
                nextDrone += Self.droneInterval
            }
        }

        // Pad (rural UK, urban): a new chord every `padInterval` s, each held `padLength` s so they overlap.
        if let pad = style.pad {
            while nextPad < cursor {
                var chord = rng.int(0...(pad.chords.count - 1))
                if chord == lastChord { chord = (chord + 1) % pad.chords.count }
                lastChord = chord
                for (k, note) in pad.chords[chord].enumerated() {
                    events.append(NoteEvent(time: nextPad + 0.15 * Double(k), midiNote: note, duration: pad.length,
                                            velocity: pad.velocity * rng.range(0.85...1.0), voice: .pad))
                }
                nextPad += pad.interval
            }
        }

        // Pulse (urban): a soft low note on a slow beat, alternating tonic and fifth; none in quiet weather.
        if let pulse = style.pulse {
            while nextPulse < cursor {
                events.append(NoteEvent(time: nextPulse, midiNote: pulseCount % 2 == 0 ? pulse.low : pulse.high,
                                        duration: 1.6, velocity: pulse.velocity * (pulseCount % 4 == 0 ? 1.0 : 0.7),
                                        voice: .bass))
                pulseCount += 1
                nextPulse += pulse.interval
            }
        } else {
            nextPulse = max(nextPulse, cursor)
        }
        return events.sorted { $0.time < $1.time }
    }

    /// The notes of `[startTime, startTime + duration)` for a steady `mood`, from a fresh composer seeded with `seed`.
    /// Pure: the same inputs always give the same events.
    public static func events(mood: GardenMood, from startTime: Double, duration: Double, seed: UInt64) -> [NoteEvent] {
        let end = startTime + duration
        var composer = MusicComposer(seed: seed)
        var all: [NoteEvent] = []
        while composer.cursor < end {
            all += composer.nextPhrase(mood: mood)
        }
        return all
            .filter { $0.time >= startTime && $0.time < end }
            .sorted { $0.time < $1.time }
    }

    // MARK: Melody helpers

    /// A stepwise move (mostly one scale degree, sometimes two or three), never a leap bigger than a fifth.
    private mutating func stepIndex(from index: Int, pool: [Int], direction: inout Int) -> Int {
        if rng.chance(0.3) { direction = -direction }
        let roll = rng.unit()
        let degrees = roll < 0.7 ? 1 : (roll < 0.92 ? 2 : 3)
        for attempt in 0..<2 {
            let dir = attempt == 0 ? direction : -direction
            let target = index + dir * degrees
            if pool.indices.contains(target), abs(pool[target] - pool[index]) <= 7 {
                direction = dir
                return target
            }
        }
        return index
    }

    /// The nearest tonic or fifth to `last` that is at most a fifth away from `previous`.
    private static func cadenceIndex(pool: [Int], last: Int, previous: Int, cadence: [Int]) -> Int {
        var best = last
        var bestDistance = Int.max
        for j in pool.indices where MusicScale.isCadence(pool[j], in: cadence) && abs(pool[j] - pool[previous]) <= 7 {
            let distance = abs(j - last)
            if distance < bestDistance {
                best = j
                bestDistance = distance
            }
        }
        return best
    }

    private static func nearestIndex(in pool: [Int], to midi: Int) -> Int {
        pool.indices.min { abs(pool[$0] - midi) < abs(pool[$1] - midi) } ?? 0
    }
}

/// How busy and how loud the music is for a mood. All ranges are seconds or counts; rests are clamped to 4...12.
/// The weather and time-of-day shaping is shared by every theme; each theme then adjusts it (instrument, scale,
/// register, pace) and adds its own accompaniment.
struct PhraseStyle {
    /// A sustained chord every `interval` seconds, each note held `length` seconds.
    struct Pad {
        let chords: [[Int]]
        let interval: Double
        let length: Double
        let velocity: Double
    }

    /// A soft low note every `interval` seconds, alternating `low` and `high`.
    struct Pulse {
        let low: Int
        let high: Int
        let interval: Double
        let velocity: Double
    }

    let notes: ClosedRange<Int>
    let spacing: ClosedRange<Double>
    let rest: ClosedRange<Double>
    let velocity: ClosedRange<Double>
    let fluteChance: Double
    let dropletChance: Double
    let melodyPool: [Int]
    let dropletPool: [Int]
    let fluteNotes: [Int]

    let pitchClasses: [Int]
    let cadence: [Int]
    let melodyVoice: MusicVoice
    /// A melody note lasts `gap * noteLengthPerGap` seconds, within `noteLength`.
    let noteLength: ClosedRange<Double>
    let noteLengthPerGap: Double
    let dropletLength: Double
    let drone: Bool
    let thumbBass: Bool
    let pad: Pad?
    let pulse: Pulse?

    init(_ mood: GardenMood) {
        let pitchClasses = MusicScale.pitchClasses(for: mood.season, theme: mood.theme)
        var notes = 3...5
        var spacing = 1.0...1.4
        var rest = 5.0...8.0
        var velocity = 0.5...0.8
        var flute = 0.35
        var droplet = 0.0
        var register = 57...81

        switch mood.condition {
        case .clear:
            notes = 3...6; spacing = 0.9...1.3; rest = 4.0...7.0; velocity = 0.55...0.85; flute = 0.4
        case .partlyCloudy:
            break
        case .overcast:
            notes = 3...5; spacing = 1.2...1.6; rest = 7.0...10.0; velocity = 0.45...0.7; flute = 0.3
        case .snow:
            notes = 3...4; spacing = 1.4...1.9; rest = 9.0...12.0; velocity = 0.35...0.55; flute = 0.25
        case .fog:
            notes = 3...3; spacing = 1.6...2.0; rest = 11.0...12.0; velocity = 0.35...0.55; flute = 0.12
        case .drizzle:
            notes = 3...4; spacing = 1.3...1.7; rest = 8.0...11.0; velocity = 0.35...0.55; flute = 0.25; droplet = 0.3
        case .rain:
            notes = 3...4; spacing = 1.4...1.8; rest = 9.0...12.0; velocity = 0.3...0.5; flute = 0.2; droplet = 0.35
        case .thunderstorm:
            notes = 3...4; spacing = 1.4...1.8; rest = 9.0...12.0; velocity = 0.3...0.45; flute = 0.15; droplet = 0.3
        }

        let night = mood.phase == .night
        switch mood.phase {
        case .day:
            break
        case .dawn, .dusk:
            // Warmer and a little slower, with a touch more flute.
            spacing = Self.scaled(spacing, 1.15)
            velocity = Self.scaled(velocity, 1.05)
            flute += 0.15
        case .night:
            // Sparser, lower and softer.
            notes = min(notes.lowerBound, 3)...min(notes.upperBound, 4)
            spacing = Self.scaled(spacing, 1.2)
            rest = Self.scaled(rest, 1.2)
            velocity = Self.scaled(velocity, 0.75)
            flute *= 0.6
            register = 45...69
        }

        // Theme adjustments. Japanese keeps the values above untouched.
        var voice = MusicVoice.koto
        var length = 1.0...2.6
        var perGap = 2.2
        var dropletLength = 0.9
        var thumbBass = false
        var pad: Pad?
        var pulse: Pulse?
        switch mood.theme {
        case .japanese:
            break
        case .farm:
            // Fingerpicked: quicker, closer notes in a guitar's middle register, a thumb-bass under each phrase.
            voice = .pluck
            notes = notes.lowerBound...(notes.upperBound + 1)
            spacing = Self.scaled(spacing, 0.62)
            velocity = Self.scaled(velocity, 0.9)
            register = night ? 47...69 : 55...78
            length = 1.8...3.2; perGap = 3.0; dropletLength = 1.4
            flute = 0
            thumbBass = true
        case .ruralUK:
            // Slow piano with more rest, over a sustained pad.
            voice = .piano
            notes = notes.lowerBound...max(notes.lowerBound, notes.upperBound - 1)
            spacing = Self.scaled(spacing, 1.2)
            rest = Self.scaled(rest, 1.25)
            velocity = Self.scaled(velocity, 0.9)
            register = night ? 48...72 : 55...79
            length = 4.0...7.0; perGap = 4.0; dropletLength = 2.5
            flute = 0
            let warm = mood.season == .spring || mood.season == .summer
            pad = Pad(chords: warm ? [[50, 57, 65], [48, 55, 64], [43, 50, 59], [45, 52, 60]]
                                   : [[50, 57, 65], [48, 55, 64], [46, 53, 62], [43, 50, 58]],
                      interval: 18, length: 24, velocity: night ? 0.4 : (mood.condition == .fog ? 0.45 : 0.55))
        case .urban:
            // Sparse electric-piano motifs, a lower register, calmer at night; a light pulse in settled weather.
            voice = .epiano
            notes = max(2, notes.lowerBound - 1)...max(2, notes.upperBound - 2)
            spacing = Self.scaled(spacing, 1.1)
            rest = Self.scaled(rest, night ? 1.38 : 1.15)
            velocity = Self.scaled(velocity, night ? 0.85 : 1.0)
            register = night ? 43...66 : 52...76
            length = 2.5...5.0; perGap = 3.0; dropletLength = 1.8
            flute = 0
            let warm = mood.season == .spring || mood.season == .summer
            pad = Pad(chords: warm ? [[48, 52, 55, 59], [45, 52, 55, 60], [52, 55, 59, 62], [43, 50, 55, 59]]
                                   : [[48, 51, 55, 58], [51, 55, 58, 62], [46, 50, 53, 58], [43, 50, 53, 58]],
                      interval: 20, length: 26, velocity: night ? 0.35 : 0.45)
            let settled: Bool
            switch mood.condition {
            case .clear, .partlyCloudy, .overcast: settled = true
            default: settled = false
            }
            if settled, !night {
                pulse = Pulse(low: 36, high: 43, interval: 2.8, velocity: 0.3)
            }
        }

        self.notes = notes
        self.spacing = spacing
        let restLow = min(12.0, max(4.0, rest.lowerBound))
        self.rest = restLow...min(12.0, max(restLow, rest.upperBound))
        self.velocity = velocity
        self.fluteChance = flute
        self.dropletChance = droplet
        self.pitchClasses = pitchClasses
        self.cadence = MusicScale.cadence(for: mood.theme)
        self.melodyVoice = voice
        self.noteLength = length
        self.noteLengthPerGap = perGap
        self.dropletLength = dropletLength
        self.drone = mood.theme == .japanese
        self.thumbBass = thumbBass
        self.pad = pad
        self.pulse = pulse
        self.melodyPool = MusicScale.pool(pitchClasses: pitchClasses, range: register)
        self.dropletPool = MusicScale.pool(pitchClasses: pitchClasses, range: 74...86)
        self.fluteNotes = MusicScale.pool(pitchClasses: pitchClasses, range: 62...79)
    }

    private static func scaled(_ r: ClosedRange<Double>, _ factor: Double) -> ClosedRange<Double> {
        (r.lowerBound * factor)...(r.upperBound * factor)
    }
}

/// Small deterministic generator (SplitMix64). Not for anything but the music.
struct SplitMixRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func range(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + (r.upperBound - r.lowerBound) * unit()
    }

    mutating func int(_ r: ClosedRange<Int>) -> Int {
        r.lowerBound + Int(next() % UInt64(r.count))
    }

    mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }
}
