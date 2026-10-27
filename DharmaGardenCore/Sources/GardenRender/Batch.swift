import Accelerate
import AVFoundation
import CoreGraphics
import CoreText
import DharmaGardenCore
import Foundation
import ImageIO

// Batch candidate renderer for the improviser. Not shipped with the app.
//
//   GardenRender batch --out <dir> [--count 20] [--minutes 4] [--moods dawn,day,dusk,night,rain] [--start-seed 1]
//
// `--count` is the total number of pieces, shared round-robin across the moods, so 20 pieces over 5 moods is
// 4 per mood with seeds start-seed ..< start-seed+4. Pieces are independent pure functions of (mood, seed), so
// they are rendered in parallel; the sound code is untouched.

// MARK: Results

struct BatchEntry: Codable {
    var name: String
    var mood: String
    var seed: UInt64
    var minutes: Double
    var notes: Int
    var notesPerMinute: Double
    var longestGap: Double
    var maxIn10s: Int
    var pitchEntropy: Double
    var topNoteShare: Double
    var topThreeShare: Double
    var meanMidi: Double
    var peakDb: Double
    var loudnessLUFS: Double
    var gainAppliedDb: Double
    var clipped: Bool
    var accepted: Bool
    var rejectReasons: [String]
    var renderSeconds: Double
    var file: String
    var excerpt: String
}

struct Rendered {
    var entry: BatchEntry
    var envelope: [Float]          // 0...1 per contact-sheet column
    var onsets: [(time: Double, degree: Int)]
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Rendered?]
    init(count: Int) { items = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ r: Rendered) { lock.lock(); items[i] = r; lock.unlock() }
    var all: [Rendered] { items.compactMap { $0 } }
}

// MARK: Audio helpers

private let targetLUFS = -24.0
private let peakCeilingDb = -3.0

func peak(_ b: StereoBuffer) -> Float {
    var p: Float = 0
    for i in 0..<b.left.count { p = max(p, abs(b.left[i]), abs(b.right[i])) }
    return p
}

func db(_ x: Double) -> Double { 20 * log10(max(x, 1e-9)) }

func fadeInOut(_ b: StereoBuffer, fadeIn: Double, fadeOut: Double) -> StereoBuffer {
    var b = b
    let n = b.left.count
    let inN = min(n, Int(fadeIn * b.sampleRate)), outN = min(n, Int(fadeOut * b.sampleRate))
    for i in 0..<inN {
        let g = Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(inN)))
        b.left[i] *= g; b.right[i] *= g
    }
    for i in 0..<outN {
        let g = Float(0.5 + 0.5 * cos(Double.pi * Double(i) / Double(outN)))
        b.left[n - outN + i] *= g; b.right[n - outN + i] *= g
    }
    return b
}

func scaled(_ b: StereoBuffer, byDb gainDb: Double) -> StereoBuffer {
    var b = b
    var g = Float(pow(10, gainDb / 20))
    b.left.withUnsafeMutableBufferPointer { vDSP_vsmul($0.baseAddress!, 1, &g, $0.baseAddress!, 1, vDSP_Length($0.count)) }
    b.right.withUnsafeMutableBufferPointer { vDSP_vsmul($0.baseAddress!, 1, &g, $0.baseAddress!, 1, vDSP_Length($0.count)) }
    return b
}

