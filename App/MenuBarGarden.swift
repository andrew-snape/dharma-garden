import SwiftUI
import AppKit
import DharmaGardenCore
import DharmaGardenArt

/// The one garden store, settings and weather, shared by the main window and the menu bar garden.
@MainActor
final class GardenShared {
    static let shared = GardenShared()
    let store = GardenStore()
    let settings = AppSettings()
    let weather = WeatherService()
    private init() {}
}

/// The compact garden in the menu bar window: the scene, a few tools and the buttons to open the window or quit.
/// It reads the same store as the main window, so a change in one shows in the other.
struct MenuBarGarden: View {
    @ObservedObject var store: GardenStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var weather: WeatherService
    @Environment(\.openWindow) private var openWindow
    @State private var tool: Tool = .water
    @State private var ripples: [SceneRipple] = []
    @State private var lastSprinkle: GroundPoint?

    private var palette: ScenePalette {
        let theme = settings.sceneTheme.gardenTheme
        return weather.palette(theme: theme) ?? ScenePalette.resolve(season: weather.season, phase: .day, condition: .clear,
                                                                     temperatureC: 18, cloudCover: 0, theme: theme)
    }

    var body: some View {
        let style = ScenePanelStyle(palette: palette)
        VStack(spacing: 8) {
            HStack {
                Text(settings.gardenTitle).font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    CarrotIcon(size: 15)
                    Text("\(store.garden.coins)").font(.callout.bold().monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(store.garden.coins) carrots")
            }
            GardenSceneView(garden: store.garden, palette: palette, ripples: ripples,
                            onTap: { tap($0) }, onDrag: { drag($0) },
                            wind: 0.25, driftEnabled: false,
                            style: settings.sceneStyle, theme: settings.sceneTheme)
                .frame(width: 360, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 6) {
                tile("Water", .water) { _ in Image(systemName: "drop.fill").font(.system(size: 13, weight: .semibold)) }
                tile("Weed", .weed) { HandWeederIcon(color: $0).frame(width: 15, height: 16) }
                tile("Pick", .harvest) { _ in Image(systemName: "basket.fill").font(.system(size: 13, weight: .semibold)) }
                tile("Fork", .fork) { GardenForkIcon(color: $0).frame(width: 15, height: 16) }
            }
            HStack {
                Button("Open Garden window") {
                    openWindow(id: GardenWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 384)
        .background(style.fill)
        .environment(\.colorScheme, style.colorScheme)
        .onAppear { store.catchUp(weather: weather.report?.hourly ?? []) }
    }

    private func tile<Icon: View>(_ title: String, _ t: Tool, @ViewBuilder icon: (Color) -> Icon) -> some View {
        let selected = tool == t
        let text: Color = selected ? .white : .primary
        return Button { tool = t } label: {
            VStack(spacing: 2) {
                icon(text).foregroundStyle(text)
                Text(title).font(.caption.bold()).foregroundStyle(text)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? ScenePanelStyle(palette: palette).selectedFill : ScenePanelStyle(palette: palette).idleFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tap(_ p: GroundPoint?) {
        lastSprinkle = nil
        guard let p else { return }
        use(p)
    }

    /// Dragging waters along the path, one spot every tenth of the patch; the other tools act on each spot passed.
    private func drag(_ p: GroundPoint?) {
        guard let p else { lastSprinkle = nil; return }
        if let last = lastSprinkle, hypot(last.x - p.x, last.y - p.y) < 0.04 { return }
        lastSprinkle = p
        use(p)
    }

    private func use(_ p: GroundPoint) {
        var acted = false
        store.apply { g in
            switch tool {
            case .water: GardenEngine.water(at: p, in: &g); acted = true
            case .weed: acted = GardenEngine.pullWeed(at: p, in: &g)
            case .harvest: acted = GardenEngine.harvest(at: p, in: &g) != nil
            default: acted = GardenEngine.aerate(at: p, in: &g)
            }
        }
        guard acted || tool == .fork else { return }
        let kind: SceneRipple.Kind = switch tool {
        case .water: .water
        case .weed: .pull
        case .harvest: .pick
        default: .aerate
        }
        let now = Date()
        ripples.removeAll { now.timeIntervalSince($0.startedAt) > 4.5 }
        ripples.append(SceneRipple(point: p, startedAt: now, kind: kind))
    }
}

/// The menu bar icon: a leaf.
struct MenuBarLeaf: View {
    var body: some View { Image(systemName: "leaf.fill") }
}

enum GardenWindow { static let id = "garden" }
