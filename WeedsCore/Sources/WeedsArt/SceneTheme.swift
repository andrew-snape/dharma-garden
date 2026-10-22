import SwiftUI
import WeedsCore

/// The look of the garden's surroundings: the horizon, barrier, buildings, ground and ambient touches. Independent of
/// `SceneStyle` (any theme works in both views). The cases match `GardenTheme` in WeedsCore, which the music and the
/// palette use, and the raw values are identical so a stored value reads back as either.
public enum SceneTheme: String, CaseIterable, Sendable {
    case farm, japanese, ruralUK, urban

    public var displayName: String {
        switch self {
        case .farm: "Farm"
        case .japanese: "Japanese garden"
        case .ruralUK: "Rural UK garden"
        case .urban: "Urban backyard"
        }
    }

    /// One line for the settings picker.
    public var blurb: String {
        switch self {
        case .farm: "Rolling green hills, a post-and-rail fence and a Queenslander house."
        case .japanese: "Misty mountains, a tiled wall, a maple and a stone lantern."
        case .ruralUK: "Patchwork fields, a dry-stone wall and a stone cottage."
        case .urban: "Terrace houses, a timber fence and a small backyard."
        }
    }

    public init(_ theme: GardenTheme) {
        switch theme {
        case .farm: self = .farm
        case .japanese: self = .japanese
        case .ruralUK: self = .ruralUK
        case .urban: self = .urban
        }
    }

    /// The same theme as the music and palette know it.
    public var gardenTheme: GardenTheme {
        switch self {
        case .farm: .farm
        case .japanese: .japanese
        case .ruralUK: .ruralUK
        case .urban: .urban
        }
    }
}

/// The theme hooks. `GardenSceneView` calls only these; each one dispatches to the active theme's function, which
/// lives in that theme's file (`SceneThemeJapanese.swift`, `SceneThemeUK.swift`, `SceneThemeUrban.swift`; the farm's
/// are below and wrap the original drawing unchanged). A theme that has nothing of its own yet calls the farm.
///
/// Layers and the layer each hook draws in (parallax and camera as for the farm):
/// - sky layer: `drawThemeSky`, `drawThemeClouds`, then (hills layer) `drawThemeHorizon`
/// - ground (drifted camera): `drawThemeGround`, for both scene styles (check `style` for the backyard extras)
/// - fence layer: `drawThemeBackdropProps` (backyard only, behind the barrier), `drawThemeBarrier`,
///   `drawThemeSideBarriers` (backyard only)
/// - foreground layer: `drawThemeForeground`
/// - weather pass: `drawThemeAmbient`, drawn over the darkness overlay so lights can glow, under fog and rain
extension SceneCanvas {
    func drawThemeSky() {
        switch theme {
        case .farm: farmSky()
        case .japanese: japaneseSky()
        case .ruralUK: ukSky()
        case .urban: urbanSky()
        }
    }

    func drawThemeClouds() {
        switch theme {
        case .farm: farmClouds()
        case .japanese: japaneseClouds()
        case .ruralUK: ukClouds()
        case .urban: urbanClouds()
        }
    }

    func drawThemeHorizon() {
        switch theme {
        case .farm: farmHorizon()
        case .japanese: japaneseHorizon()
        case .ruralUK: ukHorizon()
        case .urban: urbanHorizon()
        }
    }

    func drawThemeGround() {
        switch theme {
        case .farm: farmGround()
        case .japanese: japaneseGround()
        case .ruralUK: ukGround()
        case .urban: urbanGround()
        }
    }

    /// The barrier across the back, in both scene styles.
    func drawThemeBarrier() {
        switch theme {
        case .farm: farmBarrier()
        case .japanese: japaneseBarrier()
        case .ruralUK: ukBarrier()
        case .urban: urbanBarrier()
        }
    }

    /// Buildings, trees and props behind the back barrier. Backyard only.
    func drawThemeBackdropProps() {
        switch theme {
        case .farm: farmBackdropProps()
        case .japanese: japaneseBackdropProps()
        case .ruralUK: ukBackdropProps()
        case .urban: urbanBackdropProps()
        }
    }

    /// The barrier along both sides of the yard. Backyard only.
    func drawThemeSideBarriers() {
        switch theme {
        case .farm: farmSideBarriers()
        case .japanese: japaneseSideBarriers()
        case .ruralUK: ukSideBarriers()
        case .urban: urbanSideBarriers()
        }
    }

    func drawThemeForeground() {
        switch theme {
        case .farm: farmForeground()
        case .japanese: japaneseForeground()
        case .ruralUK: ukForeground()
        case .urban: urbanForeground()
        }
    }

    func drawThemeAmbient() {
        switch theme {
        case .farm: farmAmbient()
        case .japanese: japaneseAmbient()
        case .ruralUK: ukAmbient()
        case .urban: urbanAmbient()
        }
    }

    // MARK: Farm (the original drawing, unchanged)

    func farmSky() { drawSky() }
    func farmClouds() { drawClouds() }
    func farmHorizon() { drawHills() }

    func farmGround() {
        drawLawn()
        if style == .backyard { drawBackyardLawn() }
    }

    func farmBarrier() { drawBarrier(.railFence) }
    func farmBackdropProps() { drawBackyardBack() }
    func farmSideBarriers() { drawSideBarriers(.railFence) }
    func farmForeground() { drawForeground() }
    func farmAmbient() {}
}
