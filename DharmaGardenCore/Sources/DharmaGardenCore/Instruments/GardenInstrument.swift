import Foundation

/// The instruments a garden theme can play, behind one switch so a renderer (and later the app) can pick one by
/// name. The handpan case calls straight through to `ModalInstrument` and changes nothing about it.
public enum GardenInstrument: String, CaseIterable, Sendable {
    case handpan, kalimba, piano, musicbox, tines

    /// The notes of this instrument, low to high.
    public var notes: [Int] {
        switch self {
        case .handpan: return ModalInstrument.scale
        case .kalimba: return KalimbaInstrument.scale
        case .piano: return FeltPianoInstrument.scale
        case .musicbox: return MusicBoxInstrument.scale
        case .tines: return TinesInstrument.scale
        }
    }

    /// What to give `Improviser` so its pieces are played in this instrument's own range and spirit.
    public var pieceScale: PieceScale {
        switch self {
        case .handpan: return .handpan
        case .kalimba: return KalimbaInstrument.pieceScale
        case .piano: return FeltPianoInstrument.pieceScale
        case .musicbox: return MusicBoxInstrument.pieceScale
        case .tines: return TinesInstrument.pieceScale
        }
    }

    /// How much of the room to mix in, 0...1. The handpan's is the default `ConvolutionReverb.finish` uses; a
    /// piano is a little drier because its own body already carries a lot of the room.
    public var wet: Double {
        switch self {
        case .handpan: return 0.3
        case .kalimba: return 0.28
        case .piano: return 0.22
        case .musicbox: return 0.28
        case .tines: return 0.26
        }
    }

    /// Where the room's final low-pass sits. The handpan keeps the 7 kHz its approved pieces were made with;
    /// the others are darker, so nothing in them feels sharp.
    public var lowPassHz: Double {
        switch self {
        case .handpan, .musicbox: return 7000
        case .kalimba, .piano, .tines: return 4500
        }
    }

    public func render(
        events: [HandpanEvent],
        duration: Double,
        seed: UInt64 = 1,
        sampleRate: Double = ModalInstrument.defaultSampleRate
    ) -> StereoBuffer {
        switch self {
        case .handpan: return ModalInstrument.render(events: events, duration: duration, seed: seed, sampleRate: sampleRate)
        case .kalimba: return KalimbaInstrument.render(events: events, duration: duration, seed: seed, sampleRate: sampleRate)
        case .piano: return FeltPianoInstrument.render(events: events, duration: duration, seed: seed, sampleRate: sampleRate)
        case .musicbox: return MusicBoxInstrument.render(events: events, duration: duration, seed: seed, sampleRate: sampleRate)
        case .tines: return TinesInstrument.render(events: events, duration: duration, seed: seed, sampleRate: sampleRate)
        }
    }
}
