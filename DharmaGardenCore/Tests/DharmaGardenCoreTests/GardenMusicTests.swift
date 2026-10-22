import XCTest
@testable import DharmaGardenCore

final class GardenMusicTests: XCTestCase {
    private let clearSpring = GardenMood(phase: .day, condition: .clear, season: .spring, theme: .japanese)
    private let seed: UInt64 = 20_261_020

    private func events(_ mood: GardenMood, seconds: Double = 600, seed: UInt64 = 20_261_020) -> [NoteEvent] {
        MusicComposer.events(mood: mood, from: 0, duration: seconds, seed: seed)
    }

    private func koto(_ all: [NoteEvent]) -> [NoteEvent] {
        all.filter { $0.voice == .koto }.sorted { $0.time < $1.time }
    }

    /// Splits the koto notes into phrases wherever the gap is longer than any gap inside a phrase (max 2.3 s).
    /// The last phrase is dropped: the window may have cut it short.
    private func phrases(_ notes: [NoteEvent]) -> [[NoteEvent]] {
        var result: [[NoteEvent]] = []
        for note in notes {
            if let last = result.last?.last, note.time - last.time > 3.0 {
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

    // MARK: Determinism

    func testSameInputsGiveIdenticalEvents() {
        XCTAssertEqual(events(clearSpring), events(clearSpring))
        let night = GardenMood(phase: .night, condition: .rain, season: .autumn, theme: .japanese)
        XCTAssertEqual(events(night, seed: 7), events(night, seed: 7))
    }

    func testDifferentSeedsGiveDifferentMusic() {
        XCTAssertNotEqual(events(clearSpring, seed: 1), events(clearSpring, seed: 2))
    }

    func testWindowsMatchTheirPartOfTheWholeStream() {
        let whole = events(clearSpring, seconds: 120)
        let window = MusicComposer.events(mood: clearSpring, from: 60, duration: 30, seed: seed)
        XCTAssertEqual(window, whole.filter { $0.time >= 60 && $0.time < 90 })
    }

    // MARK: Scale

    func testNotesBelongToTheSeasonScale() {
        for season in [Season.spring, .summer, .autumn, .winter] {
            let mood = GardenMood(phase: .day, condition: .clear, season: season, theme: .japanese)
            let allowed = Set(MusicScale.pitchClasses(for: season))
            for note in events(mood, seconds: 300) where note.voice != .drone {
                XCTAssertTrue(allowed.contains(pitchClass(note.midiNote)),
                              "\(season) note \(note.midiNote) is outside its scale")
            }
        }
    }

    func testDroneIsRootAndFifthOnly() {
        let drones = events(clearSpring, seconds: 120).filter { $0.voice == .drone }
        XCTAssertFalse(drones.isEmpty)
        XCTAssertEqual(Set(drones.map(\.midiNote)), [38, 45], "D2 and A2")
    }

    func testSeasonChangesTheScale() {
        let spring = events(clearSpring, seconds: 900)
        let autumn = events(GardenMood(phase: .day, condition: .clear, season: .autumn, theme: .japanese), seconds: 900)
        let springClasses = Set(spring.filter { $0.voice != .drone }.map { pitchClass($0.midiNote) })
        let autumnClasses = Set(autumn.filter { $0.voice != .drone }.map { pitchClass($0.midiNote) })
        XCTAssertEqual(springClasses, [2, 4, 7, 9, 11], "Yo: D E G A B")
        XCTAssertEqual(autumnClasses, [2, 4, 5, 9, 10], "Hirajoshi: D E F A B-flat")
        XCTAssertNotEqual(springClasses, autumnClasses)
    }

    // MARK: Phrases and rests

    func testPhrasesHaveThreeToEightNotesAndEndOnTonicOrFifth() {
        let all = phrases(koto(events(clearSpring, seconds: 900)))
        XCTAssertGreaterThan(all.count, 40)
        for phrase in all {
            XCTAssertTrue((3...8).contains(phrase.count), "phrase of \(phrase.count) notes")
            let last = phrase[phrase.count - 1].midiNote
            XCTAssertTrue(MusicScale.isCadence(last), "phrase ends on \(last), not tonic or fifth")
        }
    }

    func testMelodyStepsAreNeverLargerThanAFifth() {
        for mood in [clearSpring, GardenMood(phase: .night, condition: .clear, season: .autumn, theme: .japanese),
                     GardenMood(phase: .dusk, condition: .drizzle, season: .winter, theme: .japanese)] {
            for phrase in phrases(koto(events(mood, seconds: 600))) {
                for (a, b) in zip(phrase, phrase.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(a.midiNote - b.midiNote), 7,
                                             "leap of \(b.midiNote - a.midiNote) semitones in a phrase")
                }
            }
        }
    }

    func testRestsBetweenPhrasesAreFourToTwelveSeconds() {
        let all = phrases(koto(events(clearSpring, seconds: 900)))
        for (prev, next) in zip(all, all.dropFirst()) {
            let rest = next[0].time - prev[prev.count - 1].time
            XCTAssertGreaterThanOrEqual(rest, 4.0 - 1e-9)
            XCTAssertLessThanOrEqual(rest, 12.0 + 1e-9)
        }
    }

    func testFlutePlaysOccasionalLongNotes() {
        let flutes = events(clearSpring, seconds: 900).filter { $0.voice == .flute }
        XCTAssertFalse(flutes.isEmpty)
        for f in flutes {
            XCTAssertTrue((3.0...6.0).contains(f.duration), "flute note of \(f.duration) s")
        }
        XCTAssertLessThan(Double(flutes.count) / 900, 0.1, "flute is occasional, not constant")
    }

    // MARK: Mood

    /// Koto notes per second over ten minutes, for one mood.
    private func density(_ mood: GardenMood) -> Double {
        Double(koto(events(mood, seconds: 600)).count) / 600
    }

    func testDensityFollowsMood() {
        let clear = GardenMood(phase: .day, condition: .clear, season: .spring, theme: .japanese)
        let night = GardenMood(phase: .night, condition: .clear, season: .spring, theme: .japanese)
        let rain = GardenMood(phase: .day, condition: .rain, season: .spring, theme: .japanese)
        let fog = GardenMood(phase: .day, condition: .fog, season: .spring, theme: .japanese)
        let dawn = GardenMood(phase: .dawn, condition: .clear, season: .spring, theme: .japanese)

        XCTAssertLessThan(density(night), density(clear), "night is sparser than day")
        XCTAssertLessThan(density(rain), density(clear), "rain is sparser than a clear day")
        XCTAssertLessThan(density(dawn), density(clear), "dawn is slower than a clear day")
        for other in [clear, night, rain, dawn] {
            XCTAssertLessThan(density(fog), density(other), "fog is the sparsest")
        }
    }

    func testClearDayIsCalmButNeverBusierThanOneNoteEvery1point5Seconds() {
        let rate = density(clearSpring)
        XCTAssertGreaterThan(rate, 0)
        XCTAssertGreaterThanOrEqual(1 / rate, 1.5, "average gap \(1 / rate) s is too busy")
    }

    // MARK: Synth

    func testSynthOutputIsAudibleFiniteBoundedAndClickFree() {
        let rate = 44_100.0
        let frames = Int(20 * rate)
        let notes = events(clearSpring, seconds: 20)
        let samples = GardenSynth.render(events: notes, frames: frames, sampleRate: rate, channels: 2)

        XCTAssertEqual(samples.count, frames * 2)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite }, "NaN or infinity in output")
        let peak = samples.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(peak, 1.0)

        let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        XCTAssertGreaterThan(rms, 0.005, "output is nearly silent")

        // Click check: no large jump between neighbouring samples of one channel, at any note start or anywhere.
        var worst: Float = 0
        for i in 2..<samples.count {
            worst = max(worst, abs(samples[i] - samples[i - 2]))
        }
        XCTAssertLessThan(worst, 0.2, "sample-to-sample jump of \(worst)")

        // And specifically around each note start (first 20 ms).
        for note in notes {
            let start = Int(note.time * rate) * 2
            let end = min(samples.count, start + Int(0.02 * rate) * 2)
            guard start + 2 < samples.count, start >= 2 else { continue }
            for i in max(start, 2)..<end {
                XCTAssertLessThan(abs(samples[i] - samples[i - 2]), 0.2, "click at note start \(note.time) s")
            }
        }
    }

