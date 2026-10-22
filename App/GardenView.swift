import SwiftUI
import AppKit
import WeedsCore
import WeedsArt

enum Tool: Hashable { case water, weed, harvest, fork, seasol, fertiliser, plant(FlowerType) }

/// Seconds a feedback ring stays in the view's list. Rings last at most 1.6 s, so older ones are pruned.
private let rippleKeepSeconds: TimeInterval = 4.5
/// Ground distance between watering spots while sprinkling by dragging (about a tenth of the patch).
private let sprinkleSpacing = 0.04
/// How long the garden must sit still before its change rewrites the reminder (sprinkling changes it many times).
private let reminderDebounce: Duration = .milliseconds(1500)

/// A coin change to show briefly beside the coin counter. Positive is income, negative is spending.
struct CoinNote: Equatable {
    let id: Int
    let amount: Int
}

/// The "New entry" toast for a species spotted for the first time. Each note gets a new id, so it animates afresh.
struct EntryNote {
    let id: Int
    let name: String
}

/// "+12" (or a minus sign for spending) that fades out. Each note gets a new id, so it animates afresh.
struct CoinFloat: View {
    let amount: Int
    @State private var faded = false

    var body: some View {
        Text(amount >= 0 ? "+\(amount)" : "\u{2212}\(-amount)")
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(amount >= 0 ? Color.orange : Color.secondary)
            .opacity(faded ? 0 : 1)
            .fixedSize()
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 1.6)) { faded = true } }
    }
}

struct GardenView: View {
    @StateObject private var store = GardenStore()
    @StateObject private var weather = WeatherService()
    @StateObject private var settings = AppSettings()
    @StateObject private var location = LocationService()
    @StateObject private var reminders = ReminderService()
    @StateObject private var music = GardenMusic()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tool: Tool = .water
    /// The last place the player touched on the ground, marked with a ring.
    @State private var selectedPoint: GroundPoint?
    /// Where the pointer is over the patch, for the seed ghost. nil when it is off the scene.
    @State private var hoverPoint: GroundPoint?
    /// Feedback rings for recent actions (see `rippleKeepSeconds`).
    @State private var ripples: [SceneRipple] = []
    /// The last spot watered while sprinkling, so a drag waters every `sprinkleSpacing`.
    @State private var lastSprinkle: GroundPoint?
    /// True for a moment after a seed was tried on a spot that is not allowed: the ghost flashes red.
    @State private var flashInvalid = false
    @State private var flashToken = 0
    @State private var showSettings = false
    @State private var showShop = false
    @State private var showBook = false
    @State private var showLocationQuestion = false
    @State private var coinNote: CoinNote?
    @State private var noteID = 0
    /// Music starts only after the first window activation or garden tap, never at launch in silence.
    @State private var musicArmed = false
    /// Visitors on the patch right now. Live view state only: they are not saved (see `VisitorController`).
    @State private var visitors: [Visitor] = []
    @State private var roller = VisitorController()
    /// False while the app is in the background. No visitors are rolled then.
    @State private var appActive = true
    /// Early rolls still allowed before the regular cadence is all that is left (see `VisitorController`).
    @State private var earlyRollsLeft = VisitorController.earlyRollTries
    @State private var nextEarlyRoll = Date().addingTimeInterval(VisitorController.earlyRollSeconds)
    /// The "New entry" toast, when one is showing.
    @State private var entryNote: EntryNote?
    @State private var entryNoteID = 0
    /// The short action sounds (see `ToolSounds`). Played only while Settings has them on.
    @State private var sounds = ToolSounds()
    /// True while the once-a-day summary card is up.
    @State private var showSummary = false
    /// Seed types whose tile is pulsing because their count just went up.
    @State private var bumpedSeeds: Set<FlowerType> = []

    // Made once, not in `body`: a publisher built in `body` is a new one on every update, which can restart the countdown.
    private static let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private static let visitorTickTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private static let visitorCheckTimer = Timer.publish(every: Tuning.visitorCheckSeconds, on: .main, in: .common)
        .autoconnect()

