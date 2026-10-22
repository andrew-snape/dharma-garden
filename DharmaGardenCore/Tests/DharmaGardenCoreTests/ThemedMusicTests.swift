import XCTest
@testable import DharmaGardenCore

/// Music per garden theme: determinism, scales and registers, voices, pacing, loudness and a click-free theme switch.
final class ThemedMusicTests: XCTestCase {
    private let seed: UInt64 = 20_261_020
    private let themes = GardenTheme.allCases
    private let seasons: [Season] = [.spring, .summer, .autumn, .winter]

    private func mood(_ theme: GardenTheme, phase: SunPhase = .day, _ condition: WeatherCondition = .clear,
                      season: Season = .spring) -> GardenMood {
        GardenMood(phase: phase, condition: condition, season: season, theme: theme)
    }

    private func events(_ mood: GardenMood, seconds: Double = 600, seed: UInt64 = 20_261_020) -> [NoteEvent] {
        MusicComposer.events(mood: mood, from: 0, duration: seconds, seed: seed)
    }

    private func melodyVoice(_ theme: GardenTheme) -> MusicVoice {
        switch theme {
        case .japanese: .koto
        case .farm: .pluck
        case .ruralUK: .piano
        case .urban: .epiano
        }
    }

    private func melody(_ mood: GardenMood, seconds: Double = 600, seed: UInt64 = 20_261_020) -> [NoteEvent] {
        events(mood, seconds: seconds, seed: seed).filter { $0.voice == melodyVoice(mood.theme) }.sorted { $0.time < $1.time }
    }

    /// Splits melody notes into phrases at gaps over 3.3 s (the longest in-phrase gap is under 3 s, rests are 4+).
    private func phrases(_ notes: [NoteEvent]) -> [[NoteEvent]] {
        var result: [[NoteEvent]] = []
        for note in notes {
            if let last = result.last?.last, note.time - last.time > 3.3 {
                result.append([note])
            } else if result.isEmpty {
                result.append([note])
            } else {
                result[result.count - 1].append(note)
            }
        }
        return Array(result.dropLast())
    }

    private func pitchClass(_ midi: Int) -> Int { (midi % 12 + 12) % 12 }

    // MARK: Japanese is today's music

