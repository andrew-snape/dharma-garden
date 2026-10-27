import Accelerate
import AVFoundation
import CoreGraphics
import DharmaGardenCore
import Foundation
import ImageIO

// Spike renderer for the modal handpan. Not shipped with the app.
// Usage: swift run GardenRender [output-dir]   (default: ../music-previews)

// `GardenRender batch ...` renders improviser candidates instead; see Batch.swift.
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "batch" {
    runBatch(Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}

// `GardenRender notes --out <dir>` renders the garden-note one-shots; see Notes.swift.
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "notes" {
    runNotes(Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}

// `GardenRender preview --instrument kalimba|piano|musicbox|tines|handpan --out <dir>` renders the Phase 3 previews;
// see Preview.swift.
if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "preview" {
    runPreview(Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}

let sampleRate = ModalInstrument.defaultSampleRate
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../music-previews")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// 24-bit PCM stereo WAV.
func writeWAV(_ buf: StereoBuffer, to url: URL) throws {
    let frames = buf.left.count
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let dataBytes = UInt32(frames * 6)
    data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(2)
    u32(UInt32(buf.sampleRate)); u32(UInt32(buf.sampleRate) * 6); u16(6); u16(24)
    data.append(contentsOf: Array("data".utf8)); u32(dataBytes)
    func s24(_ x: Float) {
        let v = Int32(max(-1, min(1, x)) * 8_388_607)
        data.append(UInt8(truncatingIfNeeded: v)); data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v >> 16))
    }
    for i in 0..<frames { s24(buf.left[i]); s24(buf.right[i]) }
    try data.write(to: url)
}

func stats(_ b: StereoBuffer) -> String {
    var peak: Float = 0
    var sum: Double = 0
    for i in 0..<b.left.count {
        peak = max(peak, abs(b.left[i]), abs(b.right[i]))
        sum += Double(b.left[i] * b.left[i] + b.right[i] * b.right[i])
    }
    let rms = (sum / Double(2 * max(1, b.left.count))).squareRoot()
    return String(format: "peak %.2f dBFS, rms %.2f dBFS", 20 * log10(Double(peak)), 20 * log10(rms))
}

func fade(_ b: StereoBuffer, out seconds: Double) -> StereoBuffer {
    var b = b
    let n = Int(seconds * b.sampleRate)
    for i in 0..<min(n, b.left.count) {
        let g = Float(0.5 + 0.5 * cos(Double.pi * Double(i) / Double(n)))
        b.left[b.left.count - n + i] *= g
        b.right[b.right.count - n + i] *= g
    }
    return b
}

// MARK: Notes file

var noteEvents: [HandpanEvent] = []
var t = 0.5
for velocity in [0.35, 0.65] {
    for midi in ModalInstrument.scale {
        noteEvents.append(HandpanEvent(time: t, midi: midi, velocity: velocity))
        t += 3.5
    }
}
let notesDuration = t + 4
let notesDry = ModalInstrument.render(events: noteEvents, duration: notesDuration, seed: 42)
let notes = fade(ConvolutionReverb.finish(notesDry), out: 1.0)
try writeWAV(notes, to: outDir.appendingPathComponent("handpan-notes.wav"))
print("handpan-notes.wav:", stats(notes))

// MARK: Improvisation

/// A loose, seeded handpan player: short phrases on a ~66 bpm pulse, stepwise, resolving to D or A.
func improvise(seconds: Double, seed: UInt64) -> [HandpanEvent] {
    var rng = SplitMix(seed: seed)
    let beat = 60.0 / 66.0
    var events: [HandpanEvent] = []
    var pos = 4 // D4
    var time = 1.0
    var lastMotif: [Int] = []
    while time < seconds - 6 {
        let progress = time / seconds
        // Arc: sparse start and end, fuller in the middle.
        let fullness = sin(Double.pi * min(1, max(0, progress))) // 0...1...0
        let count = 3 + Int((rng.unit() * 2 + fullness * 2.5).rounded(.down))
        let n = min(7, count)
        var degrees: [Int] = []
        if !lastMotif.isEmpty && rng.unit() < 0.3 {
            // Repeat the previous phrase's opening with a small variation.
            degrees = Array(lastMotif.prefix(max(2, n - 2)))
            pos = degrees.last ?? pos
        }
        while degrees.count < n - 1 {
            let r = rng.unit()
            var step = r < 0.38 ? 1 : (r < 0.76 ? -1 : (r < 0.86 ? 2 : -2))
            if rng.unit() < 0.04 { pos = 0; step = 0 } // occasional ding anchor
            pos = min(8, max(0, pos + step))
            degrees.append(pos)
        }
        // Resolve to the nearest of D4, A3, A4, D3.
        let targets = [4, 1, 8, 0]
        let resolve = targets.min { abs($0 - pos) < abs($1 - pos) } ?? 4
        degrees.append(resolve)
        pos = resolve
        lastMotif = degrees

        var beatTime = time
        for d in degrees {
            let humanise = rng.signed() * 0.02
            let velocity = (0.25 + 0.2 * fullness + 0.15 * rng.unit()).clamped(0.25, 0.6)
            events.append(HandpanEvent(time: max(0, beatTime + humanise),
                                       midi: ModalInstrument.scale[d], velocity: velocity))
            beatTime += beat * (rng.unit() < 0.25 ? 0.5 : 1)
            if rng.unit() < 0.15 { beatTime += beat * 0.5 }
        }
        let rest = (2 + 4 * (1 - fullness) * rng.unit() + 1.5 * rng.unit()).clamped(2, 6)
        time = beatTime + rest
    }
    return events
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}

let improv = improvise(seconds: 60, seed: 2026)
let improvDry = ModalInstrument.render(events: improv, duration: 64, seed: 42)
let improvMix = fade(ConvolutionReverb.finish(improvDry), out: 3.0)
try writeWAV(improvMix, to: outDir.appendingPathComponent("handpan-60s.wav"))
print("handpan-60s.wav:", stats(improvMix), "notes:", improv.count)

// MARK: Spectrogram

func writeSpectrogram(_ b: StereoBuffer, to url: URL, width: Int = 1600, height: Int = 600, maxHz: Double = 8000) throws {
    let n = 8192
    let log2n = 13
    let mono = zip(b.left, b.right).map { 0.5 * ($0 + $1) }
    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else { return }
    defer { vDSP_destroy_fftsetup(setup) }
    let binHz = b.sampleRate / Double(n)
    let maxBin = Int(maxHz / binHz)
    var db = [Float](repeating: -200, count: width * height)
    var maxDb: Float = -200
    for col in 0..<width {
        let centre = Int(Double(col) / Double(width) * Double(mono.count))
        var frame = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let idx = centre - n / 2 + i
            if idx >= 0 && idx < mono.count { frame[i] = mono[idx] * window[i] }
        }
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
        for row in 0..<height {
            let hz = maxHz * (1 - Double(row) / Double(height - 1)) // top = high
            let bin = min(maxBin, Int(hz / binHz))
            let mag = (re[bin] * re[bin] + im[bin] * im[bin]).squareRoot() / Float(n)
            let v = 20 * log10(max(mag, 1e-10))
            db[row * width + col] = v
            maxDb = max(maxDb, v)
        }
    }
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) {
        let x = Double(max(0, min(1, (db[i] - (maxDb - 90)) / 90)))
        // black -> indigo -> magenta -> orange -> pale yellow
        let stops: [(Double, Double, Double)] = [(0, 0, 0), (0.15, 0.05, 0.4), (0.7, 0.1, 0.5), (1, 0.6, 0.1), (1, 1, 0.8)]
        let f = x * 4
        let k = min(3, Int(f)), u = f - Double(k)
        let a = stops[k], c = stops[k + 1]
        pixels[i * 4] = UInt8(255 * (a.0 + (c.0 - a.0) * u))
        pixels[i * 4 + 1] = UInt8(255 * (a.1 + (c.1 - a.1) * u))
        pixels[i * 4 + 2] = UInt8(255 * (a.2 + (c.2 - a.2) * u))
    }
    // 1 kHz gridlines
    for kHz in 1..<8 where Double(kHz) * 1000 < maxHz {
        let row = Int((1 - Double(kHz) * 1000 / maxHz) * Double(height - 1))
        for col in stride(from: 0, to: width, by: 4) {
            let o = (row * width + col) * 4
            pixels[o] = 90; pixels[o + 1] = 90; pixels[o + 2] = 90
        }
    }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: cs,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