    /// Keeps the open garden moving: fetches fresh weather when the report is due (which also catches up),
    /// otherwise catches the garden up with the weather already known. Waits while a fetch is in flight, so the
    /// catch-up uses the fresh report's past hours.
    func tick() async {
        if weather.needsRefresh(for: settings.activePlace) {
            await refreshAll()
        } else if !weather.isFetching {
            store.catchUp(weather: weather.report?.hourly ?? [])
        }
    }

    /// Weather for the active place, then the garden caught up with it, then the reminder rewritten.
    func refreshAll() async {
        await weather.refresh(for: settings.activePlace)
        store.catchUp(weather: weather.report?.hourly ?? [])
        await rescheduleReminder()
    }

    /// Asks the Mac for its town when "Use my location" is on. A failed fix keeps the last known place.
    func refreshLocation() async {
        guard settings.useDeviceLocation else { return }
        if let town = await location.currentTown() {
            settings.devicePlace = town
        }
    }

    /// Records the first-launch answer. "Use my location" turns the setting on, which asks macOS for permission
    /// through the existing location refresh. If permission is refused, the garden keeps the manual place.
    func answerLocationQuestion(useLocation: Bool) {
        settings.hasAskedLocation = true
        if useLocation { settings.useDeviceLocation = true }
    }

    /// Lets the music play from now on (fading in), if the user has it on.
    func armMusic() {
        musicArmed = true
        if settings.musicEnabled { music.start() }
    }

    func rescheduleReminder(delay: Duration = .zero) async {
        await reminders.reschedule(enabled: settings.reminderEnabled, minutes: settings.reminderMinutes,
                                   garden: store.garden, weather: weather.report?.hourly ?? [], delay: delay)
    }

    /// Palette for the scene: the live weather when known, otherwise a plain mild day.
    private var palette: ScenePalette {
        let theme = settings.sceneTheme.gardenTheme
        return weather.palette(theme: theme) ?? ScenePalette.resolve(season: weather.season, phase: .day, condition: .clear,
                                                                     temperatureC: 18, cloudCover: 0, theme: theme)
    }

    /// Wind for the scene, 0...1 from 0...40 km/h. A quarter of full wind when the weather is not known yet.
    private var windLevel: Double {
        guard let kmh = weather.report?.current.windKmh else { return 0.25 }
        return min(max(kmh / 40, 0), 1)
    }

