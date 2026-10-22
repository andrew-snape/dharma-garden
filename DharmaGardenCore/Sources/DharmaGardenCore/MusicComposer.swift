import Foundation

/// Deterministic, seeded score for the garden's music. Same seed and same moods give the same notes.
///
/// The music moves on a slow, steady beat over a looping chord progression, so the melody and what plays under it
/// always agree. It is written one section at a time, in whole bars: a phrase of two to four bars (chord tones on the
/// strong beats, steps between them, a gentle rise and fall, ending held on the tonic or the fifth), then bars of rest
/// in which the accompaniment carries on. The rest, from a phrase's last note to the next phrase's first, is 4 to 12
/// seconds. In rain some phrases are three high droplet notes instead.
///
/// The weather and the time of day set the tempo, the length of the rests, how busy the phrases are, the register and
/// the loudness. The theme sets the instrument, the metre, the chords and the accompaniment:
/// - Japanese: koto over an unbroken drone of root and fifth; a soft flute sometimes answers in the rest.
/// - Farm: fingerpicked guitar over an alternating thumb-bass that follows the chords.
/// - Rural UK: slow piano in three-time over a legato pad whose chords move to the nearest notes.
/// - Urban: sparse electric-piano motifs over soft seventh chords, with a light bass on the beat in settled weather.
public struct MusicComposer: Sendable {
    /// Where the next phrase starts, in seconds from the start of the music. Always the start of a bar.
    public private(set) var cursor: Double

    private var rng: SplitMixRandom
    private var lastNote: Int?
    /// Bars written so far: picks the chord, so the progression runs on across phrases and rests.
    private var bar = 0
    private var progression = 0
    /// The last pad chord, so the next one moves by the smallest steps.
    private var padVoicing: [Int] = []

    /// Pad chords sit in this range (with the root below them when no bass plays).
    static let padRange = 45...64
    static let bassRange = 36...47

    public init(seed: UInt64, startTime: Double = 0) {
        rng = SplitMixRandom(seed: seed)
        cursor = startTime
    }

