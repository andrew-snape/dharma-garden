import SwiftUI
import DharmaGardenCore

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


extension SideChore {
    var symbol: String {
        switch self {
        case .feedBirds: "bird.fill"
        case .deadhead: "scissors"
        case .compost: "leaf.arrow.circlepath"
        }
    }
}

/// A chip along the bottom of the scene for when nothing needs doing: a small side chore to do. Tapping does it.
struct ChoreChip: View {
    let chore: SideChore
    /// How many more chores are on offer after this one.
    let more: Int
    let style: ScenePanelStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: chore.symbol).font(.system(size: 12, weight: .semibold))
                Text(chore.title).font(.callout.bold())
                if chore.cost > 0 {
                    Text("\(chore.cost)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
                if more > 0 {
                    Text("+\(more)").font(.caption2.bold().monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .panel(style)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(chore.detail)
        .accessibilityLabel(chore.cost > 0 ? "\(chore.title), \(chore.cost) coin" : chore.title)
        .accessibilityHint(chore.detail)
    }
}

/// "While you were away": what grew, faded or appeared in the time the garden ran without the player.
/// It fades out by itself after a while, or on a tap.
struct AwayCard: View {
    let summary: AwaySummary
    let style: ScenePanelStyle
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome back").font(.headline)
            Text("You were away for \(summary.awayText)").font(.caption).foregroundStyle(.secondary)
            ForEach(summary.lines, id: \.self) { line in
                Label(line, systemImage: "leaf.fill").font(.callout)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 220, alignment: .leading)
        .panel(style)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .task {
            try? await Task.sleep(for: .seconds(14))
            onDone()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to dismiss")
    }
}