/// Integrated loudness in LUFS following ITU-R BS.1770-4: K-weighting (a high shelf and a 38 Hz high-pass,
/// coefficients for 48 kHz), 400 ms blocks every 100 ms, an absolute gate at -70 LUFS and a relative gate 10 LU
/// below the gated mean. Exact for 48 kHz audio, which is all we render.
func integratedLUFS(_ b: StereoBuffer) -> Double {
    func biquad(_ x: [Float], _ bb: [Double], _ aa: [Double]) -> [Float] {
        var out = [Float](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let xi = Double(x[i])
            let y = bb[0] * xi + bb[1] * x1 + bb[2] * x2 - aa[0] * y1 - aa[1] * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = y
            out[i] = Float(y)
        }
        return out
    }
    func kWeight(_ x: [Float]) -> [Float] {
        let shelf = biquad(x, [1.53512485958697, -2.69169618940638, 1.19839281085285],
                           [-1.69065929318241, 0.73248077421585])
        return biquad(shelf, [1.0, -2.0, 1.0], [-1.99004745483398, 0.99007225036621])
    }
    let block = Int(0.4 * b.sampleRate), hop = Int(0.1 * b.sampleRate)
    guard b.left.count > block else { return -70 }
    let l = kWeight(b.left), r = kWeight(b.right)
    var prefix = [Double](repeating: 0, count: l.count + 1)
    for i in 0..<l.count { prefix[i + 1] = prefix[i] + Double(l[i] * l[i]) + Double(r[i] * r[i]) }
    var means: [Double] = []
    var start = 0
    while start + block <= l.count {
        means.append((prefix[start + block] - prefix[start]) / Double(block))
        start += hop
    }
    func lufs(_ ms: Double) -> Double { -0.691 + 10 * log10(max(ms, 1e-12)) }
    let absolute = means.filter { lufs($0) > -70 }
    guard !absolute.isEmpty else { return -70 }
    let relativeGate = lufs(absolute.reduce(0, +) / Double(absolute.count)) - 10
    let gated = absolute.filter { lufs($0) > relativeGate }
    guard !gated.isEmpty else { return -70 }
    return lufs(gated.reduce(0, +) / Double(gated.count))
}

func slice(_ b: StereoBuffer, from: Double, seconds: Double) -> StereoBuffer {
    let a = max(0, min(b.left.count, Int(from * b.sampleRate)))
    let e = max(a, min(b.left.count, a + Int(seconds * b.sampleRate)))
    return StereoBuffer(left: Array(b.left[a..<e]), right: Array(b.right[a..<e]), sampleRate: b.sampleRate)
}

/// AAC in an .m4a container, 128 kbps stereo.
func writeM4A(_ b: StereoBuffer, to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: b.sampleRate,
        AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let chunk = 48_000
    var pos = 0
    while pos < b.left.count {
        let n = min(chunk, b.left.count - pos)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        for i in 0..<n {
            buf.floatChannelData![0][i] = b.left[pos + i]
            buf.floatChannelData![1][i] = b.right[pos + i]
        }
        try file.write(from: buf)
        pos += n
    }
}

// MARK: One piece

private let sheetColumns = 1260

/// `instrument`, `excerptName` and `writeFull` exist for `GardenRender preview`; the defaults are the handpan batch
/// exactly as before.
func renderOne(mood: PieceMood, seed: UInt64, minutes: Double, out: URL,
                       instrument: GardenInstrument = .handpan, excerptName: String? = nil,
                       writeFull: Bool = true) throws -> Rendered {
    let began = Date()
    let duration = minutes * 60
    let events = Improviser.piece(mood: mood, seed: seed, minutes: minutes, scale: instrument.pieceScale)
    let metrics = PieceMetrics(events: events, duration: duration)

    // The approved instrument and room, exactly as the earlier previews used them (instrument seed 42).
    let dry = instrument.render(events: events, duration: duration, seed: 42)
    let clipped = peak(dry) >= 1
    var mix = fadeInOut(ConvolutionReverb.finish(dry, wet: instrument.wet, lowPassHz: instrument.lowPassHz), fadeIn: 4, fadeOut: 8)

    // Loudness: aim for -24 LUFS, but never let the peak pass -3 dBFS. Sparse music is peaky, so the ceiling
    // usually wins and the real figure (reported) sits a little under the target.
    let lufsBefore = integratedLUFS(mix)
    let peakBefore = db(Double(peak(mix)))
    let gainDb = min(targetLUFS - lufsBefore, peakCeilingDb - peakBefore)
    mix = scaled(mix, byDb: gainDb)
    let lufs = integratedLUFS(mix)
    let peakDb = db(Double(peak(mix)))

    let name = "\(mood.rawValue)-\(seed)"
    if writeFull { try writeM4A(mix, to: out.appendingPathComponent("\(name).m4a")) }

    var excerpt = slice(mix, from: min(0.30 * duration, max(0, duration - 60)), seconds: 60)
    excerpt = fadeInOut(excerpt, fadeIn: 2, fadeOut: 2)
    try writeM4A(excerpt, to: out.appendingPathComponent(excerptName ?? "\(name)-excerpt.m4a"))

    // First-cut filter.
    var reasons: [String] = []
    if clipped { reasons.append("clipping") }
    if metrics.maxIn10s > 12 { reasons.append("too dense (\(metrics.maxIn10s) notes in 10 s)") }
    let gapLimit = mood == .night ? 30.0 : 20.0
    if metrics.longestGap > gapLimit { reasons.append(String(format: "dead gap %.0f s", metrics.longestGap)) }
    if metrics.topNoteShare > 0.30 { reasons.append(String(format: "monotonous (one note %.0f%%)", metrics.topNoteShare * 100)) }

    // Contact-sheet thumbnail: RMS per column in dB, -60...-6 mapped to 0...1.
    let per = max(1, mix.left.count / sheetColumns)
    var envelope = [Float](repeating: 0, count: sheetColumns)
    for c in 0..<sheetColumns {
        let a = c * per, e = min(mix.left.count, a + per)
        guard a < e else { continue }
        var s = 0.0
        for i in a..<e { s += Double(mix.left[i] * mix.left[i] + mix.right[i] * mix.right[i]) }
        let v = db((s / Double(2 * (e - a))).squareRoot())
        envelope[c] = Float(min(1, max(0, (v + 60) / 54)))
    }
    let onsets = events.map { (time: $0.time, degree: instrument.notes.firstIndex(of: $0.midi) ?? 0) }

    let entry = BatchEntry(
        name: name, mood: mood.rawValue, seed: seed, minutes: minutes, notes: metrics.onsets,
        notesPerMinute: metrics.notesPerMinute, longestGap: metrics.longestGap, maxIn10s: metrics.maxIn10s,
        pitchEntropy: metrics.pitchEntropy, topNoteShare: metrics.topNoteShare,
        topThreeShare: metrics.topThreeShare, meanMidi: metrics.meanMidi, peakDb: peakDb, loudnessLUFS: lufs,
        gainAppliedDb: gainDb, clipped: clipped, accepted: reasons.isEmpty, rejectReasons: reasons,
        renderSeconds: Date().timeIntervalSince(began), file: "\(name).m4a", excerpt: "\(name)-excerpt.m4a")
    return Rendered(entry: entry, envelope: envelope, onsets: onsets)
}