    var body: some View {
        let style = ScenePanelStyle(palette: palette)
        ZStack {
            // Fills the whole window, including under the (hidden) title bar.
            SceneBackground(palette: palette).ignoresSafeArea()
            VStack(spacing: 12) {
                header(style)
                // The scene is the hero: it takes all the height the chrome does not need and the
                // GardenSceneView keeps its 4:3 frame inside that space.
                gardenScene
                toolBar(style)
#if DEBUG
                DebugPanel(store: store, onSpawn: spawnDebugVisitor)
                    .padding(10)
                    .panel(style)
#endif
            }
            // Top inset clears the traffic lights, which sit over the hidden title bar.
            .padding(.top, 34)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 640, minHeight: 720)
        .task {
            await tick()
            showSummaryIfDue()
        }
        .task { await refreshLocation() }
        .onAppear {
            // Asked once, on the very first launch only.
            if !settings.hasAskedLocation { showLocationQuestion = true }
            music.setVolume(settings.musicVolume)
            music.setMood(weather.mood(theme: settings.sceneTheme.gardenTheme))
        }
        .alert("Use your location for local weather?", isPresented: $showLocationQuestion) {
            Button("Use my location") { answerLocationQuestion(useLocation: true) }
            Button("Not now", role: .cancel) { answerLocationQuestion(useLocation: false) }
        } message: {
            Text("Your garden can match the weather and seasons to the town you are in. Until you say yes, the garden uses Mount Duneed, VIC. You can change this any time in Settings.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            music.resume()
            armMusic()
            appActive = true
            Task { await tick() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // The music keeps playing while another app is in front.
            appActive = false
            store.save()
        }
        // Time moves on while the window sits still: catch the garden up, and re-read the mood, every minute.
        .onReceive(Self.minuteTimer) { _ in
            Task { await tick() }
            music.setMood(weather.mood(theme: settings.sceneTheme.gardenTheme))
        }
        // Every couple of seconds: drop visitors that have left, and take an early roll if one is due.
        .onReceive(Self.visitorTickTimer) { now in
            pruneVisitors(at: now)
            if earlyRollsLeft > 0, now >= nextEarlyRoll, visitorsCanArrive {
                earlyRollsLeft -= 1
                nextEarlyRoll = now.addingTimeInterval(VisitorController.earlyRollSeconds)
                rollVisitor(at: now)
            }
        }
        // The regular cadence: one roll every few real minutes while the app is open.
        .onReceive(Self.visitorCheckTimer) { now in
            if visitorsCanArrive { rollVisitor(at: now) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // Synchronous: the process ends when this returns, so a started task would never finish.
            store.save()
            reminders.rescheduleBeforeQuit(enabled: settings.reminderEnabled, minutes: settings.reminderMinutes,
                                           garden: store.garden, weather: weather.report?.hourly ?? [])
        }
        .onChange(of: scenePhase) { _, phase in
            // Going inactive or to the background is the last chance to rewrite the reminder before it fires.
            if phase != .active {
                store.save()
                Task { await rescheduleReminder() }
            }
        }
        .onChange(of: settings.activePlace) { _, _ in
            Task { await refreshAll() }
        }
        .onChange(of: settings.useDeviceLocation) { _, on in
            if on { Task { await refreshLocation() } }
        }
        .onChange(of: settings.reminderEnabled) { _, _ in Task { await rescheduleReminder() } }
        .onChange(of: settings.reminderMinutes) { _, _ in Task { await rescheduleReminder() } }
        .onChange(of: store.garden) { _, _ in Task { await rescheduleReminder(delay: reminderDebounce) } }
        .onChange(of: weather.report) { _, _ in
            Task { await rescheduleReminder() }
            music.setMood(weather.mood(theme: settings.sceneTheme.gardenTheme))
        }
        .onChange(of: settings.sceneTheme) { _, theme in music.setMood(weather.mood(theme: theme.gardenTheme)) }
        .onChange(of: settings.musicEnabled) { _, on in
            if on { armMusic() } else { music.stop() }
        }
        .onChange(of: settings.musicVolume) { _, volume in music.setVolume(volume) }
        // A seed tile pulses when its count goes up (bought in the shop, or a milestone reward).
        .onChange(of: store.garden.seedStock) { old, new in
            let up = Set(FlowerType.allCases.filter { (new[$0.rawValue] ?? 0) > (old[$0.rawValue] ?? 0) })
            guard !up.isEmpty else { return }
            bumpedSeeds.formUnion(up)
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                bumpedSeeds.subtract(up)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store, settings: settings, location: location, reminders: reminders, palette: palette)
        }
        .sheet(isPresented: $showShop) {
            ShopView(store: store, palette: palette)
        }
        .sheet(isPresented: $showBook) {
            GardenBookView(store: store, palette: palette)
        }
    }

    private func header(_ style: ScenePanelStyle) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Dharma Garden").font(.title.bold())
                WeatherLine(weather: weather)
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "circle.fill").foregroundStyle(.orange)
                Text("\(store.garden.coins)").font(.title3.bold().monospacedDigit())
            }
            .overlay(alignment: .leading) {
                if let note = coinNote { CoinFloat(amount: note.amount).id(note.id).offset(x: -44) }
            }
            Button { settings.musicEnabled.toggle() } label: {
                Image(systemName: settings.musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(settings.musicEnabled ? "Mute garden music" : "Play garden music")
            .accessibilityLabel(settings.musicEnabled ? "Mute garden music" : "Play garden music")
            Button { showBook = true } label: {
                Image(systemName: "book.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        // A dot while a milestone can be claimed in the book.
                        if hasClaimableMilestone {
                            Circle().fill(Color.orange).frame(width: 8, height: 8).offset(x: 1, y: -1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("Garden book")
            .accessibilityLabel(hasClaimableMilestone ? "Garden book, milestone ready to claim" : "Garden book")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .panel(style)
    }

    /// The tools on one row, with a scrollable tray of the seed packets the player owns. Keys 1 to 7 pick a tool
    /// (7 opens the shop). Seasol and Fertiliser cost coins, so they dim when the player cannot pay.
    private func toolBar(_ style: ScenePanelStyle) -> some View {
        let coins = store.garden.coins
        return VStack(spacing: 7) {
            HStack(spacing: 5) {
                toolTile("Water", "drop.fill", key: "1", selected: tool == .water, style) { tool = .water }
                toolTile("Weed", "scissors", key: "2", selected: tool == .weed, style) { tool = .weed }
                toolTile("Pick", "basket.fill", key: "3", selected: tool == .harvest, style) { tool = .harvest }
                toolTile("Fork", "rectangle.split.3x1.fill", key: "4", selected: tool == .fork, style) { tool = .fork }
                toolTile("Seasol", "water.waves", key: "5", cost: Tuning.seasolCost, coins: coins,
                         selected: tool == .seasol, style) { tool = .seasol }
                toolTile("Fertiliser", "leaf.arrow.circlepath", key: "6", cost: Tuning.fertiliserCost, coins: coins,
                         selected: tool == .fertiliser, style) { tool = .fertiliser }
                toolTile("Shop", "bag.fill", key: "7", selected: false, style) { showShop = true }
            }
            seedTray(style)
        }
        .padding(7)
        .panel(style)
    }

    /// Equal-width tiles, so every label fits without truncation at 640 pt. A tile with a `cost` shows it as a badge
    /// and dims, and cannot be picked, while `coins` fall short (an already-picked tool stays pickable).
    private func toolTile(_ title: String, _ icon: String, key: KeyEquivalent, cost: Int? = nil, coins: Int = 0,
                          selected: Bool, _ style: ScenePanelStyle, action: @escaping () -> Void) -> some View {
        let text: Color = selected ? .white : .primary
        let affordable = cost.map { coins >= $0 } ?? true
        return Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(text)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? style.selectedFill : style.idleFill)
            )
            .overlay(alignment: .topLeading) {
                // Key hint, so the shortcut can be found without a manual.
                Text(String(key.character))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(text.opacity(0.6))
                    .padding(.leading, 5)
                    .padding(.top, 3)
            }
            .overlay(alignment: .topTrailing) {
                if let cost {
                    Text("\(cost)")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                        .offset(x: 3, y: -4)
                }
            }
            .opacity(affordable || selected ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .disabled(!affordable && !selected)
        .help(cost.map { "\(title): \($0) coins a use (key \(String(key.character)))" } ?? "\(title) (key \(String(key.character)))")
        .accessibilityLabel(cost.map { "\(title), \($0) coins" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Seed types with at least one packet, as tiles in a horizontal scroll. Selecting one arms the plant tool.
    private func seedTray(_ style: ScenePanelStyle) -> some View {
        let owned = FlowerType.allCases.filter { store.garden.seedCount($0) > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Seeds").font(.caption.bold()).foregroundStyle(.secondary)
            if owned.isEmpty {
                Text("No seeds left. Visit the Shop to buy more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(owned, id: \.self) { seedTile($0, style) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seedTile(_ f: FlowerType, _ style: ScenePanelStyle) -> some View {
        let selected = tool == .plant(f)
        let text: Color = selected ? .white : .primary
        return Button { tool = .plant(f) } label: {
            VStack(spacing: 2) {
                FlowerArt(flower: f, progress: 1)
                    .frame(width: 34, height: 34)
                Text(f.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 96, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? style.selectedFill : style.idleFill)
            )
            .overlay(alignment: .topTrailing) {
                Text("\(store.garden.seedCount(f))")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
                    .offset(x: 4, y: -4)
            }
            .scaleEffect(bumpedSeeds.contains(f) ? 1.12 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: bumpedSeeds)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.displayName), \(store.garden.seedCount(f)) seeds")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The garden scene with the visitors on it and the "New entry" toast along its top.
    private var gardenScene: some View {
        GardenSceneView(garden: store.garden, palette: palette,
                        selectedPoint: selectedPoint, hoverPoint: hoverPoint,
                        ghostFlower: ghostFlower, ghostValid: ghostValid,
                        ripples: ripples,
                        onTap: handleTap, onDrag: handleDrag,
                        onHover: { hoverPoint = $0 },
                        wind: windLevel, driftEnabled: settings.gentleDrift,
                        style: settings.sceneStyle, theme: settings.sceneTheme,
                        visitors: visitors, onSpotVisitor: spotVisitor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { entryToastLayer }
            .overlay(alignment: .topLeading) { plantCardLayer }
            .overlay(alignment: .bottom) { adviceLayer }
            .overlay { summaryLayer }
    }

    /// The chip for the most pressing job. Hidden while the daily summary is up, which already lists the jobs.
    @ViewBuilder private var adviceLayer: some View {
        let tips = GardenAdvice.tips(for: store.garden)
        if !showSummary, let first = tips.first {
            AdviceChip(advice: first, more: tips.count - 1, style: ScenePanelStyle(palette: palette)) {
                follow(first)
            }
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    /// Picks the tool (or opens the shop) that answers a piece of advice.
    private func follow(_ advice: GardenAdvice) {
        switch advice.action {
        case .pick: tool = .harvest
        case .water: tool = .water
        case .weed: tool = .weed
        case .shop: showShop = true
        case .sow:
            if let seed = FlowerType.allCases.first(where: { store.garden.seedCount($0) > 0 }) { tool = .plant(seed) }
        }
    }

    @ViewBuilder private var summaryLayer: some View {
        if showSummary {
            ZStack {
                Color.black.opacity(0.25).onTapGesture { showSummary = false }
                DailySummaryCard(greeting: GardenAdvice.greeting(at: Date()),
                                 weatherLine: weatherSummary,
                                 tips: GardenAdvice.tips(for: store.garden),
                                 rainExpected: GardenAdvice.rainExpected(in: weather.report?.hourly ?? [], from: Date()),
                                 style: ScenePanelStyle(palette: palette)) { showSummary = false }
            }
            .transition(.opacity)
        }
    }

    /// "18°C · Clear · Spring" when the weather is known.
    private var weatherSummary: String? {
        guard let r = weather.report else { return nil }
        return "\(Int(r.current.temperatureC.rounded()))°C · \(r.current.condition.label) · \(weather.season.rawValue.capitalized)"
    }

    /// Shows the summary the first time the garden is opened on a calendar day. Not on the very first launch
    /// (the location question is up then), and never twice in a day.
    private func showSummaryIfDue() {
        guard settings.hasAskedLocation, !showLocationQuestion else { return }
        let day = Date().formatted(.iso8601.year().month().day())
        guard settings.lastSummaryDay != day else { return }
        settings.lastSummaryDay = day
        withAnimation(.easeOut(duration: 0.25)) { showSummary = true }
    }

    private func playSound(_ sound: ToolSound) {
        guard settings.soundEffectsEnabled else { return }
        sounds.play(sound)
    }

    private func sound(for tool: Tool) -> ToolSound {
        switch tool {
        case .water: .water
        case .weed: .pull
        case .harvest: .pick
        case .fork: .fork
        case .seasol, .fertiliser: .feed
        case .plant: .plant
        }
    }

    /// The card for the plant under the pointer. Hidden while a seed is armed, since the ghost is the focus then.
    @ViewBuilder private var plantCardLayer: some View {
        if ghostFlower == nil, let p = hoverPoint,
           let plant = GardenEngine.nearestPlant(to: p, in: store.garden, reach: Tuning.pullReach * 1.5) {
            PlantCard(plant: plant, garden: store.garden, style: ScenePanelStyle(palette: palette))
                .padding(8)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var entryToastLayer: some View {
        if let note = entryNote {
            EntryToast(name: note.name).id(note.id).padding(.top, 8)
        }
    }

    /// True while a collection milestone is reached and not yet claimed (shows the dot on the book button).
    private var hasClaimableMilestone: Bool {
        !GardenEngine.claimableMilestones(in: store.garden).isEmpty
    }

    /// The seed the plant tool would sow, if that tool is armed.
    private var ghostFlower: FlowerType? {
        if case .plant(let f) = tool { return f }
        return nil
    }

    /// Whether the seed ghost is drawn as allowed: the spot under the pointer is clear, unless a recent try was refused.
    private var ghostValid: Bool? {
        if flashInvalid { return false }
        guard let p = hoverPoint else { return nil }
        return GardenEngine.canPlant(at: p, in: store.garden)
    }

    /// A tap on the patch uses the armed tool there. A tap that misses the ground does nothing.
    func handleTap(_ point: GroundPoint?) {
        guard let p = point else { return }
        selectedPoint = p
        lastSprinkle = nil
        armMusic()
        use(tool, at: p)
    }

    /// Dragging with the water tool sprinkles: a spot every `sprinkleSpacing` along the way.
    func handleDrag(_ point: GroundPoint?) {
        guard tool == .water || tool == .fork, let p = point else { return }
        if let last = lastSprinkle, last.distance(to: p) < sprinkleSpacing { return }
        if lastSprinkle == nil { armMusic() }
        let previous = lastSprinkle
        lastSprinkle = p
        selectedPoint = p
        if tool == .fork {
            dragFork(from: previous, to: p)
        } else {
            use(.water, at: p)
        }
    }

    /// One step of a fork drag: aerates at `p` and draws the lines from where the last step was. The first step
    /// of a drag has no line yet, so it shows the fork going in.
    private func dragFork(from previous: GroundPoint?, to p: GroundPoint) {
        guard let previous else {
            use(.fork, at: p)
            return
        }
        // A line only runs along ground that is bed all the way. Crossing the lawn between two beds starts afresh.
        guard Self.bedSpans(from: previous, to: p, in: store.garden.plot) else {
            use(.fork, at: p)
            return
        }
        store.apply { g in GardenEngine.aerate(at: p, in: &g) }
        addRipple(p, .furrow, from: previous)
        playSound(.fork)
    }

    /// True when the straight line from `a` to `b` stays on the bed (sampled along its length).
    private static func bedSpans(from a: GroundPoint, to b: GroundPoint, in plot: PlotShape) -> Bool {
        (0...8).allSatisfy { i in
            let f = Double(i) / 8
            return plot.contains(GroundPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
    }

    /// Applies one player action at a ground point and shows its feedback. A seed on a spot that is not allowed
    /// changes nothing and flashes the ghost red.
    func use(_ tool: Tool, at p: GroundPoint) {
        let coinsBefore = store.garden.coins
        var acted = false
        store.apply { g in
            switch tool {
            case .water:
                GardenEngine.water(at: p, in: &g)
                acted = true
            case .weed:
                acted = GardenEngine.pullWeed(at: p, in: &g)
            case .harvest:
                acted = GardenEngine.harvest(at: p, in: &g) != nil
            case .fork:
                acted = GardenEngine.aerate(at: p, in: &g)
            case .seasol:
                acted = GardenEngine.applySeasol(at: p, in: &g)
            case .fertiliser:
                acted = GardenEngine.applyFertiliser(at: p, in: &g)
            case .plant(let f):
                acted = GardenEngine.sow(f, at: p, in: &g)
            }
        }
        let gained = store.garden.coins - coinsBefore
        if gained != 0 { flashCoins(gained) }
        if gained > 0 { playSound(.coin) }
        // The fork always shows going in on the bed, even where the soil is already loose.
        if acted || (tool == .fork && store.garden.plot.contains(p)) {
            addRipple(p, kind(for: tool))
            playSound(sound(for: tool))
        } else if case .plant = tool {
            flashRefusedSeed()
        }
        // The last packet of the armed seed is used: go back to watering.
        if case .plant(let f) = tool, store.garden.seedCount(f) == 0 { self.tool = .water }
    }

    private func kind(for tool: Tool) -> SceneRipple.Kind {
        switch tool {
        case .water: .water
        case .weed: .pull
        case .harvest: .pick
        case .fork: .aerate
        case .seasol: .seasol
        case .fertiliser: .fertilise
        case .plant: .plant
        }
    }

    /// Visitors only arrive while the app is active and no sheet or alert is open.
    private var visitorsCanArrive: Bool {
        appActive && !showSettings && !showShop && !showBook && !showLocationQuestion
    }

    /// Makes one visitor (if the roll brings one) and adds it to the patch.
    private func rollVisitor(at now: Date) {
        let context = VisitorController.context(report: weather.report, garden: store.garden, now: now)
        guard let visitor = roller.roll(garden: store.garden, context: context, now: now, live: visitors) else { return }
        visitors.append(visitor)
        earlyRollsLeft = 0
    }

    /// Removes visitors that have left. Only writes when one has gone, so the scene is not redrawn for nothing.
    private func pruneVisitors(at now: Date) {
        if visitors.contains(where: { $0.isGone(at: now) }) {
            visitors.removeAll { $0.isGone(at: now) }
        }
    }

    /// Tapping a visitor spots it: it pays its coins, counts in the book, and leaves the patch.
    /// The first sighting of a species also shows the "New entry" toast.
    func spotVisitor(_ visitor: Visitor) {
        guard let index = visitors.firstIndex(where: { $0.id == visitor.id }) else { return }
        visitors.remove(at: index)
        var spotted = (coins: 0, isNewEntry: false)
        store.apply { spotted = GardenEngine.spot(visitor, in: &$0) }
        if spotted.coins > 0 { flashCoins(spotted.coins) }
        addRipple(visitor.position, .spot)
        playSound(.spot)
        if spotted.isNewEntry { flashEntry(visitor.species.displayName) }
        armMusic()
    }

#if DEBUG
    /// Debug only: puts a visitor of the chosen species at a random point on the patch.
    func spawnDebugVisitor(_ species: VisitorSpecies) {
        visitors.append(roller.spawn(species, garden: store.garden, now: Date()))
    }
#endif

    /// Adds a ring for an action and drops rings that have finished.
    private func addRipple(_ p: GroundPoint, _ kind: SceneRipple.Kind, from: GroundPoint? = nil) {
        let now = Date()
        ripples.removeAll { now.timeIntervalSince($0.startedAt) > rippleKeepSeconds }
        ripples.append(SceneRipple(point: p, startedAt: now, kind: kind, from: from))
    }

    /// The seed ghost turns red for a moment.
    private func flashRefusedSeed() {
        flashToken += 1
        let token = flashToken
        flashInvalid = true
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            if flashToken == token { flashInvalid = false }
        }
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

    /// Shows the "New entry" toast for a moment. The toast fades on its own, and is cleared after it has faded.
    private func flashEntry(_ name: String) {
        entryNoteID += 1
        let id = entryNoteID
        entryNote = EntryNote(id: id, name: name)
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if entryNote?.id == id { entryNote = nil }
        }
    }
}

/// One line of weather under the title: "18°C · Clear · Spring".
struct WeatherLine: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        HStack(spacing: 6) {
            if let r = weather.report {
                Text("\(Int(r.current.temperatureC.rounded()))°C · \(r.current.condition.label) · \(weather.season.rawValue.capitalized)")
                if weather.isStale {
                    Text("(updated \(Int(r.age(at: Date()) / 60)) min ago)").foregroundStyle(.secondary)
                }
            } else if weather.lastFetchFailed {
                Text("Can't reach the weather right now").foregroundStyle(.secondary)
            } else {
                Text("Checking the weather…").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

struct SceneBackground: View {
    let palette: ScenePalette?
    func c(_ x: RGB) -> Color { Color(red: x.r, green: x.g, blue: x.b) }
    var body: some View {
        if let p = palette {
            ZStack {
                LinearGradient(colors: [c(p.skyTop), c(p.skyBottom), c(p.grass)], startPoint: .top, endPoint: .bottom)
                Color(red: p.overlayTint.r, green: p.overlayTint.g, blue: p.overlayTint.b).opacity(p.overlayStrength)
                Color.white.opacity(p.fogStrength * 0.5)
                Color.black.opacity(p.darkness)
            }
            .ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