    /// FNV-1a over every field of every event, bit for bit.
    private func fingerprint(_ notes: [NoteEvent]) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for e in notes {
            for s in ["\(e.time.bitPattern)", "\(e.midiNote)", "\(e.duration.bitPattern)", "\(e.velocity.bitPattern)", e.voice.rawValue] {
                for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
            }
        }
        return String(h, radix: 16)
    }

    /// Captured from the composer before the themes existed (seed 20261020, 600 s).
    func testJapaneseOutputEqualsTheOriginalGolden() {
        let golden: [(GardenMood, Int, String)] = [
            (mood(.japanese, phase: .day, .clear, season: .spring), 360, "56f6157694ac5108"),
            (mood(.japanese, phase: .night, .rain, season: .autumn), 190, "e927ebbf989c1b5d"),
            (mood(.japanese, phase: .dusk, .drizzle, season: .winter), 221, "881a22c572884034"),
            (mood(.japanese, phase: .dawn, .fog, season: .summer), 174, "8ec849245e7102d4"),
            (mood(.japanese, phase: .day, .overcast, season: .summer), 253, "af56531a882a1134"),
        ]
        for (m, count, hash) in golden {
            let notes = events(m)
            XCTAssertEqual(notes.count, count, "\(m)")
            XCTAssertEqual(fingerprint(notes), hash, "\(m)")
        }
        // And the opening notes, readable.
        let first = events(mood(.japanese), seconds: 60).prefix(6).map { ($0.midiNote, $0.voice) }
        let expected: [(Int, MusicVoice)] = [(64, .koto), (38, .drone), (45, .drone), (76, .flute), (62, .koto), (57, .koto)]
        XCTAssertEqual(first.map(\.0), expected.map(\.0))
        XCTAssertEqual(first.map(\.1), expected.map(\.1))
    }

    // MARK: Determinism

    func testSameSeedAndThemeGiveIdenticalEventsAndThemesDiffer() {
        for theme in themes {
            XCTAssertEqual(events(mood(theme)), events(mood(theme)), "\(theme)")
            XCTAssertNotEqual(events(mood(theme), seed: 1), events(mood(theme), seed: 2), "\(theme)")
            let window = MusicComposer.events(mood: mood(theme), from: 60, duration: 30, seed: seed)
            XCTAssertEqual(window, events(mood(theme), seconds: 120).filter { $0.time >= 60 && $0.time < 90 }, "\(theme)")
        }
        let sounds = themes.map { fingerprint(events(mood($0))) }
        XCTAssertEqual(Set(sounds).count, themes.count)
    }

    func testEveryMoodComposesWithoutTrapping() {
        let phases: [SunPhase] = [.dawn, .day, .dusk, .night]
        let conditions: [WeatherCondition] = [.clear, .partlyCloudy, .overcast, .snow, .fog, .drizzle, .rain, .thunderstorm]
        for theme in themes {
            for phase in phases {
                for condition in conditions {
                    let notes = events(mood(theme, phase: phase, condition, season: .winter), seconds: 90)
                    XCTAssertFalse(notes.isEmpty, "\(theme) \(phase) \(condition)")
                }
            }
        }
    }

    // MARK: Scale and register

    func testNotesStayInTheThemesScaleForEverySeason() {
        for theme in themes {
            for season in seasons {
                let allowed = Set(MusicScale.pitchClasses(for: season, theme: theme))
                for phase in [SunPhase.day, .night] {
                    for note in events(mood(theme, phase: phase, .partlyCloudy, season: season), seconds: 300) {
                        XCTAssertTrue(allowed.contains(pitchClass(note.midiNote)),
                                      "\(theme) \(season): note \(note.midiNote) (\(note.voice)) is outside the scale")
                    }
                }
            }
        }
    }

    func testScalesAreWhatTheThemesPromise() {
        XCTAssertEqual(MusicScale.pitchClasses(for: .spring, theme: .farm), [2, 4, 6, 9, 11], "D E F# A B")
        XCTAssertEqual(MusicScale.pitchClasses(for: .winter, theme: .farm), [2, 4, 5, 7, 9, 11], "D dorian, no seventh")
        XCTAssertEqual(MusicScale.pitchClasses(for: .summer, theme: .ruralUK), [0, 2, 4, 5, 7, 9, 11], "D dorian")
        XCTAssertEqual(MusicScale.pitchClasses(for: .autumn, theme: .ruralUK), [0, 2, 4, 5, 7, 9, 10], "D aeolian")
        XCTAssertEqual(MusicScale.pitchClasses(for: .spring, theme: .japanese), MusicScale.pitchClasses(for: .spring))
        for theme in themes {
            for season in seasons {
                let scale = Set(MusicScale.pitchClasses(for: season, theme: theme))
                XCTAssertTrue(MusicScale.cadence(for: theme).allSatisfy(scale.contains), "\(theme) \(season)")
            }
        }
    }

    func testRegistersPerTheme() {
        let ranges: [GardenTheme: ClosedRange<Int>] = [.japanese: 45...86, .farm: 47...86, .ruralUK: 48...86, .urban: 43...86]
        for theme in themes {
            for phase in [SunPhase.day, .night] {
                for condition in [WeatherCondition.clear, .rain] {
                    for note in melody(mood(theme, phase: phase, condition, season: .autumn), seconds: 400) {
                        XCTAssertTrue(ranges[theme]!.contains(note.midiNote), "\(theme) \(phase) note \(note.midiNote)")
                    }
                }
            }
        }
        // Urban sits lower than the Japanese koto; night is lower than day.
        func mean(_ m: GardenMood) -> Double {
            let n = melody(m, seconds: 1200).map(\.midiNote)
            return Double(n.reduce(0, +)) / Double(n.count)
        }
        XCTAssertLessThan(mean(mood(.urban)), mean(mood(.japanese)))
        for theme in themes {
            XCTAssertLessThan(mean(mood(theme, phase: .night)), mean(mood(theme)), "\(theme) night is lower")
        }
    }

    // MARK: Voices

    func testVoicesPerTheme() {
        let expected: [GardenTheme: Set<MusicVoice>] = [
            .japanese: [.koto, .flute, .drone],
            .farm: [.pluck, .bass],
            .ruralUK: [.piano, .pad],
            .urban: [.epiano, .pad, .bass],
        ]
        for theme in themes {
            var used = Set<MusicVoice>()
            for m in [mood(theme), mood(theme, .rain, season: .autumn)] {
                used.formUnion(events(m, seconds: 900).map(\.voice))
            }
            XCTAssertEqual(used, expected[theme], "\(theme)")
        }
    }

    func testUrbanPulseIsCalmAtNightAndInBadWeather() {
        func pulses(_ m: GardenMood) -> Int { events(m, seconds: 300).filter { $0.voice == .bass }.count }
        XCTAssertGreaterThan(pulses(mood(.urban)), 50)
        XCTAssertEqual(pulses(mood(.urban, phase: .night)), 0)
        XCTAssertEqual(pulses(mood(.urban, .rain)), 0)
    }

    func testPadChordsOverlapWithoutGaps() {
        for theme in [GardenTheme.ruralUK, .urban] {
            let pads = events(mood(theme), seconds: 400).filter { $0.voice == .pad }
            XCTAssertFalse(pads.isEmpty)
            let starts = Array(Set(pads.map { Int($0.time / 5) })).sorted()
            for (a, b) in zip(starts, starts.dropFirst()) { XCTAssertLessThanOrEqual(b - a, 4, "pad gap in \(theme)") }
            XCTAssertTrue(pads.allSatisfy { (36...65).contains($0.midiNote) })
        }
    }

    // MARK: Phrases

    func testPhrasesEndOnTonicOrFifthWithSteadyLeapsAndRests() {
        for theme in themes {
            for m in [mood(theme), mood(theme, phase: .night, .overcast, season: .winter), mood(theme, .rain, season: .autumn)] {
                let all = phrases(melody(m, seconds: 1200))
                XCTAssertGreaterThan(all.count, 20, "\(theme)")
                for phrase in all {
                    XCTAssertTrue((2...8).contains(phrase.count), "\(theme): phrase of \(phrase.count) notes")
                    XCTAssertTrue(MusicScale.isCadence(phrase[phrase.count - 1].midiNote, in: MusicScale.cadence(for: theme)),
                                  "\(theme) ends on \(phrase[phrase.count - 1].midiNote)")
                    for (a, b) in zip(phrase, phrase.dropFirst()) {
                        XCTAssertLessThanOrEqual(abs(a.midiNote - b.midiNote), 7, "\(theme) leap")
                    }
                }
                for (prev, next) in zip(all, all.dropFirst()) {
                    let rest = next[0].time - prev[prev.count - 1].time
                    XCTAssertGreaterThanOrEqual(rest, 4.0 - 1e-9, "\(theme)")
                    XCTAssertLessThanOrEqual(rest, 12.0 + 1e-9, "\(theme)")
                }
            }
        }
    }

    private func density(_ m: GardenMood) -> Double {
        Double(melody(m, seconds: 3000).count) / 3000
    }

    func testDensityFollowsWeatherAndTimeOfDayInEveryTheme() {
        for theme in themes {
            let clear = mood(theme)
            let night = mood(theme, phase: .night)
            let rain = mood(theme, .rain)
            let fog = mood(theme, .fog)
            let dawn = mood(theme, phase: .dawn)
            XCTAssertLessThan(density(night), density(clear), "\(theme): night is sparser")
            XCTAssertLessThan(density(rain), density(clear), "\(theme): rain is sparser")
            XCTAssertLessThan(density(dawn), density(clear), "\(theme): dawn is slower")
            for other in [clear, night, rain, dawn] {
                XCTAssertLessThan(density(fog), density(other), "\(theme): fog is the sparsest")
            }
            XCTAssertGreaterThanOrEqual(1 / density(clear), 1.0, "\(theme) is too busy")
        }
    }

    func testPacingCharacterOfEachTheme() {
        // Fingerpicked farm notes come quicker than koto; piano and urban are slower and sparser overall.
        XCTAssertGreaterThan(density(mood(.farm)) , density(mood(.ruralUK)))
        XCTAssertLessThan(density(mood(.ruralUK)), density(mood(.japanese)), "UK has more rest")
        XCTAssertLessThan(density(mood(.urban)), density(mood(.japanese)), "urban is sparse")
        func meanRest(_ m: GardenMood) -> Double {
            let all = phrases(melody(m, seconds: 3000))
            let rests = zip(all, all.dropFirst()).map { $1[0].time - $0[$0.count - 1].time }
            return rests.reduce(0, +) / Double(rests.count)
        }
        XCTAssertGreaterThan(meanRest(mood(.ruralUK)), meanRest(mood(.japanese)))
    }

    // MARK: Synth

    private let rate = 44_100.0

    private func render(_ m: GardenMood, seconds: Double = 8) -> [Float] {
        GardenSynth.render(events: events(m, seconds: seconds), frames: Int(seconds * rate), sampleRate: rate, channels: 2)
    }

    private func stats(_ samples: [Float]) -> (peak: Float, rms: Double, dc: Double) {
        let peak = samples.map { abs($0) }.max() ?? 0
        let sum = samples.reduce(0.0) { $0 + Double($1) }
        let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        return (peak, rms, sum / Double(samples.count))
    }

    func testSynthIsAudibleFiniteBoundedAndLoudnessMatchedAcrossThemes() {
        let reference = stats(render(mood(.japanese))).rms
        for theme in themes {
            for (season, phase) in [(Season.spring, SunPhase.day), (.autumn, .night)] {
                do {
                    let samples = render(mood(theme, phase: phase, .partlyCloudy, season: season))
                    XCTAssertTrue(samples.allSatisfy { $0.isFinite }, "\(theme) NaN or infinity")
                    let s = stats(samples)
                    XCTAssertLessThan(s.peak, 0.9, "\(theme) \(season) \(phase) peak \(s.peak) leaves no headroom")
                    XCTAssertGreaterThan(s.rms, 0.01, "\(theme) \(season) \(phase) is nearly silent: \(s.rms)")
                    XCTAssertLessThan(s.rms, 0.2, "\(theme) \(season) \(phase) is too loud: \(s.rms)")
                    XCTAssertLessThan(abs(s.dc), 0.005, "\(theme) DC offset \(s.dc)")
                    if phase == .day {
                        XCTAssertGreaterThan(s.rms, reference * 0.5, "\(theme) \(season) is much quieter than Japanese")
                        XCTAssertLessThan(s.rms, reference * 2, "\(theme) \(season) is much louder than Japanese")
                    }
                }
            }
        }
    }

    func testNoClicksAtNoteStartsOrAnywhereInEveryTheme() {
        for theme in themes {
            let m = mood(theme)
            let notes = events(m, seconds: 12)
            let samples = GardenSynth.render(events: notes, frames: Int(12 * rate), sampleRate: rate, channels: 2)
            var worst: Float = 0
            for i in 2..<samples.count { worst = max(worst, abs(samples[i] - samples[i - 2])) }
            XCTAssertLessThan(worst, 0.2, "\(theme): sample-to-sample jump of \(worst)")
        }
    }

    func testMonoRenderIsFiniteAndAudibleForEveryTheme() {
        for theme in themes {
            let samples = GardenSynth.render(events: events(mood(theme), seconds: 6), frames: 6 * 48_000,
                                             sampleRate: 48_000, channels: 1)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 1 }, "\(theme)")
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.01, "\(theme)")
        }
    }

    func testManyOverlappingNotesStayBoundedAndFinite() {
        // A pile-up well beyond the voice limits: stolen voices must not click through the limiter or go NaN.
        for voice in [MusicVoice.pluck, .bass, .piano, .epiano, .pad] {
            let pile = (0..<40).map { NoteEvent(time: Double($0) * 0.05, midiNote: 40 + $0 % 30, duration: 8, velocity: 1, voice: voice) }
            let samples = GardenSynth.render(events: pile, frames: Int(3 * rate), sampleRate: rate, channels: 2)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 1 }, "\(voice)")
        }
    }

    // MARK: Theme switch

    /// The app's crossfade: fade down, reset, new theme's music from zero, fade up. Offline, with the same calls.
    func testSwitchingThemeMidStreamDoesNotClick() {
        let pairs: [(GardenTheme, GardenTheme)] = [(.japanese, .farm), (.farm, .ruralUK), (.ruralUK, .urban), (.urban, .japanese)]
        for (from, to) in pairs {
            let synth = GardenSynth(sampleRate: rate, channels: 2, level: 1)
            synth.schedule(events(mood(from), seconds: 12))
            var out: [Float] = []
            func run(_ seconds: Double) {
                let frames = Int(seconds * rate)
                var block = [Float](repeating: 0, count: frames * 2)
                block.withUnsafeMutableBufferPointer { synth.renderInterleaved(into: $0.baseAddress!, frames: frames) }
                out += block
            }
            run(7)
            synth.setLevel(0, over: 1.5)
            run(1.6)
            synth.reset()
            synth.schedule(events(mood(to), seconds: 12))
            synth.setLevel(1, over: 1.5)
            run(7)

            XCTAssertTrue(out.allSatisfy { $0.isFinite && abs($0) < 1 })
            var worst: Float = 0
            for i in 2..<out.count { worst = max(worst, abs(out[i] - out[i - 2])) }
            XCTAssertLessThan(worst, 0.2, "\(from) to \(to): jump of \(worst)")
            // The faded region is quiet around the swap and music is audible on both sides.
            let swap = Int(8.6 * rate) * 2
            XCTAssertLessThan(out[(swap - 200)..<(swap + 200)].map { abs($0) }.max() ?? 1, 0.001, "\(from) to \(to)")
            XCTAssertGreaterThan(out[0..<(7 * Int(rate) * 2)].map { abs($0) }.max() ?? 0, 0.02)
            XCTAssertGreaterThan(out[(swap + 2 * Int(rate) * 2)...].map { abs($0) }.max() ?? 0, 0.02)
        }
    }

    func testComposerFollowsAThemeChangeBetweenPhrases() {
        var composer = MusicComposer(seed: seed)
        var all = composer.nextPhrase(mood: mood(.japanese))
        all += composer.nextPhrase(mood: mood(.farm))
        all += composer.nextPhrase(mood: mood(.ruralUK))
        XCTAssertTrue(all.contains { $0.voice == .koto })
        XCTAssertTrue(all.contains { $0.voice == .pluck })
        XCTAssertTrue(all.contains { $0.voice == .piano })
    }

    // MARK: Listening files

    /// With MUSIC_RENDER_DIR set (for example ~/Library/Caches/weeds-renders/music), writes 20 s of each theme in each
    /// season as stereo 16-bit WAVs and checks them numerically: peak, RMS and spectral centroid.
    func testWriteListeningFilesWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["MUSIC_RENDER_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set MUSIC_RENDER_DIR to write listening files.")
        }
        let folder = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        var report: [String] = []
        for theme in themes {
            for season in seasons {
                let m = mood(theme, phase: .day, .partlyCloudy, season: season)
                let samples = render(m, seconds: 20)
                let s = stats(samples)
                let spectrum = Self.spectrum(samples, sampleRate: rate)
                let centroid = spectrum.centroid
                report.append(String(format: "%@ %@: peak %.3f rms %.4f dc %.5f centroid %.0f Hz above 3 kHz %.2f%%",
                                     "\(theme)", "\(season)", s.peak, s.rms, s.dc, centroid, 100 * spectrum.highShare))
                XCTAssertLessThan(s.peak, 0.9)
                XCTAssertTrue((150.0...3500.0).contains(centroid), "\(theme) \(season) centroid \(centroid)")
                try Self.writeWav(samples, sampleRate: Int(rate), to: folder.appendingPathComponent("\(theme)-\(season).wav"))
            }
        }
        let text = "MUSIC RENDER REPORT\n" + report.joined(separator: "\n") + "\n"
        try text.write(to: folder.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    /// Power-weighted mean frequency of the mono mix, and the share of power above 3 kHz (where harshness lives),
    /// over 8192-sample Hann windows (radix-2 FFT).
    private static func spectrum(_ stereo: [Float], sampleRate: Double) -> (centroid: Double, highShare: Double) {
        let n = 8192
        let mono = stride(from: 0, to: stereo.count - 1, by: 2).map { 0.5 * (stereo[$0] + stereo[$0 + 1]) }
        var weighted = 0.0
        var total = 0.0
        var high = 0.0
        var start = 0
        while start + n <= mono.count {
            var re = (0..<n).map { Double(mono[start + $0]) * (0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }
            var im = [Double](repeating: 0, count: n)
            fft(&re, &im)
            for k in 1..<(n / 2) {
                let power = re[k] * re[k] + im[k] * im[k]
                let frequency = Double(k) * sampleRate / Double(n)
                weighted += power * frequency
                total += power
                if frequency > 3000 { high += power }
            }
            start += n * 2
        }
        return total > 0 ? (weighted / total, high / total) : (0, 0)
    }

    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let angle = -2 * Double.pi / Double(len)
            for i in stride(from: 0, to: n, by: len) {
                for k in 0..<(len / 2) {
                    let wr = cos(angle * Double(k)), wi = sin(angle * Double(k))
                    let a = i + k, b = i + k + len / 2
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
            }
            len <<= 1
        }
    }

    private static func writeWav(_ samples: [Float], sampleRate: Int, to url: URL) throws {
        let dataSize = samples.count * 2
        var data = Data()
        func append(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + dataSize)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(2)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 4)); append16(4); append16(16)
        append("data"); append32(UInt32(dataSize))
        for s in samples { append16(UInt16(bitPattern: Int16((max(-1, min(1, s)) * 32_767).rounded()))) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