// MARK: Contact sheet

private func writeContactSheet(_ items: [Rendered], to url: URL) {
    let width = 1560, labelW = 250, rowH = 92, pad = 14, header = 36
    let height = header + items.count * rowH + pad
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }
    func text(_ s: String, x: Double, y: Double, size: CGFloat, color c: CGColor) {
        let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: c]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs as [NSAttributedString.Key: Any]))
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
    ctx.setFillColor(color(0.07, 0.08, 0.1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    text("envelope = loudness over the piece (dB);  strip below = note onsets, low notes at the bottom",
         x: 12, y: Double(height - 24), size: 12, color: color(0.6, 0.65, 0.7))

    let hues: [String: (Double, Double, Double)] = [
        "dawn": (1.0, 0.72, 0.45), "day": (1.0, 0.9, 0.45), "dusk": (0.85, 0.55, 0.9),
        "night": (0.5, 0.6, 1.0), "rain": (0.45, 0.85, 0.9),
    ]
    let plotX = Double(labelW), plotW = Double(width - labelW - 14)
    for (row, item) in items.enumerated() {
        let e = item.entry
        let top = Double(height - header - row * rowH)       // CG origin is bottom-left
        let bottom = top - Double(rowH) + 6
        ctx.setFillColor(row % 2 == 0 ? color(0.1, 0.11, 0.14) : color(0.08, 0.09, 0.12))
        ctx.fill(CGRect(x: 0, y: bottom - 3, width: Double(width), height: Double(rowH)))
        let h = hues[e.mood] ?? (0.8, 0.8, 0.8)
        let label = e.accepted ? color(h.0, h.1, h.2) : color(1, 0.35, 0.3)
        text("\(e.mood) \(e.seed)", x: 12, y: top - 22, size: 17, color: label)
        text(String(format: "%.0f notes/min  gap %.0fs", e.notesPerMinute, e.longestGap), x: 12, y: top - 40, size: 11,
             color: color(0.75, 0.78, 0.82))
        text(String(format: "%.1f LUFS  mean MIDI %.1f", e.loudnessLUFS, e.meanMidi), x: 12, y: top - 55, size: 11,
             color: color(0.75, 0.78, 0.82))
        text(e.accepted ? "ok" : "REJECT: " + (e.rejectReasons.first ?? ""), x: 12, y: top - 70, size: 11, color: label)

        // Envelope.
        let envBase = bottom + 26, envH = Double(rowH) - 40
        ctx.setFillColor(color(h.0, h.1, h.2, 0.8))
        let colW = plotW / Double(item.envelope.count)
        for (c, v) in item.envelope.enumerated() where v > 0 {
            ctx.fill(CGRect(x: plotX + Double(c) * colW, y: envBase, width: max(1, colW), height: Double(v) * envH))
        }
        // Onset strip.
        ctx.setFillColor(color(0, 0, 0, 0.35))
        ctx.fill(CGRect(x: plotX, y: bottom, width: plotW, height: 22))
        ctx.setFillColor(color(1, 1, 1, 0.9))
        let duration = e.minutes * 60
        for o in item.onsets {
            ctx.fill(CGRect(x: plotX + o.time / duration * plotW, y: bottom + 1 + Double(o.degree) * 2.3, width: 2, height: 2.6))
        }
    }
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: Entry point

func runBatch(_ args: [String]) {
    func option(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    guard let outPath = option("--out") else {
        print("usage: GardenRender batch --out <dir> [--count 20] [--minutes 4] [--moods dawn,day,dusk,night,rain] [--start-seed 1]")
        exit(2)
    }
    let count = Int(option("--count") ?? "") ?? 20
    let minutes = Double(option("--minutes") ?? "") ?? 4
    let startSeed = UInt64(option("--start-seed") ?? "") ?? 1
    let moods = (option("--moods") ?? "dawn,day,dusk,night,rain").split(separator: ",").compactMap { PieceMood(rawValue: String($0)) }
    guard !moods.isEmpty else { print("no valid moods"); exit(2) }
    let out = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    // Round-robin over the moods; each mood's seeds count up from start-seed.
    var jobs: [(PieceMood, UInt64)] = []
    for i in 0..<count { jobs.append((moods[i % moods.count], startSeed + UInt64(i / moods.count))) }

    let results = Results(count: jobs.count)
    let began = Date()
    DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
        let (mood, seed) = jobs[i]
        do {
            let r = try renderOne(mood: mood, seed: seed, minutes: minutes, out: out)
            results.set(i, r)
            print(String(format: "%@-%llu rendered in %.1f s (%@)", mood.rawValue, seed, r.entry.renderSeconds,
                         r.entry.accepted ? "ok" : "rejected: " + r.entry.rejectReasons.joined(separator: ", ")))
        } catch {
            print("\(mood.rawValue)-\(seed) failed: \(error)")
        }
    }
    let all = results.all
    print(String(format: "all %d pieces in %.1f s wall clock", all.count, Date().timeIntervalSince(began)))

    // batch.json
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(all.map(\.entry)) { try? data.write(to: out.appendingPathComponent("batch.json")) }

    // batch.md
    var md = "# Batch\n\n\(all.count) pieces, \(minutes) min each. Loudness is BS.1770 integrated LUFS (K-weighted, gated), "
    md += "target -24 with the peak held at or under -3 dBFS, so sparse pieces can land a little under target.\n\n"
    md += "| piece | mood | seed | length | notes/min | longest gap | max/10 s | entropy | top note | LUFS | peak dBFS | render s | verdict |\n"
    md += "|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
    for r in all {
        let e = r.entry
        md += String(format: "| %@ | %@ | %llu | %.0f:%02d | %.1f | %.1f s | %d | %.2f | %.0f%% | %.1f | %.1f | %.1f | %@ |\n",
                     e.name, e.mood, e.seed, e.minutes.rounded(.down), Int((e.minutes * 60).truncatingRemainder(dividingBy: 60)),
                     e.notesPerMinute, e.longestGap, e.maxIn10s, e.pitchEntropy, e.topNoteShare * 100,
                     e.loudnessLUFS, e.peakDb, e.renderSeconds,
                     e.accepted ? "ok" : "REJECT: " + e.rejectReasons.joined(separator: "; "))
    }
    try? md.write(to: out.appendingPathComponent("batch.md"), atomically: true, encoding: .utf8)

    writeContactSheet(all, to: out.appendingPathComponent("contact-sheet.png"))
    print("wrote batch.json, batch.md and contact-sheet.png to", out.path)
}
