import SwiftUI
import WeedsCore
import WeedsArt

/// A small card about the plant under the pointer: its growth, water and what it needs next.
struct PlantCard: View {
    let plant: Plant
    let garden: Garden
    let style: ScenePanelStyle

    private var flower: FlowerType { plant.flower }
    private var isThirsty: Bool { plant.moisture < Tuning.droopFullMoisture }
    private var isFrosted: Bool { plant.frostUntil.map { $0 > Date() } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FlowerArt(flower: flower, progress: min(plant.progress, 1))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(flower.displayName).font(.callout.bold())
                    Text(stageText).font(.caption).foregroundStyle(.secondary)
                }
            }
            if plant.progress < 1 {
                meter("Growth", value: plant.progress, tint: .green)
            }
            meter("Water", value: plant.moisture / 100, tint: isThirsty ? .orange : .blue)
            Text(needText)
                .font(.caption.bold())
                .foregroundStyle(needsAttention ? Color.orange : Color.primary)
            let badges = treatmentBadges
            if !badges.isEmpty {
                HStack(spacing: 4) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(style.idleFill))
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 190, alignment: .leading)
        .panel(style)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func meter(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            ProgressView(value: min(max(value, 0), 1)).tint(tint)
        }
    }

    /// Life stage in words. A growing plant also gets a rough time to go, from its own growth speed.
    private var stageText: String {
        switch plant.lifeStage {
        case .growing:
            let days = Int(((1 - plant.progress) * flower.daysToBloom / plant.speedFactor).rounded(.up))
            return "\(plant.stage.label) · about \(max(days, 1)) day\(days == 1 ? "" : "s") to go"
        case .blooming: return flower.readyWord == "harvest" ? "Ready to harvest" : "In bloom"
        case .fading: return "Fading"
        case .seedHead: return "Gone to seed"
        }
    }

    private var needsAttention: Bool { plant.isWilted || isThirsty || isFrosted }

    /// The most pressing thing about the plant, one line.
    private var needText: String {
        if plant.isWilted { return "Wilting. Water it now" }
        if isThirsty { return "Thirsty. Needs water" }
        if isFrosted { return "Chilled by frost" }
        switch plant.lifeStage {
        case .growing: return "Doing well"
        case .blooming: return flower.readyWord == "harvest" ? "Pick it for coins" : "Enjoy the flowers"
        case .fading, .seedHead: return "Past its best"
        }
    }

    /// Soil treatments active under the plant.
    private var treatmentBadges: [String] {
        var out: [String] = []
        if garden.soil.isTreated(\.aeratedHours, at: plant.position) { out.append("Forked") }
        if garden.soil.isTreated(\.seasolHours, at: plant.position) { out.append("Seasol") }
        if garden.soil.isTreated(\.fertiliserHours, at: plant.position) { out.append("Fertilised") }
        return out
    }
}

private extension GrowthStage {
    var label: String {
        switch self {
        case .seed: "Seed"
        case .sprout: "Sprout"
        case .bud: "Bud"
        case .bloom: "Bloom"
        }
    }
}
