import AVFoundation
import DharmaGardenCore
import Foundation

// Garden-note one-shots for the app. Not shipped with the app.
//
//   GardenRender notes --out <dir> [--calibrate <dir of piece .m4a files>] [--peak-db <dB>]
//
// Each of the 9 scale notes is rendered at two strengths (0.25 "soft", 0.5 "medium") through the same
// ModalInstrument and ConvolutionReverb.finish as the pieces. All 18 are rendered in ONE buffer and finished in
// one call, so they share a single gain: a soft note stays softer than a medium one, and the notes keep their
// natural level relative to each other. `peakDb` sets that shared gain.

/// The shared `peakDb` for `ConvolutionReverb.finish`, found with `--calibrate` against the approved pieces so a
/// soft note heard alone sits at the level of the pieces' quiet passages.
private let defaultNotesPeakDb = -5.6

private let noteStrengths: [(name: String, velocity: Double)] = [("soft", 0.25), ("medium", 0.5)]
/// The room between notes in the single render. Longer than the longest tail we keep (7 s).
private let noteSpacing = 10.0
private let maxNoteSeconds = 7.0
private let tailFloorDb = -60.0

private func readPiece(_ url: URL) throws -> StereoBuffer {
    let file = try AVAudioFile(forReading: url)
    guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw CocoaError(.fileReadUnknown)
    }
    try file.read(into: buf)
    let n = Int(buf.frameLength), channels = Int(buf.format.channelCount)
    let l = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: n))
    let r = channels > 1 ? Array(UnsafeBufferPointer(start: buf.floatChannelData![1], count: n)) : l
    return StereoBuffer(left: l, right: r, sampleRate: file.processingFormat.sampleRate)
}

private func slice(_ b: StereoBuffer, from: Int, to: Int) -> StereoBuffer {
    let a = max(0, min(b.left.count, from)), e = max(a, min(b.left.count, to))
    return StereoBuffer(left: Array(b.left[a..<e]), right: Array(b.right[a..<e]), sampleRate: b.sampleRate)
}

/// Short-term loudness (3 s windows, 1 s hop) of every window that is not silence.
private func shortTermLoudness(_ b: StereoBuffer) -> [Double] {
    let win = Int(3 * b.sampleRate), hop = Int(b.sampleRate)
    var out: [Double] = []
    var start = 0
    while start + win <= b.left.count {
        let l = integratedLUFS(slice(b, from: start, to: start + win))
        if l > -60 { out.append(l) }
        start += hop
    }
    return out
}

/// AAC in an .m4a, 96 kbps stereo.
private func writeNote(_ b: StereoBuffer, to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: b.sampleRate,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 96_000,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(b.left.count)) else { return }
    buf.frameLength = AVAudioFrameCount(b.left.count)
    for i in 0..<b.left.count {
        buf.floatChannelData![0][i] = b.left[i]
        buf.floatChannelData![1][i] = b.right[i]
    }
    try file.write(from: buf)
}

/// Cuts a note where its tail first falls under -60 dBFS (peak over 20 ms), at most 7 s, with a short fade.
private func trimmed(_ note: StereoBuffer) -> StereoBuffer {
    let rate = note.sampleRate
    let window = Int(0.02 * rate)
    let floor = Float(pow(10, tailFloorDb / 20))
    var peakIndex = 0
    var best: Float = 0
    for i in 0..<note.left.count where max(abs(note.left[i]), abs(note.right[i])) > best {
        best = max(abs(note.left[i]), abs(note.right[i])); peakIndex = i
    }
    var end = min(note.left.count, Int(maxNoteSeconds * rate))
    var i = peakIndex
    while i + window <= end {
        var m: Float = 0
        for k in i..<(i + window) { m = max(m, abs(note.left[k]), abs(note.right[k])) }
        if m < floor { end = i + window; break }
        i += window
    }
    var out = slice(note, from: 0, to: end)
    let fadeN = min(out.left.count, Int(0.4 * rate))
    for k in 0..<fadeN {
        let g = Float(0.5 + 0.5 * cos(Double.pi * Double(k) / Double(fadeN)))
        out.left[out.left.count - fadeN + k] *= g
        out.right[out.right.count - fadeN + k] *= g
    }
    return out
}