    /// Writes the next section in `mood`: a phrase, its accompaniment and the rest after it, and moves the cursor to
    /// the bar after the rest.
    public mutating func nextPhrase(mood: GardenMood) -> [NoteEvent] {
        let style = ScoreStyle(mood)
        let start = cursor
        let beat = style.beat
        let perBar = style.beatsPerBar
        let barLength = beat * Double(perBar)
        let droplet = style.dropletChance > 0 && rng.chance(style.dropletChance)

        // Rhythm, in beats from the start of the section.
        var rhythm: [Double] = []
        var strong: [Bool] = []
        var phraseBars = 1
        if droplet {
            rhythm = [0, 1, 2]
            strong = [true, false, true]
        } else {
            phraseBars = rng.int(style.phraseBars)
            for b in 0..<(phraseBars - 1) {
                var pattern = style.patterns[rng.int(0...(style.patterns.count - 1))]
                if rhythm.count + pattern.count > 6 { pattern = style.patterns[0] }
                if rhythm.count + pattern.count > 6 {
                    // Long enough: the phrase ends in the next bar.
                    phraseBars = b + 1
                    break
                }
                for p in pattern {
                    rhythm.append(Double(b * perBar) + p)
                    strong.append(p == 0 || (perBar == 4 && p == 2))
                }
            }
            let lastBar = Double((phraseBars - 1) * perBar)
            if perBar == 4, rhythm.count < 7, rng.chance(0.4) {
                // A note on the downbeat, then the held note on beat three.
                rhythm += [lastBar, lastBar + 2]
                strong += [true, true]
            } else {
                rhythm.append(lastBar)
                strong.append(true)
            }
        }

        // Whole bars of rest after the phrase, as close as they come to the mood's rest (always 4...12 s).
        let lastOnset = rhythm[rhythm.count - 1] * beat
        let wanted = rng.range(style.rest)
        var sectionBars = phraseBars
        var bestError = Double.infinity
        for bars in phraseBars...(phraseBars + 8) {
            let rest = Double(bars) * barLength - lastOnset
            guard rest >= 4.0, rest <= 12.0 else { continue }
            if abs(rest - wanted) < bestError {
                bestError = abs(rest - wanted)
                sectionBars = bars
            }
        }

        // The chord of each bar. A new progression may begin at the top of each cycle.
        let cycle = style.barsPerChord * 4
        var chords: [[Int]] = []
        for b in 0..<sectionBars {
            let global = bar + b
            if global % cycle == 0 {
                progression = rng.int(0...(style.progressions.count - 1))
            }
            let progressionChords = style.progressions[min(progression, style.progressions.count - 1)]
            chords.append(progressionChords[(global / style.barsPerChord) % progressionChords.count])
        }
        let firstBar = bar
        bar += sectionBars

        // Pitches.
        let pool = droplet ? style.dropletPool : style.melodyPool
        let pitches = melody(count: rhythm.count, strong: strong, chords: rhythm.map { chords[Int($0) / perBar] },
                             pool: pool, droplet: droplet, cadence: style.cadence)
        if !droplet { lastNote = pitches[pitches.count - 1] }

        var events: [NoteEvent] = []
        let rest = Double(sectionBars) * barLength - lastOnset
        let base = rng.range(style.velocity)
        let count = rhythm.count
        for i in 0..<count {
            let last = i == count - 1
            // A touch of human timing inside the phrase; the first and last notes stay on the beat.
            let lilt = (i > 0 && !last) ? rng.range(0...0.025) : 0
            let onset = start + rhythm[i] * beat + lilt
            let length: Double
            if droplet {
                length = style.dropletLength
            } else if last {
                length = min(style.finalLength, rest * 0.85)
            } else {
                let gap = (rhythm[i + 1] - rhythm[i]) * beat
                length = min(style.noteLength.upperBound, max(style.noteLength.lowerBound, gap * style.legato))
            }
            // A soft arch across the phrase, the last note settling a little quieter.
            let position = Double(i) / Double(max(1, count - 1))
            var velocity = base * (0.86 + 0.14 * sin(.pi * position)) * (strong[i] ? 1.0 : 0.92)
            if last { velocity *= 0.9 }
            velocity *= rng.range(0.97...1.03)
            events.append(NoteEvent(time: onset, midiNote: pitches[i], duration: length,
                                    velocity: min(1, velocity), voice: style.melodyVoice))
        }

        let sectionLength = Double(sectionBars) * barLength

        // Japanese: the drone runs unbroken, each section's overlapping the next. The flute answers in the rest.
        if style.drone {
            for note in [38, 45] {
                events.append(NoteEvent(time: start, midiNote: note, duration: sectionLength + 1.5,
                                        velocity: style.accompanimentVelocity, voice: .drone))
            }
        }
        if !droplet, style.fluteChance > 0, rng.chance(style.fluteChance) {
            let at = start + lastOnset + beat * Double(rng.int(1...2))
            let tones = style.fluteNotes.filter { chords[chords.count - 1].contains(Self.pitchClass($0)) }
            let choices = tones.isEmpty ? style.fluteNotes : tones
            let note = choices[rng.int(0...(choices.count - 1))]
            events.append(NoteEvent(time: at, midiNote: note, duration: rng.range(3.0...6.0),
                                    velocity: rng.range(0.3...0.42), voice: .flute))
        }

        for b in 0..<sectionBars {
            let barStart = start + Double(b) * barLength
            let chord = chords[b]
            let root = Self.bassNote(chord[0])
            let other = Self.bassPartner(for: root, chord: chord)

            // Farm thumb-bass, urban bass: root on the downbeat, the chord's fifth (or nearest) on beat three.
            if style.thumbBass || style.pulse {
                let velocity = style.accompanimentVelocity * rng.range(0.92...1.0)
                events.append(NoteEvent(time: barStart, midiNote: root, duration: beat * 1.9,
                                        velocity: velocity, voice: .bass))
                if perBar == 4, !style.night {
                    events.append(NoteEvent(time: barStart + 2 * beat, midiNote: other, duration: beat * 1.9,
                                            velocity: velocity * 0.8, voice: .bass))
                }
            }

            // Pad: a chord at each chord change, held into the next so they overlap without a gap.
            if style.pad, (firstBar + b) % style.barsPerChord == 0 || (b == 0 && padVoicing.isEmpty) {
                let barsLeft = style.barsPerChord - (firstBar + b) % style.barsPerChord
                let length = Double(barsLeft) * barLength + 1.2
                var notes = voiceLead(chord)
                if !style.pulse { notes.insert(root, at: 0) }
                for (k, note) in notes.enumerated() {
                    events.append(NoteEvent(time: barStart + 0.12 * Double(k), midiNote: note, duration: length,
                                            velocity: style.accompanimentVelocity * rng.range(0.9...1.0), voice: .pad))
                }
            }
        }

        cursor = start + sectionLength
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

    // MARK: Melody

    /// The phrase's pitches: it opens on a chord tone near the last phrase's end, climbs towards a high point and
    /// settles, landing on chord tones on the strong beats and stepping between them. No leap is wider than a fifth,
    /// and the last note is the tonic or the fifth (one in the chord when it can be).
    private mutating func melody(count: Int, strong: [Bool], chords: [[Int]], pool: [Int], droplet: Bool,
                                 cadence: [Int]) -> [Int] {
        let peak = max(1, Int((Double(count - 1) * rng.range(0.35...0.7)).rounded()))
        let centre = pool.count / 2
        var index: Int
        if droplet || lastNote == nil {
            index = droplet ? rng.int(0...(pool.count - 1)) : centre + rng.int(-2...1)
        } else {
            index = Self.nearestIndex(in: pool, to: lastNote ?? 67) + rng.int(-1...1)
            // Drift gently back towards the middle of the register.
            if index > centre + 2 { index -= 1 } else if index < centre - 2 { index += 1 }
        }
        index = min(max(index, 0), pool.count - 1)
        // Phrases that begin high fall first and rise to finish; the rest rise first and settle.
        let rising = index <= centre
        index = Self.nearestChordTone(in: pool, around: index, chord: chords[0], within: 2) ?? index

        var result = [pool[index]]
        for i in 1..<count {
            if i == count - 1 {
                index = Self.cadenceIndex(pool: pool, previous: index, cadence: cadence, chord: chords[i])
            } else {
                var direction = (i <= peak) == rising ? 1 : -1
                if index + direction < 0 || index + direction >= pool.count { direction = -direction }
                if strong[i], let target = Self.chordToneStep(in: pool, from: index, direction: direction,
                                                              chord: chords[i]) {
                    index = target
                } else {
                    let degrees = rng.chance(0.18) ? 2 : 1
                    let target = index + direction * degrees
                    if pool.indices.contains(target), abs(pool[target] - pool[index]) <= 7 {
                        index = target
                    } else if pool.indices.contains(index - direction) {
                        index -= direction
                    }
                }
            }
            result.append(pool[index])
        }
        return result
    }

    /// The nearest chord tone one to three scale steps away in `direction` (then the other way), at most a fifth off.
    private static func chordToneStep(in pool: [Int], from index: Int, direction: Int, chord: [Int]) -> Int? {
        for dir in [direction, -direction] {
            for steps in 1...3 {
                let target = index + dir * steps
                guard pool.indices.contains(target), abs(pool[target] - pool[index]) <= 7 else { break }
                if chord.contains(pitchClass(pool[target])) { return target }
            }
        }
        return nil
    }

    private static func nearestChordTone(in pool: [Int], around index: Int, chord: [Int], within: Int) -> Int? {
        for distance in 0...within {
            for target in [index - distance, index + distance] where pool.indices.contains(target) {
                if chord.contains(pitchClass(pool[target])) { return target }
            }
        }
        return nil
    }

    /// The nearest tonic or fifth to the previous note, at most a fifth away, preferring one in the chord.
    private static func cadenceIndex(pool: [Int], previous: Int, cadence: [Int], chord: [Int]) -> Int {
        var best = previous
        var bestScore = Double.infinity
        for j in pool.indices where MusicScale.isCadence(pool[j], in: cadence) && abs(pool[j] - pool[previous]) <= 7 {
            let score = Double(abs(j - previous)) + (chord.contains(pitchClass(pool[j])) ? 0 : 1.5)
            if score < bestScore {
                best = j
                bestScore = score
            }
        }
        return best
    }

    private static func nearestIndex(in pool: [Int], to midi: Int) -> Int {
        pool.indices.min { abs(pool[$0] - midi) < abs(pool[$1] - midi) } ?? 0
    }

    // MARK: Accompaniment

    /// The chord's notes in the pad range, each placed as close as it can be to the last chord's notes.
    private mutating func voiceLead(_ chord: [Int]) -> [Int] {
        let anchors = padVoicing.isEmpty ? [50, 53, 57, 60] : padVoicing
        var notes: [Int] = []
        for pc in chord {
            let candidates = Self.padRange.filter { Self.pitchClass($0) == pc }
            let best = candidates.min { a, b in
                let da = anchors.map { abs($0 - a) }.min() ?? 0
                let db = anchors.map { abs($0 - b) }.min() ?? 0
                return da != db ? da < db : a < b
            }
            if let best { notes.append(best) }
        }
        notes.sort()
        padVoicing = notes
        return notes
    }

    static func bassNote(_ pitchClass: Int) -> Int {
        bassRange.lowerBound + ((pitchClass - bassRange.lowerBound) % 12 + 12) % 12
    }

    /// The chord tone nearest a fifth above the root, for the thumb's second note.
    static func bassPartner(for root: Int, chord: [Int]) -> Int {
        let candidates = (root + 3...root + 9).filter { chord.contains(pitchClass($0)) }
        return candidates.min { abs($0 - root - 7) < abs($1 - root - 7) } ?? root + 12
    }

    static func pitchClass(_ midi: Int) -> Int { (midi % 12 + 12) % 12 }
}

/// How a mood is scored. The weather and time of day shape every theme the same way (tempo, rests, busyness,
/// loudness, register); each theme then sets its own instrument, metre, chords and accompaniment.
struct ScoreStyle {
    let beat: Double
    let beatsPerBar: Int
    let barsPerChord: Int
    let phraseBars: ClosedRange<Int>
    /// Rhythms of one bar, in beats, sparsest first. No gap (to the next bar too) is longer than two beats.
    let patterns: [[Double]]
    let rest: ClosedRange<Double>
    let velocity: ClosedRange<Double>
    /// A melody note lasts its gap to the next note times `legato`, within `noteLength`; the last lasts `finalLength`.
    let legato: Double
    let noteLength: ClosedRange<Double>
    let finalLength: Double
    let dropletChance: Double
    let dropletLength: Double
    let fluteChance: Double
    let melodyVoice: MusicVoice
    let melodyPool: [Int]
    let dropletPool: [Int]
    let fluteNotes: [Int]
    let cadence: [Int]
    /// Chords as pitch classes, root first, four to a progression.
    let progressions: [[[Int]]]
    let drone: Bool
    let thumbBass: Bool
    let pad: Bool
    let pulse: Bool
    let accompanimentVelocity: Double
    let night: Bool

