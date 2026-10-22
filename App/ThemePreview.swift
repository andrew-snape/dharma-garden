import SwiftUI
import DharmaGardenArt
import DharmaGardenCore

/// Renders each theme's preview once and keeps the image, so the Settings rows draw a bitmap instead of the scene.
@MainActor
enum ThemePreviewCache {
    static let size = CGSize(width: 96, height: 72)

    private struct Key: Hashable {
        let theme: SceneTheme
        let bed: BedStyle
    }

    private static var images: [Key: Image] = [:]

    /// The cached image for the pair, drawn on first use. A new bed style makes a new entry.
    static func image(theme: SceneTheme, bed: BedStyle) -> Image? {
        let key = Key(theme: theme, bed: bed)
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(content: SceneThemePreview(theme: theme, bedStyle: bed)
            .frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let rendered = renderer.nsImage else { return nil }
        let image = Image(nsImage: rendered)
        images[key] = image
        return image
    }
}

/// The still scene thumbnail for a theme, with a ring around it when it is the chosen one. Decorative: the row's
/// text carries the label.
struct ThemePreviewImage: View {
    let theme: SceneTheme
    let bed: BedStyle
    let selected: Bool

    var body: some View {
        Group {
            if let image = ThemePreviewCache.image(theme: theme, bed: bed) {
                image.resizable().interpolation(.high)
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: ThemePreviewCache.size.width, height: ThemePreviewCache.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