    func testSchedulingOutOfOrderAcrossCallsMatchesOneCall() {
        let rate = 22_050.0
        let a = NoteEvent(time: 0.40, midiNote: 69, duration: 0.3, velocity: 0.8, voice: .koto)
        let b = NoteEvent(time: 0.05, midiNote: 62, duration: 0.3, velocity: 0.8, voice: .koto)
        let c = NoteEvent(time: 0.60, midiNote: 74, duration: 0.3, velocity: 0.8, voice: .koto)
        let frames = Int(rate)
        let once = GardenSynth.render(events: [a, b, c], frames: frames, sampleRate: rate)

        let split = GardenSynth(sampleRate: rate, channels: 2, level: 1)
        split.schedule([c, a])
        split.schedule([b]) // earlier than the queue's last note: must still play first
        var out = [Float](repeating: 0, count: frames * 2)
        out.withUnsafeMutableBufferPointer { split.renderInterleaved(into: $0.baseAddress!, frames: frames) }
        XCTAssertEqual(out, once)
    }

    func testMonoRenderIsAlsoFiniteAndAudible() {
        let samples = GardenSynth.render(events: events(clearSpring, seconds: 10), frames: 10 * 48_000,
                                         sampleRate: 48_000, channels: 1)
        XCTAssertEqual(samples.count, 10 * 48_000)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 1 })
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.01)
    }

    // MARK: Listening file

    /// With MUSIC_WAV_PATH set, writes 30 s of a clear spring day as a stereo 16-bit WAV for the developer to hear.
    func testWriteListeningWavWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["MUSIC_WAV_PATH"], !path.isEmpty else {
            throw XCTSkip("Set MUSIC_WAV_PATH to write a listening file.")
        }
        let rate = 44_100
        let frames = 30 * rate
        let samples = GardenSynth.render(events: events(clearSpring, seconds: 30), frames: frames,
                                         sampleRate: Double(rate), channels: 2)
        try Self.writeWav(samples, sampleRate: rate, channels: 2, to: URL(fileURLWithPath: path))
    }

    private static func writeWav(_ samples: [Float], sampleRate: Int, channels: Int, to url: URL) throws {
        let bitsPerSample = 16
        let dataSize = samples.count * 2
        var data = Data()
        func append(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + dataSize)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(UInt16(channels))
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * channels * bitsPerSample / 8))
        append16(UInt16(channels * bitsPerSample / 8)); append16(UInt16(bitsPerSample))
        append("data"); append32(UInt32(dataSize))
        for s in samples {
            let v = Int16((max(-1, min(1, s)) * 32_767).rounded())
            append16(UInt16(bitPattern: v))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