    init(_ mood: GardenMood) {
        let warm = mood.season == .spring || mood.season == .summer
        let night = mood.phase == .night
        let twilight = mood.phase == .dawn || mood.phase == .dusk

        // Weather, shared by every theme.
        var tempo = 1.0
        var rest: ClosedRange<Double>
        var busy: Double
        var velocity: ClosedRange<Double>
        var droplet = 0.0
        var flute: Double
        switch mood.condition {
        case .clear:
            rest = 4.0...6.5; busy = 1.0; velocity = 0.5...0.68; flute = 0.4
        case .partlyCloudy:
            rest = 5.0...8.0; busy = 0.85; velocity = 0.46...0.64; flute = 0.35
        case .overcast:
            tempo = 1.05; rest = 7.0...10.0; busy = 0.6; velocity = 0.42...0.6; flute = 0.3
        case .snow:
            tempo = 1.12; rest = 9.0...12.0; busy = 0.4; velocity = 0.36...0.5; flute = 0.25
        case .fog:
            tempo = 1.2; rest = 11.0...12.0; busy = 0.0; velocity = 0.36...0.5; flute = 0.12
        case .drizzle:
            tempo = 1.08; rest = 8.0...11.0; busy = 0.5; velocity = 0.38...0.52; flute = 0.25; droplet = 0.3
        case .rain:
            tempo = 1.1; rest = 9.0...12.0; busy = 0.4; velocity = 0.34...0.48; flute = 0.2; droplet = 0.35
        case .thunderstorm:
            tempo = 1.1; rest = 9.0...12.0; busy = 0.4; velocity = 0.32...0.46; flute = 0.15; droplet = 0.3
        }

        // Time of day: dawn and dusk a little slower and warmer, night slower, sparser, softer and lower.
        if twilight {
            tempo *= 1.12; rest = Self.scaled(rest, 1.2); busy *= 0.75; velocity = Self.scaled(velocity, 0.95)
            flute += 0.15
        } else if night {
            tempo *= 1.2; rest = Self.scaled(rest, 1.3); busy *= 0.55; velocity = Self.scaled(velocity, 0.8)
            flute *= 0.6
        }

        // Theme.
        var beat: Double
        var perBar = 4
        var phraseBars = 2...3
        var patterns: [[Double]]
        var register: ClosedRange<Int>
        var legato = 1.8
        var noteLength = 1.0...2.6
        var finalLength = 3.0
        var dropletLength = 0.9
        var progressions: [[[Int]]]
        var accompaniment = 0.45
        var thumbBass = false
        var pad = false
        var pulse = false
        switch mood.theme {
        case .japanese:
            beat = 0.95
            patterns = [[0, 2], [0, 2, 3], [0, 1, 2], [0, 1, 2, 3]]
            register = night ? 45...69 : 57...81
            progressions = warm
                ? [[[2, 4, 9], [7, 11, 2], [4, 9, 11], [9, 2, 4]], [[2, 4, 9], [11, 4, 7], [7, 11, 2], [9, 2, 4]]]
                : [[[2, 5, 9], [10, 2, 5], [2, 5, 9], [9, 2, 4]], [[2, 9, 4], [10, 2, 5], [5, 9, 2], [9, 2, 4]]]
            accompaniment = night ? 0.4 : 0.48
        case .farm:
            // Fingerpicked: quicker notes in a guitar's middle register, a thumb-bass on every bar.
            beat = 0.68
            patterns = [[0, 2], [0, 1, 2], [0, 2, 3], [0, 1, 2, 3], [0, 0.5, 1, 2], [0, 1, 2, 2.5, 3]]
            register = night ? 47...69 : 55...78
            legato = 2.2; noteLength = 1.4...3.0; finalLength = 3.2; dropletLength = 1.4
            velocity = Self.scaled(velocity, 0.92)
            rest = Self.scaled(rest, 0.95)
            progressions = warm
                ? [[[2, 6, 9], [11, 2, 6], [4, 9, 11], [9, 2, 4]], [[2, 6, 9], [9, 11, 4], [11, 2, 6], [2, 6, 9]]]
                : [[[2, 5, 9], [7, 11, 2], [2, 5, 9], [4, 7, 11]], [[2, 5, 9], [5, 9, 2], [7, 11, 2], [9, 2, 4]]]
            thumbBass = true
            accompaniment = night ? 0.3 : 0.36
            flute = 0
        case .ruralUK:
            // Slow piano in three-time with long rests, over a legato pad.
            beat = 1.1
            perBar = 3
            phraseBars = 2...3
            patterns = [[0, 2], [0, 1], [0, 2, 2.5], [0, 1, 2]]
            register = night ? 48...72 : 55...79
            legato = 2.6; noteLength = 2.5...5.0; finalLength = 5.5; dropletLength = 2.5
            velocity = Self.scaled(velocity, 0.92)
            rest = Self.scaled(rest, 1.4)
            progressions = warm
                ? [[[2, 5, 9], [0, 4, 7], [7, 11, 2], [2, 5, 9]], [[2, 5, 9], [5, 9, 0], [0, 4, 7], [9, 0, 4]]]
                : [[[2, 5, 9], [10, 2, 5], [5, 9, 0], [0, 4, 7]], [[2, 5, 9], [7, 10, 2], [10, 2, 5], [9, 0, 4]]]
            pad = true
            accompaniment = night ? 0.36 : (mood.condition == .fog ? 0.4 : 0.46)
            flute = 0
        case .urban:
            // Sparse electric-piano motifs over soft seventh chords; a light bass on the beat in settled weather.
            beat = 0.9
            phraseBars = 2...2
            patterns = [[0, 2], [0, 1.5, 2.5], [0, 2, 3], [0, 1.5, 2]]
            register = night ? 43...66 : 52...76
            legato = 2.0; noteLength = 2.0...4.5; finalLength = 4.5; dropletLength = 1.8
            rest = Self.scaled(rest, night ? 1.3 : 1.15)
            progressions = warm
                ? [[[0, 4, 7, 11], [9, 0, 4, 7], [4, 7, 11, 2], [7, 11, 2, 4]],
                   [[0, 4, 11, 2], [4, 7, 11, 2], [9, 0, 4, 11], [7, 0, 2, 4]]]
                : [[[0, 3, 7, 10], [3, 7, 10, 2], [5, 10, 0, 3], [10, 2, 5, 7]],
                   [[0, 3, 7, 10], [7, 10, 2, 5], [3, 7, 10, 2], [5, 10, 0, 3]]]
            pad = true
            switch mood.condition {
            case .clear, .partlyCloudy, .overcast: pulse = !night
            default: pulse = false
            }
            accompaniment = night ? 0.32 : 0.4
            flute = 0
        }

        // Calmer weather keeps only the sparser rhythms; fog and night also keep phrases short.
        let keep = max(1, Int((Double(patterns.count) * (0.35 + 0.65 * busy)).rounded()))
        patterns = Array(patterns.prefix(keep))
        if busy == 0 {
            phraseBars = phraseBars.lowerBound...phraseBars.lowerBound
        } else if busy < 0.5 {
            phraseBars = phraseBars.lowerBound...max(phraseBars.lowerBound, phraseBars.upperBound - 1)
        }

        let pitchClasses = MusicScale.pitchClasses(for: mood.season, theme: mood.theme)
        self.beat = min(1.4, beat * tempo)
        self.beatsPerBar = perBar
        self.barsPerChord = 2
        self.phraseBars = phraseBars
        self.patterns = patterns
        let restLow = min(12.0, max(4.0, rest.lowerBound))
        self.rest = restLow...min(12.0, max(restLow, rest.upperBound))
        self.velocity = velocity
        self.legato = legato
        self.noteLength = noteLength
        self.finalLength = finalLength
        self.dropletChance = droplet
        self.dropletLength = dropletLength
        self.fluteChance = mood.theme == .japanese ? flute : 0
        self.melodyVoice = switch mood.theme {
        case .japanese: .koto
        case .farm: .pluck
        case .ruralUK: .piano
        case .urban: .epiano
        }
        self.melodyPool = MusicScale.pool(pitchClasses: pitchClasses, range: register)
        self.dropletPool = MusicScale.pool(pitchClasses: pitchClasses, range: 74...86)
        self.fluteNotes = MusicScale.pool(pitchClasses: pitchClasses, range: 62...79)
        self.cadence = MusicScale.cadence(for: mood.theme)
        self.progressions = progressions
        self.drone = mood.theme == .japanese
        self.thumbBass = thumbBass
        self.pad = pad
        self.pulse = pulse
        self.accompanimentVelocity = accompaniment
        self.night = night
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
