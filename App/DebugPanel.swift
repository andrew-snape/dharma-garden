#if DEBUG
import SwiftUI
import DharmaGardenCore

/// Debug-only time travel: fast-forward the garden to watch growth, bloom, fade and seed heads.
/// Compiled out of release builds.
struct DebugPanel: View {
    @ObservedObject var store: GardenStore
    var music: GardenMusic
    /// Puts a visitor of the chosen species on the patch (the garden view owns the visitor list).
    var onSpawn: (VisitorSpecies) -> Void
    @State private var expanded = true
    @State private var autoWater = true
    @State private var confirmReset = false

    var body: some View {
        DisclosureGroup("Debug", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    advanceButton("+1 day", 1)
                    advanceButton("+1 week", 7)
                    advanceButton("+30 days", 30)
                    advanceButton("+90 days", 90)
                }
                HStack(spacing: 6) {
                    Text("Bed").foregroundStyle(.secondary)
                    styleButton("Soil", .soilPatch)
                    styleButton("Mounds", .mounds)
                    styleButton("Grid", .grid)
                    styleButton("Planters", .plantersBoxes)
                }
                HStack(spacing: 6) {
                    Toggle("Auto-water", isOn: $autoWater)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    Button("Scatter plants") { store.debugScatter() }
                    Button("Reset garden", role: .destructive) { confirmReset = true }
                }
                .controlSize(.small)
                HStack(spacing: 6) {
                    Text("Visitors").foregroundStyle(.secondary)
                    Menu("Spawn visitor") {
                        ForEach(VisitorSpecies.allCases, id: \.self) { species in
                            Button(species.displayName) { onSpawn(species) }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Clear sightings", role: .destructive) { store.debugClearSightings() }
                }
                .controlSize(.small)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Music").foregroundStyle(.secondary)
                        Button("Play a piece now") { music.debugPlayPieceNow() }
                        Button("Skip to silence") { music.debugSkipToSilence() }
                        Button("Play each garden note") { music.debugPlayEachNote() }
                    }
                    .controlSize(.small)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(music.statusLine(at: context.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(.callout)
        .confirmationDialog("Reset the garden?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.debugReset() }
        } message: {
            Text("All plants and weeds will be cleared, and coins and seeds go back to the starting amounts.")
        }
    }

    private func advanceButton(_ title: String, _ days: Int) -> some View {
        Button(title) { store.debugAdvance(days: days, autoWater: autoWater) }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    /// Switches the bed style directly, with no notice; the Settings sheet shows what moved.
    private func styleButton(_ title: String, _ style: BedStyle) -> some View {
        Button(title) { store.apply { _ = GardenEngine.setBedStyle(style, in: &$0) } }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var statusLine: String {
        let s = DebugTools.summary(of: store.garden)
        let date = store.garden.lastSimulatedAt.formatted(date: .abbreviated, time: .shortened)
        return "Simulated \(date) · \(s.planted) planted · \(s.blooming) blooming · \(s.fading) fading · \(s.weeds) weeds"
    }
}
#endif
