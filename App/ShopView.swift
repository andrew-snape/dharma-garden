import SwiftUI
import DharmaGardenCore
import DharmaGardenArt

/// Seed shop, opened from the Shop tile in the tool bar. Drawn in the garden's own panel style, with a tab per
/// category and a card per seed. A seed the player cannot afford dims, and its buy buttons switch off.
struct ShopView: View {
    @ObservedObject var store: GardenStore
    let palette: ScenePalette
    @Environment(\.dismiss) private var dismiss
    @State private var category: FlowerCategory = .nativeFlower
    @State private var coinNote: CoinNote?
    @State private var noteID = 0

    /// Tabs in display order.
    private static let groups: [(title: String, category: FlowerCategory)] = [
        ("Native flowers", .nativeFlower),
        ("Exotic flowers", .exoticFlower),
        ("Herbs", .herb),
        ("Vegetables", .vegetable),
    ]

    var body: some View {
        GardenSheetFrame(title: "Seed Shop", palette: palette, coins: store.garden.coins, coinNote: coinNote,
                         onDone: { dismiss() }) { style in
            VStack(spacing: 12) {
                Picker("Category", selection: $category) {
                    ForEach(Self.groups, id: \.category) { Text($0.title).tag($0.category) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                .panel(style)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(FlowerType.allCases.filter { $0.category == category }, id: \.self) { f in
                            card(f, style)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    private func card(_ f: FlowerType, _ style: ScenePanelStyle) -> some View {
        let coins = store.garden.coins
        let canBuyOne = coins >= f.seedPrice
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                FlowerArt(flower: f, progress: 1)
                    .frame(width: 56, height: 56)
                    .opacity(canBuyOne ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(f.displayName).font(.headline)
                        if f.isNative {
                            Text("Native")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.25)))
                        }
                    }
                    Text("Ready to \(f.readyWord) in \(Int(f.daysToBloom.rounded())) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(f.sowSeasonHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            FlowLayout(spacing: 5) {
                ForEach(traits(f), id: \.self) { trait in
                    Text(trait)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(style.idleFill))
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(f.seedPrice) \(f.seedPrice == 1 ? "carrot" : "carrots") a seed").font(.callout.bold())
                    Text(canBuyOne ? "Owned: \(store.garden.seedCount(f))" : "Not enough carrots")
                        .font(.caption)
                        .foregroundStyle(canBuyOne ? Color.secondary : Color.orange)
                }
                Spacer()
                Button("Buy 1") { buy(f, 1) }
                    .buttonStyle(.bordered)
                    .disabled(coins < f.seedPrice)
                Button("Buy 3") { buy(f, 3) }
                    .buttonStyle(.borderedProminent)
                    .disabled(coins < f.seedPrice * 3)
            }
            .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(style)
        .accessibilityElement(children: .contain)
    }

    /// Trait chips for a plant, most important first.
    private func traits(_ f: FlowerType) -> [String] {
        var out: [String] = []
        if f.frostTender { out.append("frost tender") }
        if f.frostTolerant { out.append("frost tolerant") }
        if f.lovesHeat { out.append("loves heat") }
        if f.dryTolerant { out.append("dry tolerant") }
        if f.coolSeason { out.append("cool season") }
        if f.thirsty { out.append("thirsty") }
        return out
    }

    private func buy(_ f: FlowerType, _ count: Int) {
        var bought = false
        store.apply { bought = GardenEngine.buySeeds(f, count: count, in: &$0) }
        if bought { flashCoins(-f.seedPrice * count) }
    }

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

/// Wraps chips onto as many rows as the width needs.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
