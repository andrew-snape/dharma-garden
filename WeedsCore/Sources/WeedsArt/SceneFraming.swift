import CoreGraphics

/// How the 4:3 garden scene fills a window: it covers the whole container (no empty bands), with the overflow
/// cropped evenly on both sides. The crop is limited so the soil patch at the middle of the scene is never cut:
/// if covering would hide too much of the width, the scene stops growing and the backdrop shows above and below.
public enum SceneFraming {
    /// The scene is 4:3.
    public static let aspect: CGFloat = 4.0 / 3.0
    /// The least share of the scene's width that stays visible.
    public static let minVisibleWidth: CGFloat = 0.8

    /// The size to draw the scene at inside `container`, to be centred and clipped to it.
    public static func coverSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let coverWidth = max(container.width, container.height * aspect)
        // Widest crop allowed: the container shows at least `minVisibleWidth` of the scene.
        let width = min(coverWidth, container.width / minVisibleWidth)
        return CGSize(width: width, height: width / aspect)
    }
}
