import Foundation

public struct RGB: Codable, Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }
    func mixed(with o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
    func desaturated(_ amount: Double) -> RGB {
        let l = luminance
        return mixed(with: RGB(l, l, l), amount)
    }
}

public struct ScenePalette: Equatable, Sendable {
    public var skyTop: RGB
    public var skyBottom: RGB
    public var grass: RGB
    public var soil: RGB
    public var foliage: RGB
    /// Darkness overlay 0...1 (night/dusk), applied by the UI over the whole scene.
    public var darkness: Double
    /// Extra tint over the scene (frost blue, heat haze) and its strength 0...1.
    public var overlayTint: RGB
    public var overlayStrength: Double
    public var rainStrength: Double   // 0...1 particle density
    public var fogStrength: Double    // 0...1
    /// The sun right now, for real-time shadows and golden light. nil means no sun data: draw as before.
    public var sun: SunLight? = nil
    /// Cloud cover 0...100 used to build this palette.
    public var cloudCover: Double = 0

    // Base earthy palette per season: (grass, soil, foliage).
    static func base(_ s: Season) -> (grass: RGB, soil: RGB, foliage: RGB) {
        switch s {
        case .summer: (RGB(hex: 0x9DAA5B), RGB(hex: 0x7A5A3E), RGB(hex: 0x7F9A4A))
        case .autumn: (RGB(hex: 0x8A8F4E), RGB(hex: 0x6B4A33), RGB(hex: 0xB5703A))
        case .winter: (RGB(hex: 0x7C8F78), RGB(hex: 0x5E4A3C), RGB(hex: 0x6B7F72))
        case .spring: (RGB(hex: 0x8FB86A), RGB(hex: 0x6E4F38), RGB(hex: 0x9CC77A))
        }
    }

    static func sky(_ p: SunPhase) -> (top: RGB, bottom: RGB) {
        switch p {
        case .day: (RGB(hex: 0x6FA8DC), RGB(hex: 0xCFE6F5))
        case .dawn: (RGB(hex: 0x8C9BC9), RGB(hex: 0xF3C9A0))
        case .dusk: (RGB(hex: 0x5B5F9E), RGB(hex: 0xE8A07A))
        case .night: (RGB(hex: 0x14213D), RGB(hex: 0x2B3A67))
        }
    }

    /// Pipeline: base earthy palette -> season -> time of day -> weather overlay.
    public static func resolve(season: Season, phase: SunPhase, condition: WeatherCondition,
                               temperatureC: Double, cloudCover: Double, sun: SunLight? = nil,
                               theme: GardenTheme = .farm) -> ScenePalette {
        // `theme` is accepted so callers can pass it through; no theme tints the palette yet (all match the farm).
        let b = base(season)
        let s = sky(phase)
        var p = ScenePalette(skyTop: s.top, skyBottom: s.bottom, grass: b.grass, soil: b.soil, foliage: b.foliage,
                             darkness: 0, overlayTint: RGB(1, 1, 1), overlayStrength: 0, rainStrength: 0, fogStrength: 0)

        switch phase {
        case .day: p.darkness = 0
        case .dawn: p.darkness = 0.15
        case .dusk: p.darkness = 0.25
        case .night: p.darkness = 0.55
        }

        // Cloud and precipitation grey the sky and mute the ground.
        let grey: Double
        switch condition {
        case .clear: grey = 0.0
        case .partlyCloudy: grey = 0.2
        case .overcast: grey = 0.5
        case .fog: grey = 0.55
        case .drizzle: grey = 0.55
        case .rain: grey = 0.7
        case .thunderstorm: grey = 0.85
        case .snow: grey = 0.6
        }
        let cloudy = max(grey, cloudCover / 100 * 0.6)
        let skyGrey = RGB(0.62, 0.65, 0.68)
        p.skyTop = p.skyTop.mixed(with: skyGrey.desaturated(0), cloudy * 0.8)
        p.skyBottom = p.skyBottom.mixed(with: skyGrey, cloudy * 0.8)
        p.grass = p.grass.desaturated(cloudy * 0.35)
        p.foliage = p.foliage.desaturated(cloudy * 0.35)

        switch condition {
        case .drizzle: p.rainStrength = 0.3
        case .rain: p.rainStrength = 0.7
        case .thunderstorm: p.rainStrength = 1.0; p.darkness += 0.15
        case .fog: p.fogStrength = 0.7
        default: break
        }
        if condition == .snow { p.overlayTint = RGB(0.92, 0.95, 1); p.overlayStrength = 0.25 }

        // Hot days get a warm haze; near-freezing gets a blue cast.
        if temperatureC > 30 {
            p.overlayTint = RGB(1, 0.85, 0.6); p.overlayStrength = min(0.3, (temperatureC - 30) / 20 + 0.1)
        } else if temperatureC < 2 {
            p.overlayTint = RGB(0.75, 0.85, 1); p.overlayStrength = 0.2
        }
        p.darkness = min(0.8, p.darkness)
        p.sun = sun
        p.cloudCover = cloudCover
        return p
    }
}
