import SwiftUI
import WeedsCore

extension GardenAdvice.Action {
    var symbol: String {
        switch self {
        case .pick: "basket.fill"
        case .water: "drop.fill"
        case .weed: "scissors"
        case .sow: "leaf.fill"
        case .shop: "bag.fill"
        }
    }
}

/// A small chip along the bottom of the scene: the most pressing thing the garden needs. Tapping it picks the tool
/// that answers it.
struct AdviceChip: View {
    let advice: GardenAdvice
    /// How many more things need doing after this one.
    let more: Int
    let style: ScenePanelStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: advice.action.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(advice.text).font(.callout.bold())
                if more > 0 {
                    Text("+\(more)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .panel(style)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(more > 0 ? "\(advice.text), and \(more) more things to do" : advice.text)
        .accessibilityHint("Picks the tool for this")
    }
}

/// The card shown once a day when the garden is first opened: a greeting, the weather and what needs doing.
struct DailySummaryCard: View {
    let greeting: String
    let weatherLine: String?
    let tips: [GardenAdvice]
    let rainExpected: Bool
    let style: ScenePanelStyle
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting).font(.title2.bold())
            if let weatherLine { Text(weatherLine).font(.callout).foregroundStyle(.secondary) }
            Divider()
            if tips.isEmpty {
                Label(ReminderText.fallback, systemImage: "checkmark.circle.fill")
                    .font(.callout.bold())
            } else {
                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                    Label(tip.text, systemImage: tip.action.symbol).font(.callout.bold())
                }
            }
            if rainExpected {
                Label("Rain is on the way today, so watering can wait", systemImage: "cloud.rain.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Into the garden", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .panel(style)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }
}
