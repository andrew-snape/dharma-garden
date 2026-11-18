import Accelerate
import DharmaGardenCore
import Foundation

// Phase 3 preview renderer for the other garden instruments. Not shipped with the app.
//
//   GardenRender preview --instrument kalimba|piano|musicbox|tines|handpan --out <dir>
//                        [--seed 1] [--minutes 4] [--moods day,dusk,night] [--no-tremolo]
//
// Writes <instrument>-notes.m4a (every scale note, soft then medium), <instrument>-<mood>-excerpt.m4a for each
// mood (60 s from 30% into a 4-minute piece, -24 LUFS, peak at or under -3 dBFS) and <instrument>-spectrogram.png
// of the dry notes, then prints the numbers used for the self-check.

/// Share of the spectral energy above `hz`, from averaged Hann-windowed 8192-point frames of the mono mix.
func shareAbove(_ b: StereoBuffer, hz: Double) -> Double {
    let n = 8192, log2n = 13
    let mono = zip(b.left, b.right).map { 0.5 * ($0 + $1) }
    guard mono.count > n, let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else { return 0 }
    defer { vDSP_destroy_fftsetup(setup) }
    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    let cut = Int(hz / (b.sampleRate / Double(n)))
    var high = 0.0, all = 0.0
    var pos = 0
    while pos + n <= mono.count {
        var frame = [Float](repeating: 0, count: n)
        for i in 0..<n { frame[i] = mono[pos + i] * window[i] }
        var re = [Float](repeating: 0, count: n / 2), im = re
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Forward))
            }
        }
        for k in 1..<(n / 2) {
            let p = Double(re[k] * re[k] + im[k] * im[k])
            all += p
            if k >= cut { high += p }
        }
        pos += n / 2
    }
    return all > 0 ? high / all : 0
}

/// Per-note health check on the dry render: loudest sample, first-sample step (a click shows up here) and an
/// estimate of the broadband decay time from the -5 dB to -25 dB part of the envelope.
func noteReport(dry: StereoBuffer, events: [HandpanEvent], spacing: Double) -> [String] {
    var lines: [String] = []
    let sr = dry.sampleRate
    for e in events {
        let a = Int(e.time * sr), z = min(dry.left.count, a + Int(spacing * sr))
        guard z - a > 4800 else { continue }
        var pk: Float = 0
        for i in a..<z { pk = max(pk, abs(dry.left[i]), abs(dry.right[i])) }
        let step = max(abs(dry.left[a]), abs(dry.right[a]))
        // 20 ms RMS envelope.
        let w = Int(0.02 * sr)
        var env: [Double] = []
        var i = a
        while i + w <= z {
            var s = 0.0
            for j in i..<(i + w) { s += Double(dry.left[j] * dry.left[j] + dry.right[j] * dry.right[j]) }
            env.append(db((s / Double(2 * w)).squareRoot()))
            i += w
        }
        let top = env.max() ?? -120
        let iTop = env.firstIndex(of: top) ?? 0
        var t5: Double?, t25: Double?
        for (k, v) in env.enumerated() where k >= iTop {
            if t5 == nil && v <= top - 5 { t5 = Double(k) * 0.02 }
            if t25 == nil && v <= top - 25 { t25 = Double(k) * 0.02 }
        }
        var t60 = "n/a"
        if let t5, let t25, t25 > t5 { t60 = String(format: "%.1f s", (t25 - t5) * 3) }
        lines.append(String(format: "  midi %d vel %.2f: peak %.1f dBFS, first-sample %.1e, decay(60dB est.) %@",
                            e.midi, e.velocity, db(Double(pk)), Double(step) / Double(max(pk, 1e-9)), t60))
    }
    return lines
}

func runPreview(_ args: [String]) {
    func option(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    guard let outPath = option("--out"), let name = option("--instrument"),
          let instrument = GardenInstrument(rawValue: name) else {
        print("usage: GardenRender preview --instrument \(GardenInstrument.allCases.map(\.rawValue).joined(separator: "|")) --out <dir> [--seed 1] [--minutes 4] [--moods day,dusk,night] [--no-tremolo]")
        exit(2)
    }
    let seed = UInt64(option("--seed") ?? "") ?? 1
    let minutes = Double(option("--minutes") ?? "") ?? 4
    let moods = (option("--moods") ?? "day,dusk,night").split(separator: ",").compactMap { PieceMood(rawValue: String($0)) }
    let out = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let noTremolo = args.contains("--no-tremolo")
    let label = noTremolo ? "\(name)-notremolo" : name

    func renderDry(_ events: [HandpanEvent], duration: Double, seed: UInt64) -> StereoBuffer {
        if instrument == .tines && noTremolo {
            return TinesInstrument.render(events: events, duration: duration, seed: seed, tremolo: 0)
        }
        return instrument.render(events: events, duration: duration, seed: seed)
    }

    // Notes: every scale note soft, then every one at medium strength, 3 s apart.
    var events: [HandpanEvent] = []
    var t = 0.5
    for velocity in [0.3, 0.55] {
        for midi in instrument.notes {
            events.append(HandpanEvent(time: t, midi: midi, velocity: velocity))
            t += 3
        }
    }
    let duration = t + 4
    let dry = renderDry(events, duration: duration, seed: 42)
    var wet = fade(ConvolutionReverb.finish(dry, wet: instrument.wet, lowPassHz: instrument.lowPassHz), out: 1.0)
    // Same loudness rule as the pieces, so the notes files are comparable by ear across instruments.
    let gainDb = min(-24 - integratedLUFS(wet), -3 - db(Double(peak(wet))))
    wet = scaled(wet, byDb: gainDb)
    do {
        try writeM4A(wet, to: out.appendingPathComponent("\(label)-notes.m4a"))
        if !noTremolo { try writeSpectrogram(dry, to: out.appendingPathComponent("\(name)-spectrogram.png")) }
        // The same notes, zoomed to 0-2.5 kHz where the partials actually are.
        if !noTremolo {
            try writeSpectrogram(dry, to: out.appendingPathComponent("\(name)-spectrogram-low.png"), maxHz: 2500)
        }
    } catch { print("write failed: \(error)"); exit(1) }
    func rel(_ x: Double) -> String { String(format: "%.1f dB (%.5f%%)", 10 * log10(max(x, 1e-12)), 100 * x) }
    print("\(name) notes: peak \(String(format: "%.1f", db(Double(peak(wet))))) dBFS, "
          + "\(String(format: "%.1f", integratedLUFS(wet))) LUFS; energy above 3 kHz, dry: \(rel(shareAbove(dry, hz: 3000))), "
          + "with room: \(rel(shareAbove(wet, hz: 3000))); above 2 kHz dry: \(rel(shareAbove(dry, hz: 2000)))")
    if args.contains("--verbose") {
        noteReport(dry: dry, events: events, spacing: 3).forEach { print($0) }
    }

    // Excerpts.
    for mood in moods {
        do {
            let r = try renderOne(mood: mood, seed: seed, minutes: minutes, out: out, instrument: instrument,
                                  excerptName: "\(label)-\(mood.rawValue)-excerpt.m4a", writeFull: false)
            let e = r.entry
            print(String(format: "%@ %@ seed %llu: %d notes (%.1f/min), longest gap %.1f s, %.1f LUFS, peak %.1f dBFS, clipped %@",
                         name, mood.rawValue, seed, e.notes, e.notesPerMinute, e.longestGap, e.loudnessLUFS, e.peakDb,
                         e.clipped ? "YES" : "no"))
        } catch { print("\(mood.rawValue) failed: \(error)") }
    }
}
