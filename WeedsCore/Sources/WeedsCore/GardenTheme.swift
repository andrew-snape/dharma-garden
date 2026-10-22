import Foundation

/// The look and sound the player picked for the garden. This is the one list of themes: WeedsArt's `SceneTheme`
/// wraps it for the scene, and `GardenMood` and `ScenePalette.resolve` take it directly.
public enum GardenTheme: String, CaseIterable, Sendable, Codable {
    case farm, japanese, ruralUK, urban
}
