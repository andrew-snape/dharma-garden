import SwiftUI
import WeedsCore
import WeedsArt

/// The collection book, opened from the book button in the header. Shows the milestone rewards and every visitor
/// species. Unspotted species stay as silhouettes with a hint about where to look. Reads the store live, so it
/// updates as the garden changes. Drawn in the garden's panel style, like the seed shop.
struct GardenBookView: View {
    @ObservedObject var store: GardenStore
    let palette: ScenePalette
    @Environment(\.dismiss) private var dismiss
    /// The species whose detail shows along the bottom. Selecting the same card again closes it.
    @State private var selected: VisitorSpecies?
    @State private var coinNote: CoinNote?
    @State private var noteID = 0

    /// Rarity sections in display order.
    private static let rarities: [VisitorRarity] = [.common, .uncommon, .rare]

    private var spotted: Int { GardenEngine.spottedSpeciesCount(in: store.garden) }
    private var total: Int { VisitorSpecies.allCases.count }
    private var style: ScenePanelStyle { ScenePanelStyle(palette: palette) }

    var body: some View {
        GardenSheetFrame(title: "Garden book", palette: palette, coins: store.garden.coins, coinNote: coinNote,
                         onDone: { dismiss() }) { style in
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        progressHeader.padding(12).panel(style)
                        milestonesSection.padding(12).panel(style)
                        ForEach(Self.rarities, id: \.self) { rarity in
                            speciesSection(rarity).padding(12).panel(style)
                        }
                    }
                }
                if let species = selected { detail(species).panel(style) }
            }
            .animation(.easeOut(duration: 0.2), value: selected)
        }
        .frame(minWidth: 540, minHeight: 680)
    }

    // MARK: Header

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(spotted) of \(total) spotted")
                .font(.headline)
                .monospacedDigit()
            progressBar(spotted, of: total)
        }
    }

    // MARK: Milestones

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Milestones", detail: nil)
            VStack(spacing: 0) {
                ForEach(VisitorMilestone.all) { milestone in
                    milestoneRow(milestone)
                    if milestone.id != VisitorMilestone.all.last?.id { Divider() }
                }
            }
        }
    }

    private func milestoneRow(_ m: VisitorMilestone) -> some View {
        let reached = min(spotted, m.species)
        let claimed = store.garden.claimedMilestones.contains(m.species)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(m.title).font(.headline)
                Spacer()
                Text("\(reached)/\(m.species)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            progressBar(reached, of: m.species)
            HStack(alignment: .center, spacing: 10) {
                Text(rewardText(m))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if claimed {
                    Label("Claimed", systemImage: "checkmark.circle.fill")
                        .font(.callout.bold())
                        .foregroundStyle(.green)
                } else {
                    Button { claim(m) } label: {
                        Text("Claim")
                            .font(.callout.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(spotted >= m.species ? Color.orange : Color.secondary.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .disabled(spotted < m.species)
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// "15 coins · 2 lavender seeds", with the seed types in name order.
    private func rewardText(_ m: VisitorMilestone) -> String {
        var parts = ["\(m.coins) coins"]
        for (flower, count) in m.seeds.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            parts.append("\(count) \(flower.displayName.lowercased()) seeds")
        }
        return "Reward: " + parts.joined(separator: " · ")
    }

    private func claim(_ m: VisitorMilestone) {
        var claimed = false
        store.apply { claimed = GardenEngine.claimMilestone(m, in: &$0) }
        if claimed { flashCoins(m.coins) }
    }

    // MARK: Species

    private func speciesSection(_ rarity: VisitorRarity) -> some View {
        let species = VisitorSpecies.allCases.filter { $0.rarity == rarity }
        let count = species.filter { store.garden.sightingCount($0) > 0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(rarityLabel(rarity), detail: "\(count) of \(species.count)")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(species, id: \.self) { card($0) }
            }
        }
    }

    private func card(_ species: VisitorSpecies) -> some View {
        let count = store.garden.sightingCount(species)
        let isSelected = selected == species
        return Button { selected = isSelected ? nil : species } label: {
            VStack(spacing: 6) {
                VisitorArt(species: species, size: 72, silhouette: count == 0)
                    .frame(width: 72, height: 72)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 { countBadge(count) }
                    }
                Text(count > 0 ? species.displayName : "???")
                    .font(.callout.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                rarityChip(species.rarity)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(species.displayName), spotted \(count) times" : "Not spotted yet")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Bottom panel for the selected species. Unspotted species show only the silhouette and the hint.
    private func detail(_ species: VisitorSpecies) -> some View {
        let count = store.garden.sightingCount(species)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VisitorArt(species: species, size: 112, silhouette: count == 0)
                    .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(count > 0 ? species.displayName : "???").font(.title3.bold())
                        rarityChip(species.rarity)
                    }
                    if count > 0 {
                        Text(species.blurb).font(.callout)
                        Text("Spotted \(count) \(count == 1 ? "time" : "times")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Pays \(species.coinReward) coins a spot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Look for it when...")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(species.hint).font(.callout)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Flat orange bar for progress, drawn by hand so it looks the same in every mode.
    private func progressBar(_ value: Int, of total: Int) -> some View {
        let fraction = total > 0 ? min(1, max(0, Double(value) / Double(total))) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.orange).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(style.idleFill)
    }

    /// Solid chip, one colour per rarity. The fills are dark enough for white text in both light and dark mode.
    private func rarityChip(_ rarity: VisitorRarity) -> some View {
        Text(rarityLabel(rarity))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(rarityColour(rarity)))
    }

    /// Spotted count on a species card, styled like the seed count badges in the header tray.
    private func countBadge(_ count: Int) -> some View {
        Text("\u{00D7}\(count)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange))
            .offset(x: 6, y: -4)
    }

    private func rarityLabel(_ rarity: VisitorRarity) -> String {
        switch rarity {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        }
    }

    private func rarityColour(_ rarity: VisitorRarity) -> Color {
        switch rarity {
        case .common: Color(red: 0.20, green: 0.52, blue: 0.24)
        case .uncommon: Color(red: 0.13, green: 0.40, blue: 0.78)
        case .rare: Color(red: 0.48, green: 0.24, blue: 0.68)
        }
    }

    /// "+10" coin float beside the coin counter. Same behaviour as the seed shop.
    private func flashCoins(_ amount: Int) {
        noteID += 1
        let id = noteID
        coinNote = CoinNote(id: id, amount: amount)
        Task {
            try? await Task.sleep(for: .seconds(2))
            if coinNote?.id == id { coinNote = nil }
        }
    }
}