try writeSpectrogram(notes, to: outDir.appendingPathComponent("handpan-spectrogram.png"))
print("wrote spectrogram to", outDir.path)
let dryNotes = StereoBuffer(left: notesDry.left, right: notesDry.right, sampleRate: sampleRate)
try writeSpectrogram(dryNotes, to: outDir.appendingPathComponent("handpan-spectrogram-dry.png"))

// MARK: Recorded hang (FreePats, CC0)

// With a second argument, the FreePats "Hang D minor" samples folder, the same notes sheet and improvisation are
// rendered again from the recordings, for comparing with the model. The hang's nine notes stand in for the model's
// nine, lowest to highest, so the melody keeps its shape; both are in D minor, so it stays in key.
if CommandLine.arguments.count > 2 {
    let hangDir = URL(fileURLWithPath: CommandLine.arguments[2])
    let hangNotes = ["A3", "D4", "E4", "F4", "G4", "A4", "Bb4", "C5", "D5"]
    let hangRate = 44_100.0

    /// Every take of every note, each scaled to peak 1 with a 50 ms fade at the end so a trimmed take never clicks.
    func loadTakes(_ name: String) throws -> [[[Float]]] {
        var takes: [[[Float]]] = []
        for i in 1...9 {
            let url = hangDir.appendingPathComponent(String(format: "%@_%02d.flac", name, i))
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let file = try AVAudioFile(forReading: url)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            try file.read(into: buf)
            let n = Int(buf.frameLength)
            let channels = Int(buf.format.channelCount)
            var lr = (0..<2).map { c in Array(UnsafeBufferPointer(start: buf.floatChannelData![min(c, channels - 1)], count: n)) }
            let peak = lr.flatMap { $0 }.map(abs).max() ?? 1
            let fadeN = min(n, Int(0.05 * hangRate))
            for c in 0..<2 {
                for i in 0..<n { lr[c][i] /= max(peak, 1e-6) }
                for i in 0..<fadeN { lr[c][n - fadeN + i] *= Float(fadeN - i) / Float(fadeN) }
            }
            takes.append(lr)
        }
        return takes
    }

    let takes = try hangNotes.map(loadTakes)

    /// Plays each event with a random take of its note (never the same take twice running), louder for harder hits.
    func renderHang(_ events: [HandpanEvent], duration: Double, seed: UInt64) -> StereoBuffer {
        var rng = SplitMix(seed: seed)
        let total = Int(duration * hangRate)
        var l = [Float](repeating: 0, count: total), r = l
        var lastTake = [Int](repeating: -1, count: hangNotes.count)
        for e in events {
            guard let degree = ModalInstrument.scale.firstIndex(of: e.midi), !takes[degree].isEmpty else { continue }
            var k = Int(rng.unit() * Double(takes[degree].count))
            if k == lastTake[degree] { k = (k + 1) % takes[degree].count }
            lastTake[degree] = k
            let take = takes[degree][k]
            let gain = Float(0.4 * e.velocity / 0.65)
            let start = Int(e.time * hangRate)
            for i in 0..<take[0].count where start + i < total {
                l[start + i] += gain * take[0][i]
                r[start + i] += gain * take[1][i]
            }
        }
        return StereoBuffer(left: l, right: r, sampleRate: hangRate)
    }

    // The recording already carries the auditorium's sound, so it gets less of our room than the model.
    let hangNotesMix = fade(ConvolutionReverb.finish(renderHang(noteEvents, duration: notesDuration, seed: 42), wet: 0.18),
                            out: 1.0)
    try writeWAV(hangNotesMix, to: outDir.appendingPathComponent("hang-notes.wav"))
    print("hang-notes.wav:", stats(hangNotesMix))
    let hangImprov = fade(ConvolutionReverb.finish(renderHang(improv, duration: 64, seed: 42), wet: 0.18), out: 3.0)
    try writeWAV(hangImprov, to: outDir.appendingPathComponent("hang-60s.wav"))
    print("hang-60s.wav:", stats(hangImprov))
    try writeSpectrogram(hangNotesMix, to: outDir.appendingPathComponent("hang-spectrogram.png"))
}
