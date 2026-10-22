import SwiftUI
import WeedsCore

/// A still thumbnail of the real garden scene for a theme: backyard view, fixed summer day palette (so it looks the
/// same in light and dark mode), the given bed with a few blooming plants. It has no timeline, no drift and takes no
/// hits, so the caller can draw it once to an image and cache it.
public struct SceneThemePreview: View {
    public var theme: SceneTheme
    public var bedStyle: BedStyle

    public init(theme: SceneTheme, bedStyle: BedStyle) {
        self.theme = theme
        self.bedStyle = bedStyle
    }

    /// Sunny summer day, sun high in the north-west (the same light as the scene render sheets).
    private static let palette = ScenePalette.resolve(
        season: .summer, phase: .day, condition: .clear, temperatureC: 26, cloudCover: 10,
        sun: SunLight(elevationDegrees: 38, azimuthDegrees: 200, intensity: 0.9, warmth: 0.1))

    /// A fresh garden on `bedStyle` with a handful of flowers in bloom.
    static func garden(bedStyle: BedStyle) -> Garden {
        var g = Garden(now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = GardenEngine.setBedStyle(bedStyle, in: &g)
        g = DebugTools.fillWithPlants(garden: g, count: 7)
        for i in g.plants.indices {
            g.plants[i].progress = 1
            g.plants[i].bloomHoursElapsed = 48
        }
        return g
    }

    public var body: some View {
        SceneContent(garden: Self.garden(bedStyle: bedStyle), palette: Self.palette, camera: .backyard,
                     motion: .still, style: .backyard, theme: theme)
            .allowsHitTesting(false)
    }
}