func runNotes(_ args: [String]) {
    func option(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    guard let outPath = option("--out") else {
        print("usage: GardenRender notes --out <dir> [--instrument handpan] [--calibrate <dir of piece .m4a files>] [--peak-db <dB>]")
        exit(2)
    }
    let out = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let rate = ModalInstrument.defaultSampleRate
    guard let instrument = GardenInstrument(rawValue: option("--instrument") ?? "handpan") else {
        print("unknown instrument"); exit(2)
    }
    let scale = instrument.gardenNotes
    func finish(_ b: StereoBuffer, peakDb: Double) -> StereoBuffer {
        ConvolutionReverb.finish(b, wet: instrument.wet, lowPassHz: instrument.lowPassHz, peakDb: peakDb)
    }

    // One buffer holding all 18 notes, one strike every 10 s. The piece renders use instrument seed 42.
    var events: [HandpanEvent] = []
    var slots: [(index: Int, name: String)] = []
    for strength in noteStrengths {
        for degree in 0..<scale.count {
            let time = 0.5 + Double(events.count) * noteSpacing
            events.append(HandpanEvent(time: time, midi: scale[degree], velocity: strength.velocity))
            slots.append((degree, strength.name))
        }
    }
    let total = 0.5 + Double(events.count) * noteSpacing + 1
    let dry = instrument.render(events: events, duration: total, seed: 42)

    func window(of buf: StereoBuffer, _ slot: Int) -> StereoBuffer {
        let a = Int(events[slot].time * rate)
        return slice(buf, from: a, to: a + Int((maxNoteSeconds + 0.5) * rate))
    }

    var peakDb = Double(option("--peak-db") ?? "") ?? defaultNotesPeakDb
    if let piecesPath = option("--calibrate") {
        // The pieces' quiet passages: the 20th percentile of their short-term loudness, averaged over the pieces.
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: piecesPath)) ?? [])
            .filter { $0.hasSuffix(".m4a") && !$0.contains("excerpt") }.sorted()
        var quiet: [Double] = []
        for f in files {
            guard let piece = try? readPiece(URL(fileURLWithPath: piecesPath).appendingPathComponent(f)) else { continue }
            let levels = shortTermLoudness(piece).sorted()
            guard !levels.isEmpty else { continue }
            quiet.append(levels[levels.count / 5])
        }
        let target = quiet.reduce(0, +) / Double(max(1, quiet.count))
        // Trial render at -3 dBFS, measure the soft notes' loudness over their first 3 s, and move the gain.
        let trial = finish(dry, peakDb: -3)
        let soft = slots.indices.filter { slots[$0].name == "soft" }
        let softLevels = soft.map { integratedLUFS(slice(window(of: trial, $0), from: 0, to: Int(3 * rate))) }
        let mean = softLevels.reduce(0, +) / Double(softLevels.count)
        peakDb = -3 + (target - mean)
        print(String(format: "pieces: %d, quiet passages (p20 short-term) %.1f LUFS; soft notes at -3 dB peak: %.1f LUFS; -> peakDb %.1f",
                     files.count, target, mean, peakDb))
    }
    precondition(peakDb <= -3, "notes must leave headroom")

    let mix = finish(dry, peakDb: peakDb)
    var summary = "note        seconds  peak dBFS  3 s LUFS\n"
    for (slot, info) in slots.enumerated() {
        let note = trimmed(window(of: mix, slot))
        let name = "\(instrument.noteFilePrefix)-\(info.index)-\(info.name)"
        do { try writeNote(note, to: out.appendingPathComponent("\(name).m4a")) } catch { print("\(name) failed: \(error)"); exit(1) }
        summary += String(format: "%-11@ %6.2f  %9.1f  %8.1f\n", name as NSString, Double(note.left.count) / rate,
                          db(Double(peak(note))), integratedLUFS(slice(note, from: 0, to: min(note.left.count, Int(3 * rate)))))
    }
    print(summary)
    print(String(format: "shared peakDb %.1f; wrote 18 notes to %@", peakDb, out.path))
}
