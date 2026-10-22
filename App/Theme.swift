import SwiftUI
import DharmaGardenCore

/// Readable chrome for the garden window. Every piece of UI text sits on a rounded panel whose fill is
/// opaque enough that the text colour does not depend on what the scene behind it looks like.
struct ScenePanelStyle {
    /// True for a dark panel with light text (night, dusk, dim weather); false for a light panel with dark text.
    let isDark: Bool

    init(palette: ScenePalette) {
        isDark = palette.darkness > 0.35 || Self.luma(palette) < 0.45
    }

    /// Light text on a dark panel, dark text on a light panel. Applied to the panel's content so that
    /// system colours (.primary, .secondary, toggles, disclosure chevrons) adapt too.
    var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// Dark panel: black at 72% over the scene leaves at most 28% of the scene's brightness behind the
    /// white text, which is at least 9:1 contrast even over a white scene. Light panel: white at 85%
    /// leaves at least 85% brightness behind the black text, at least 14:1 contrast.
    var fill: Color { isDark ? Color.black.opacity(0.72) : Color.white.opacity(0.85) }
    var stroke: Color { isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10) }

    /// Fill for the selected tool. Chosen so white text on it is above 4.5:1.
    var selectedFill: Color { Color(red: 0.0, green: 0.35, blue: 0.85) }
    var idleFill: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06) }

    /// Rough perceived brightness of the scene after the darkness overlay (0...1).
    private static func luma(_ p: ScenePalette) -> Double {
        func l(_ c: RGB) -> Double { 0.2126 * Double(c.r) + 0.7152 * Double(c.g) + 0.0722 * Double(c.b) }
        return (l(p.skyTop) + l(p.skyBottom) + l(p.grass)) / 3 * (1 - p.darkness)
    }
}

struct PanelModifier: ViewModifier {
    let style: ScenePanelStyle

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, style.colorScheme)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(style.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel(_ style: ScenePanelStyle) -> some View {
        modifier(PanelModifier(style: style))
    }
}

/// The frame shared by the shop, book and settings sheets: the garden's own backdrop, a panel title bar with a
/// Done button (and the coin count, when given), and the content below. Panels inside it use the same `ScenePanelStyle`
/// as the main window, so the sheets read as part of the garden rather than a second app.
struct GardenSheetFrame<Content: View>: View {
    let title: String
    let palette: ScenePalette
    /// Shows the coin counter in the title bar when set.
    var coins: Int?
    var coinNote: CoinNote?
    let onDone: () -> Void
    @ViewBuilder let content: (ScenePanelStyle) -> Content

    var body: some View {
        let style = ScenePanelStyle(palette: palette)
        ZStack {
            SceneBackground(palette: palette).ignoresSafeArea()
            VStack(spacing: 12) {
                titleBar(style)
                content(style)
            }
            .padding(16)
        }
        // Text drawn straight on the backdrop (outside any panel) still follows the panel's light or dark scheme.
        .environment(\.colorScheme, style.colorScheme)
    }

    private func titleBar(_ style: ScenePanelStyle) -> some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            if let coins {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").foregroundStyle(.orange)
                    Text("\(coins)").font(.title3.bold().monospacedDigit())
                }
                .overlay(alignment: .leading) {
                    if let note = coinNote { CoinFloat(amount: note.amount).id(note.id).offset(x: -44) }
                }
                .padding(.trailing, 6)
            }
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .panel(style)
    }
}
