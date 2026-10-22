import Foundation
import WeedsCore

/// Gentle motion for the garden scene: camera drift, depth parallax, plant sway, drifting clouds,
/// falling rain and a slow fog pulse. Everything is a pure function of time (seconds) and wind (0...1),
/// so a frame is deterministic and can be tested without SwiftUI.
public enum SceneMotion {
    /// Depth layers. Each one moves by its multiplier times the camera drift, so nearer things move more.
    public enum Layer: Double, CaseIterable, Sendable {
        case sky = 0.15
        case hills = 0.3
        case fence = 0.6
        /// The lawn and patch. Their motion is the camera drift itself, so this layer is not shifted again.
        case ground = 1.0
        case foreground = 1.6

        public var multiplier: Double { rawValue }
    }

    /// Drift offset amplitude in normalised scene units (a fraction of the scene width or height), before wind.
    public static let driftOffsetAmplitude = 0.012
    /// Drift pitch amplitude in degrees, before wind.
    public static let driftPitchAmplitudeDegrees = 0.8

    /// Clamps to 0...1.
    public static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Wind scales the drift amplitude from 1x (calm) to 1.5x (strong wind).
    static func driftAmplitudeScale(wind: Double) -> Double { 1 + 0.5 * clamp01(wind) }

    /// Camera drift at time `t` (seconds). Offsets are in normalised scene units, pitch in degrees.
    /// Each axis is a sum of two slow sines (periods of about 17, 23 and 29 seconds), so it never
    /// exceeds its amplitude: 0.012 times the wind scale for offsets, 0.8 degrees for pitch.
    public static func drift(at t: Double, wind: Double) -> (offsetX: Double, offsetY: Double, pitchDegrees: Double) {
        let tau = 2 * Double.pi
        let amp = driftAmplitudeScale(wind: wind)
        let x = 0.5 * sin(tau * t / 17) + 0.5 * sin(tau * t / 29 + 1.1)
        let y = 0.5 * sin(tau * t / 23 + 0.4) + 0.5 * sin(tau * t / 29 + 2.3)
        let p = 0.5 * sin(tau * t / 23 + 0.9) + 0.5 * sin(tau * t / 17 + 2.0)
        return (driftOffsetAmplitude * amp * x,
                driftOffsetAmplitude * amp * y,
                driftPitchAmplitudeDegrees * amp * p)
    }

    /// Leaf and stem sway for one plant, -1...1. Each plant has its own phase and period from its seed,
    /// so neighbours do not sway in step. Calm wind keeps a little movement (15% of full strength).
    public static func sway(at t: Double, plantSeed: UInt64, wind: Double) -> Double {
        let strength = 0.15 + 0.85 * clamp01(wind)
        let phase = unit(plantSeed) * 2 * Double.pi
        let period = 2.6 + 1.2 * unit(plantSeed &+ 0x51)
        let v = sin(2 * Double.pi * t / period + phase) * strength
        return min(1, max(-1, v))
    }

    /// A deterministic value in 0..<1 from a seed (SplitMix64).
    static func unit(_ seed: UInt64) -> Double {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    /// The motion state for one drawn frame. A disabled frame is `still`: no drift, no sway, no moving clouds,
    /// rain or fog, so the scene draws as a static picture (used for Reduce Motion, drift off and inactive windows).
    public struct Frame: Equatable, Sendable {
        /// Seconds. Zero when disabled.
        public let time: Double
        /// Wind 0...1. Zero when disabled.
        public let wind: Double
        public let enabled: Bool
        /// Camera drift: offsets in normalised scene units, pitch in degrees.
        public let offsetX: Double
        public let offsetY: Double
        public let pitchDegrees: Double

        public static let still = Frame(time: 0, wind: 0, enabled: false)

        public init(time: Double, wind: Double, enabled: Bool) {
            self.enabled = enabled
            self.time = enabled ? time : 0
            self.wind = enabled ? SceneMotion.clamp01(wind) : 0
            if enabled {
                let d = SceneMotion.drift(at: time, wind: wind)
                offsetX = d.offsetX
                offsetY = d.offsetY
                pitchDegrees = d.pitchDegrees
            } else {
                offsetX = 0
                offsetY = 0
                pitchDegrees = 0
            }
        }

        /// Shift for a depth layer, in normalised scene units.
        public func layerShift(_ layer: Layer) -> (x: Double, y: Double) {
            (offsetX * layer.multiplier, offsetY * layer.multiplier)
        }

        /// Sway for a plant, -1...1. Zero when disabled.
        public func sway(plantSeed: UInt64) -> Double {
            enabled ? SceneMotion.sway(at: time, plantSeed: plantSeed, wind: wind) : 0
        }

        /// How far clouds have travelled in normalised units (before each cloud's own speed factor).
        public var cloudTravel: Double { enabled ? time * 0.002 : 0 }

        /// How far rain has fallen, in scene heights. Falls faster with more rain.
        public func rainFall(strength: Double) -> Double {
            enabled ? time * 2.4 * SceneMotion.clamp01(strength) : 0
        }

        /// Multiplier on the fog strength: a very slight breathing pulse (about 6%, 11 second period).
        public var fogPulse: Double {
            enabled ? 1 + 0.06 * sin(2 * Double.pi * time / 11) : 1
        }
    }

    /// The camera for a frame: `base` with the drift applied. The offset is measured in world units, using how
    /// far the garden centre moves per unit of eye offset, so the centre of the garden moves by the drift.
    /// Hit testing and drawing both use this camera, so taps land on the ground the user sees.
    public static func camera(_ base: Camera, frame: Frame) -> Camera {
        var cam = base
        cam.pitchOffsetDegrees = base.pitchOffsetDegrees + frame.pitchDegrees
        guard frame.enabled else { return cam }

        let centre = cam.project(x: 0, z: 0)
        var px = cam
        px.offset.x += 1
        var py = cam
        py.offset.y += 1
        let sx = px.project(x: 0, z: 0).x - centre.x
        let sy = py.project(x: 0, z: 0).y - centre.y
        if abs(sx) > 1e-9 { cam.offset.x += frame.offsetX / sx }
        if abs(sy) > 1e-9 { cam.offset.y += frame.offsetY / sy }
        return cam
    }

    /// Wraps a cloud's x into -0.2..<1.2, so a cloud leaves fully off one side and re-enters from the other.
    public static func wrapCloudX(_ x: Double) -> Double {
        let span = 1.4
        let a = x + 0.2
        return -0.2 + (a - span * floor(a / span))
    }
}
