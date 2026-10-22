import SwiftUI
import WeedsCore

/// How the garden scene is framed: the close first-person view, or a wider 3/4 view of the whole yard.
public enum SceneStyle: String, CaseIterable, Sendable {
    case firstPerson, backyard

    public var displayName: String {
        switch self {
        case .firstPerson: "First person"
        case .backyard: "Backyard"
        }
    }
}

/// A feedback ring on the soil at a ground point, drawn for a short time after an action.
public struct SceneRipple: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case water, plant, pull, pick, spot, aerate, seasol, fertilise, furrow }

    public var point: GroundPoint
    public var startedAt: Date
    public var kind: Kind
    /// Where a furrow starts: the fork was dragged from here to `point`. nil for every other kind.
    public var from: GroundPoint?

    public init(point: GroundPoint, startedAt: Date, kind: Kind, from: GroundPoint? = nil) {
        self.point = point
        self.startedAt = startedAt
        self.kind = kind
        self.from = from
    }

    /// Seconds the ring lasts. Watering spreads wider and slower than the other actions; the tool actions run
    /// long enough to see the can pour, the granules fall and the fork go in, and a furrow lingers on the soil.
    public var duration: Double {
        switch kind {
        case .water: 1.8
        case .aerate: 1.2
        case .seasol, .fertilise: 1.5
        case .furrow: 4.0
        case .plant, .pull, .pick, .spot: 0.9
        }
    }

    /// Radius reached at the end, in ground units.
    public var maxRadius: Double {
        switch kind {
        case .water: Tuning.waterRadius
        case .plant: 0.05
        case .pull: 0.035
        case .pick: 0.05
        case .spot: 0.05
        case .aerate, .seasol, .fertilise: Tuning.treatRadius
        case .furrow: 0.03
        }
    }
}

/// The garden as a scene: a soft-edged patch of soil on the lawn, seen from about 45 degrees above, in a 4:3
/// frame that scales with its container. A press that stays put calls `onTap` with the ground point under it
/// (nil when it misses the ground). A press that moves calls `onDrag` with the ground point under the pointer as
/// it moves (the water tool sprinkles along the drag). The pointer's ground point is reported by `onHover` (nil
/// when it leaves the scene), so the caller can show a seed ghost.
///
/// The scene animates at 30 fps (60 fps while the player is acting): a gentle camera drift with depth parallax, plant sway scaled by
/// `wind`, drifting clouds, falling rain, a fog pulse and feedback rings. It pauses to a static frame when
/// Reduce Motion is on, when `driftEnabled` is false, or when the app is not active.
///
/// Layers, back to front: sky and clouds, hills, lawn, fence, the soil patch with its shadows, rings and
/// markers, then plants and weeds depth sorted by ground depth (planter box fronts are sorted in with them, and the
/// seed ghost stays on top), the foreground,
/// then the light and weather overlays.
public struct GardenSceneView: View {
    public var garden: Garden
    public var palette: ScenePalette
    public var camera: Camera
    /// A point to mark (the last tap), or nil.
    public var selectedPoint: GroundPoint?
    /// Where the cursor or the last tap is. With `ghostFlower` set, a translucent seed preview is drawn here.
    public var hoverPoint: GroundPoint?
    /// The seed the player is about to plant. nil draws no ghost.
    public var ghostFlower: FlowerType?
    /// Whether the ghost spot is allowed (red when not). nil works it out from the garden: on the patch and
    /// clear of living plants.
    public var ghostValid: Bool?
    /// Feedback rings. Each runs for its kind's duration after `startedAt`, then disappears.
    public var ripples: [SceneRipple]
    /// Called with the ground point under a press that stays put, or nil when it misses the ground.
    public var onTap: ((GroundPoint?) -> Void)?
    /// Called with the ground point under the pointer while a press moves (after it has travelled a few points).
    public var onDrag: ((GroundPoint?) -> Void)?
    /// Called with the ground point under the pointer as it moves over the scene, and nil when it leaves.
    public var onHover: ((GroundPoint?) -> Void)?
    /// Wind 0...1. Scales camera drift, plant sway and the speed of rain.
    public var wind: Double
    /// Turns the gentle camera drift and other motion on or off. A static frame is drawn when off.
    public var driftEnabled: Bool
    /// Framing and backdrop: first person (the default) or the wider backyard view.
    public var style: SceneStyle
    /// The theme of the surroundings (horizon, barrier, buildings, ambient touches): farm by default.
    public var theme: SceneTheme
    /// Visitors on the patch: drawn with the plants, each posed by `VisitorMotion` at the frame's time.
    public var visitors: [Visitor]
    /// Called with a visitor whose body a press lands on (the nearest one wins). The press then does not also call
    /// `onTap`. With no callback, a press on a visitor counts as an ordinary tap.
    public var onSpotVisitor: ((Visitor) -> Void)?
    /// Called when a press lands on the reading chair on the lawn. The press then does not also call `onTap`. With no
    /// callback the chair is still drawn, and a press on it counts as an ordinary tap.
    public var onSitInChair: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Plant size relative to the scene width, at the garden centre (scale 1). 20 percent smaller than the first
    /// free-form pass, so plants sit on the larger patch without crowding.
    static let plantSize = 0.112
    /// Weed size relative to the scene width, at scale 1.
    static let weedSize = 0.1
    /// Visitor square side relative to the scene width, at scale 1.
    static let visitorSize = 0.07
    /// Where the plant's soil mound sits within FlowerArt's square (its 0.86 base line).
    static let mound = 0.86

    public init(garden: Garden, palette: ScenePalette, camera: Camera = Camera(),
                selectedPoint: GroundPoint? = nil, hoverPoint: GroundPoint? = nil,
                ghostFlower: FlowerType? = nil, ghostValid: Bool? = nil,
                ripples: [SceneRipple] = [], onTap: ((GroundPoint?) -> Void)? = nil,
                onDrag: ((GroundPoint?) -> Void)? = nil, onHover: ((GroundPoint?) -> Void)? = nil,
                wind: Double = 0.25, driftEnabled: Bool = true, style: SceneStyle = .firstPerson,
                theme: SceneTheme = .farm, visitors: [Visitor] = [], onSpotVisitor: ((Visitor) -> Void)? = nil,
                onSitInChair: (() -> Void)? = nil) {
        self.garden = garden
        self.palette = palette
        self.camera = camera
        self.selectedPoint = selectedPoint
        self.hoverPoint = hoverPoint
        self.ghostFlower = ghostFlower
        self.ghostValid = ghostValid
        self.ripples = ripples
        self.onTap = onTap
        self.onDrag = onDrag
        self.onHover = onHover
        self.wind = wind
        self.driftEnabled = driftEnabled
        self.style = style
        self.theme = theme
        self.visitors = visitors
        self.onSpotVisitor = onSpotVisitor
        self.onSitInChair = onSitInChair
    }

    /// The camera this style draws with: the backyard style always uses `Camera.backyard`.
    private var framing: Camera { style == .backyard ? .backyard : camera }

    /// Paused means a static frame: zero drift, zero sway, nothing moving.
    private var isPaused: Bool {
        reduceMotion || !driftEnabled || scenePhase != .active
    }

    /// Seconds between frames: 60 fps while the player is acting (a feedback ring is still running, or a seed ghost
    /// follows the pointer), otherwise 30 fps for the slow ambient motion. The scene stops completely (see `isPaused`)
    /// when the app is not active, so a backgrounded garden costs nothing.
    private var frameInterval: TimeInterval {
        let now = Date()
        let acting = ripples.contains { (0...$0.duration).contains(now.timeIntervalSince($0.startedAt)) }
            || (ghostFlower != nil && hoverPoint != nil)
        return acting ? 1.0 / 60.0 : 1.0 / 30.0
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: isPaused)) { timeline in
            SceneContent(garden: garden, palette: palette, camera: framing,
                         selectedPoint: selectedPoint, hoverPoint: hoverPoint,
                         ghostFlower: ghostFlower, ghostValid: ghostValid, ripples: ripples, now: timeline.date,
                         motion: SceneMotion.Frame(time: timeline.date.timeIntervalSinceReferenceDate,
                                                   wind: wind, enabled: !isPaused),
                         onTap: onTap, onDrag: onDrag, onHover: onHover, style: style,
                         theme: theme, visitors: visitors, onSpotVisitor: onSpotVisitor,
                         onSitInChair: onSitInChair)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
    }
}

/// One entry in the depth order: a plant or a weed, with the ground depth it is sorted by.
struct SceneDepthEntry: Equatable {
    let id: Int
    let isPlant: Bool
    let depth: Double
}

/// One item in the back-to-front draw order: a plant or weed, or the front board of a planter box (which hides the
/// plants behind it and is hidden by the ones in front of it).
enum SceneDrawItem: Equatable {
    case entry(SceneDepthEntry)
    case boxFront(Int)
    case visitor(Int)

    /// A stable identity for `ForEach`.
    var key: String {
        switch self {
        case .entry(let e): (e.isPlant ? "p" : "w") + String(e.id)
        case .boxFront(let box): "b" + String(box)
        case .visitor(let id): "v" + String(id)
        }
    }
}

/// Water rings closer together than this (in seconds) count as one continuous pour.
private let pourLinkSeconds = 0.6

/// A ripple that is on screen now: its point, kind and how far through its life it is (0...1).
struct ActiveRing {
    let point: GroundPoint
    let kind: SceneRipple.Kind
    let progress: Double
    /// Radius reached at the end, in ground units.
    let maxRadius: Double
    /// Where a furrow starts (see `SceneRipple.from`).
    var from: GroundPoint? = nil
    /// Whether this ring draws the watering can. Only the newest water ring does, so sprinkling shows one can
    /// following the pointer instead of one per spot.
    var showsCan = true
    /// True when this water ring follows another one closely (a sprinkling drag): its can stays tilted rather than
    /// tipping in again at every spot.
    var continuesPour = false
}

/// One drawn frame of the scene for a given motion state. `GardenSceneView` feeds it the timeline's frame;
/// tests can feed it any frame to render a fixed moment.
struct SceneContent: View {
    let garden: Garden
    let palette: ScenePalette
    /// The undrifted camera. The drift from `motion` is applied on top of it.
    let camera: Camera
    var selectedPoint: GroundPoint? = nil
    var hoverPoint: GroundPoint? = nil
    var ghostFlower: FlowerType? = nil
    var ghostValid: Bool? = nil
    var ripples: [SceneRipple] = []
    /// The time the frame is drawn at, for ripple ages.
    var now: Date = .distantPast
    let motion: SceneMotion.Frame
    var onTap: ((GroundPoint?) -> Void)? = nil
    var onDrag: ((GroundPoint?) -> Void)? = nil
    var onHover: ((GroundPoint?) -> Void)? = nil
    var style: SceneStyle = .firstPerson
    var theme: SceneTheme = .farm
    var visitors: [Visitor] = []
    var onSpotVisitor: ((Visitor) -> Void)? = nil
    var onSitInChair: (() -> Void)? = nil

    /// Pointer travel (points) that turns a press into a drag rather than a tap.
    static let tapSlop: Double = 6

    /// True once the press has travelled past `tapSlop` (kept in the view so a drag never also counts as a tap).
    @State private var dragging = false

    /// Everything standing on the patch, back to front: smaller ground depth first, then by id.
    static func depthOrder(of garden: Garden) -> [SceneDepthEntry] {
        let plants = garden.plants.map { SceneDepthEntry(id: $0.id, isPlant: true, depth: $0.position.y) }
        let weeds = garden.weeds.map { SceneDepthEntry(id: $0.id, isPlant: false, depth: $0.position.y) }
        return (plants + weeds).sorted { ($0.depth, $0.id) < ($1.depth, $1.id) }
    }

    /// `depthOrder` with each planter box's front board placed by its depth too, so a board covers the plants behind
    /// it and goes under the plants in front of it. Visitors go in by their ground depth (`visitors` gives each one's
    /// id and depth), so a creature standing in front of a plant is drawn over it.
    static func drawOrder(of garden: Garden, visitors: [(id: Int, depth: Double)] = []) -> [SceneDrawItem] {
        var keyed: [(item: SceneDrawItem, depth: Double, id: Int)] = depthOrder(of: garden).map {
            (item: SceneDrawItem.entry($0), depth: $0.depth, id: $0.id)
        }
        for (box, depth) in SceneCanvas.planterFrontDepths(garden.plot).enumerated() {
            keyed.append((item: SceneDrawItem.boxFront(box), depth: depth, id: -1 - box))
        }
        for v in visitors {
            keyed.append((item: SceneDrawItem.visitor(v.id), depth: v.depth, id: v.id))
        }
        return keyed.sorted { ($0.depth, $0.id) < ($1.depth, $1.id) }.map(\.item)
    }

    /// Ripples that are alive at `now`, with how far through their life each one is.
    static func activeRings(_ ripples: [SceneRipple], now: Date) -> [ActiveRing] {
        let alive = ripples.filter { (0...$0.duration).contains(now.timeIntervalSince($0.startedAt)) }
        let waterStarts = alive.filter { $0.kind == .water }.map(\.startedAt)
        let newestWater = waterStarts.max()
        return alive.map { r in
            var ring = ActiveRing(point: r.point, kind: r.kind, progress: now.timeIntervalSince(r.startedAt) / r.duration,
                                  maxRadius: r.maxRadius, from: r.from)
            if r.kind == .water {
                ring.showsCan = r.startedAt == newestWater
                ring.continuesPour = waterStarts.contains { $0 < r.startedAt && r.startedAt.timeIntervalSince($0) < pourLinkSeconds }
            }
            return ring
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let drifted = SceneMotion.camera(camera, frame: motion)
            let plants = Dictionary(uniqueKeysWithValues: garden.plants.map { ($0.id, $0) })
            let weeds = Dictionary(uniqueKeysWithValues: garden.weeds.map { ($0.id, $0) })
            let visible = Self.visiblePoses(visitors, now: now)
            let visibleByID = Dictionary(visible.map { ($0.visitor.id, $0) }, uniquingKeysWith: { first, _ in first })
            let visitorDepths = visible.map { (id: $0.visitor.id, depth: $0.pose.position.y + 0.02) }
            ZStack(alignment: .topLeading) {
                // Sky and clouds, then hills: both shifted by their parallax depth.
                Canvas { ctx, cs in
                    canvas(ctx, cs, camera, .sky).drawThemeSky()
                    canvas(ctx, cs, camera, .sky).drawThemeClouds()
                    canvas(ctx, cs, camera, .hills).drawThemeHorizon()
                }
                // Lawn follows the drifted camera (the ground layer moves with the drift itself).
                Canvas { ctx, cs in
                    canvas(ctx, cs, drifted, nil).drawThemeGround()
                }
                Canvas { ctx, cs in
                    if style == .backyard {
                        canvas(ctx, cs, camera, .fence).drawThemeBackdropProps()
                    }
                    canvas(ctx, cs, camera, .fence).drawThemeBarrier()
                    if style == .backyard {
                        canvas(ctx, cs, camera, .fence).drawThemeSideBarriers()
                    }
                }
                // The soil patch, its shadows and feedback rings, all on the ground.
                Canvas { ctx, cs in
                    canvas(ctx, cs, drifted, nil).drawPatch(garden, rings: Self.activeRings(ripples, now: now),
                                                            selected: selectedPoint, ghost: ghostSpot)
                }
                // The reading chair on the lawn, behind the plants and visitors.
                Canvas { ctx, cs in
                    canvas(ctx, cs, drifted, nil).drawChair()
                }
                .allowsHitTesting(false)
                // Plants and weeds, back to front by ground depth.
                ForEach(Self.drawOrder(of: garden, visitors: visitorDepths), id: \.key) { item in
                    switch item {
                    case .entry(let entry):
                        if entry.isPlant, let plant = plants[entry.id] {
                            plantView(plant, size: size, camera: drifted)
                        } else if let weed = weeds[entry.id] {
                            weedView(weed, size: size, camera: drifted)
                        }
                    case .visitor(let id):
                        if let v = visibleByID[id] {
                            visitorView(v, size: size, camera: drifted)
                        }
                    case .boxFront(let box):
                        Canvas { ctx, cs in
                            canvas(ctx, cs, drifted, nil).drawPlanterBoxFront(garden, box: box)
                        }
                        .allowsHitTesting(false)
                    }
                }
                if let spot = ghostSpot {
                    Canvas { ctx, cs in
                        canvas(ctx, cs, drifted, nil).drawGhostMarker(spot.point, valid: spot.valid)
                    }
                    .allowsHitTesting(false)
                }
                if let spot = ghostSpot, let flower = ghostFlower {
                    ghostView(flower, at: spot.point, valid: spot.valid, size: size, camera: drifted)
                }
                Canvas { ctx, cs in
                    canvas(ctx, cs, camera, .foreground).drawThemeForeground()
                }
                Canvas { ctx, cs in
                    canvas(ctx, cs, camera, nil).drawWeatherOverlays()
                }
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let travel = hypot(value.translation.width, value.translation.height)
                if travel > Self.tapSlop { dragging = true }
                if dragging { onDrag?(groundPoint(at: value.location, size: size)) }
            }.onEnded { value in
                if !dragging {
                    if let spot = onSpotVisitor, let visitor = visitorSpot(at: value.startLocation, size: size) {
                        spot(visitor)
                    } else if let sit = onSitInChair, chairSpot(at: value.startLocation, size: size) {
                        sit()
                    } else {
                        onTap?(groundPoint(at: value.startLocation, size: size))
                    }
                }
                dragging = false
            })
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): onHover?(groundPoint(at: location, size: size))
                case .ended: onHover?(nil)
                }
            }
        }
    }

    /// The ground point under a point in the scene's own coordinates. Hit testing uses the camera as it is drawn
    /// right now, read at the moment of the event.
    private func groundPoint(at location: CGPoint, size: CGSize) -> GroundPoint? {
        let frame = SceneMotion.Frame(time: Date().timeIntervalSinceReferenceDate, wind: motion.wind, enabled: motion.enabled)
        let hitCamera = SceneMotion.camera(camera, frame: frame)
        return hitCamera.groundPoint(atScreen: (x: Double(location.x / size.width), y: Double(location.y / size.height)),
                                     uprightHeight: soilLift)
    }

    /// Whether a press lands on the reading chair. Uses the camera as it is drawn right now, like `groundPoint(at:)`.
    private func chairSpot(at location: CGPoint, size: CGSize) -> Bool {
        let frame = SceneMotion.Frame(time: Date().timeIntervalSinceReferenceDate, wind: motion.wind, enabled: motion.enabled)
        return Self.chairHit(at: location, size: size, camera: SceneMotion.camera(camera, frame: frame))
    }

    /// The visitor a press lands on, if any. Uses the camera as it is drawn right now, like `groundPoint(at:)`.
    private func visitorSpot(at location: CGPoint, size: CGSize) -> Visitor? {
        let frame = SceneMotion.Frame(time: Date().timeIntervalSinceReferenceDate, wind: motion.wind, enabled: motion.enabled)
        let hitCamera = SceneMotion.camera(camera, frame: frame)
        return Self.visitor(at: location, size: size, visitors: Self.visiblePoses(visitors, now: Date()),
                            garden: garden, camera: hitCamera)
    }

    /// The visitors that are on screen at `now`, each with its pose. A visitor that has not arrived or has left
    /// (fully faded) is left out.
    static func visiblePoses(_ visitors: [Visitor], now: Date) -> [SceneVisitor] {
        visitors.compactMap { v in
            let pose = VisitorMotion.pose(of: v, at: now)
            return pose.opacity > 0.001 ? SceneVisitor(visitor: v, pose: pose) : nil
        }
    }

    /// Where a visitor's feet are on screen and the side of its square. A visitor over a planter box stands on the
    /// lifted soil, as the plants do.
    static func visitorFrame(_ v: SceneVisitor, garden: Garden, size: CGSize,
                             camera cam: Camera) -> (feet: CGPoint, side: CGFloat) {
        let pos = v.pose.position
        let lift = garden.plot.contains(pos) ? SceneCanvas.soilLift(for: garden.plot) : 0
        let q = cam.uprightGroundPoint(x: pos.x, y: pos.y, height: lift)
        let side = size.width * CGFloat(GardenSceneView.visitorSize * cam.scale(atGroundY: pos.y))
        return (CGPoint(x: q.x * size.width, y: q.y * size.height), side)
    }

    /// The visitor nearest a press, among those within reach. The centre of a visitor's body rises with its height, so
    /// a flyer is hit where it is drawn. Reach is the larger of 40 points and 0.06 ground units on screen.
    static func visitor(at location: CGPoint, size: CGSize, visitors: [SceneVisitor], garden: Garden,
                        camera cam: Camera) -> Visitor? {
        var best: (visitor: Visitor, distance: CGFloat)?
        for v in visitors {
            let f = visitorFrame(v, garden: garden, size: size, camera: cam)
            let lift = v.pose.height * VisitorArt.liftPerWorldUnit
            let centre = CGPoint(x: f.feet.x, y: f.feet.y - CGFloat(0.3 + lift) * f.side)
            let pos = v.pose.position
            let step = abs(cam.groundPoint(x: pos.x + 0.06, y: pos.y).x - cam.groundPoint(x: pos.x, y: pos.y).x)
            let reach = max(40, CGFloat(step) * size.width)
            let distance = hypot(location.x - centre.x, location.y - centre.y)
            guard distance <= reach else { continue }
            if best == nil || distance < best!.distance {
                best = (v.visitor, distance)
            }
        }
        return best?.visitor
    }

    /// One visitor on the patch with its pose at the frame's time.
    struct SceneVisitor: Equatable {
        let visitor: Visitor
        let pose: VisitorPose
    }

    /// A visitor drawn at its feet: the square is centred so its ground line sits on the feet.
    private func visitorView(_ v: SceneVisitor, size: CGSize, camera cam: Camera) -> some View {
        let f = Self.visitorFrame(v, garden: garden, size: size, camera: cam)
        return VisitorArt(species: v.visitor.species, size: f.side, pose: v.pose, night: palette.darkness >= 0.4)
            .position(x: f.feet.x, y: f.feet.y - CGFloat(VisitorArt.groundLine - 0.5) * f.side)
    }

    /// The seed preview's spot and whether it is allowed. nil when no seed is selected or no spot is hovered.
    var ghostSpot: (point: GroundPoint, valid: Bool)? {
        guard ghostFlower != nil, let p = hoverPoint else { return nil }
        return (p, ghostValid ?? GardenEngine.canPlant(at: p, in: garden))
    }

    /// A scene canvas for one layer, with the camera given and shifted by the layer's parallax (if any).
    private func canvas(_ ctx: GraphicsContext, _ cs: CGSize, _ cam: Camera, _ layer: SceneMotion.Layer?) -> SceneCanvas {
        var g = ctx
        if let layer {
            let s = motion.layerShift(layer)
            g.translateBy(x: CGFloat(s.x) * cs.width, y: CGFloat(s.y) * cs.height)
        }
        let canvas = SceneCanvas(ctx: g, size: cs, camera: cam, palette: palette, motion: motion, style: style, theme: theme)
        canvas.soilLift = soilLift
        return canvas
    }

    /// How far this bed's soil sits above the lawn (planter boxes lift it; see `SceneCanvas.soilLift(for:)`).
    private var soilLift: Double { SceneCanvas.soilLift(for: garden.plot) }

    /// Canvas point of a ground point, and the plant scale there, for the given (drifted) camera.
    private func place(_ point: GroundPoint, size: CGSize, camera cam: Camera) -> (centre: CGPoint, scale: Double) {
        let q = cam.uprightGroundPoint(x: point.x, y: point.y, height: soilLift)
        return (CGPoint(x: q.x * size.width, y: q.y * size.height), cam.scale(atGroundY: point.y))
    }

    /// One plant, drawn by FlowerArt at its own point, with its moisture-tinted mound.
    private func plantView(_ plant: Plant, size: CGSize, camera cam: Camera) -> some View {
        let at = place(plant.position, size: size, camera: cam)
        let side = size.width * CGFloat(GardenSceneView.plantSize * at.scale)
        let mound = SceneCanvas.moundColours(palette, moisture: plant.moisture)
        return FlowerArt(flower: plant.flower, progress: plant.progress,
                         droop: plant.droop(moisture: plant.moisture), fade: plant.fade,
                         variation: plant.plantSeed, sway: motion.sway(plantSeed: plant.plantSeed),
                         isSeedHead: plant.lifeStage == .seedHead, dead: plant.isDead,
                         soilColor: mound.soil, soilShade: mound.shade)
            .frame(width: side, height: side)
            .position(x: at.centre.x, y: at.centre.y - (GardenSceneView.mound - 0.5) * side)
    }

    /// One weed as a low rosette of jagged leaves lying on the soil. It grows with its age, and its leaves sway
    /// a little with the wind like the plants.
    private func weedView(_ weed: Weed, size: CGSize, camera cam: Camera) -> some View {
        let at = place(weed.position, size: size, camera: cam)
        let side = size.width * CGFloat(GardenSceneView.weedSize * at.scale)
        let growth = Self.weedGrowth(ageHours: weed.ageHours)
        return WeedRosette(seed: UInt64(bitPattern: Int64(weed.id)) &* 0x9E37_79B9 &+ 0xBEEF,
                           growth: growth,
                           sway: motion.sway(plantSeed: UInt64(bitPattern: Int64(weed.id)) &+ 0x77))
            .frame(width: side, height: side)
            .position(x: at.centre.x, y: at.centre.y - (WeedRosette.baseLine - 0.5) * side)
    }

    /// Weeds start at 55 percent of full size and reach full size after about a week.
    static func weedGrowth(ageHours: Int) -> Double {
        0.55 + 0.45 * min(1, Double(ageHours) / 168)
    }

    /// The seed preview: the flower at full bloom, translucent, and tinted red when the spot is not allowed.
    private func ghostView(_ flower: FlowerType, at point: GroundPoint, valid: Bool, size: CGSize,
                           camera cam: Camera) -> some View {
        let at = place(point, size: size, camera: cam)
        let side = size.width * CGFloat(GardenSceneView.plantSize * at.scale)
        let tint = valid ? Color.white : Color(red: 1, green: 0.42, blue: 0.38)
        return FlowerArt(flower: flower, progress: 1, variation: 0)
            .colorMultiply(tint)
            .opacity(valid ? 0.7 : 0.6)
            .frame(width: side, height: side)
            .position(x: at.centre.x, y: at.centre.y - (GardenSceneView.mound - 0.5) * side)
            .allowsHitTesting(false)
    }
}

/// A dandelion-like weed rosette: a ring of low, jagged leaves lying flat on the ground (seen from above at an
/// angle), in a duller yellow-green than the lawn. Older weeds show a few small yellow dots at the centre.
struct WeedRosette: View {
    /// Height of the rosette's centre inside the square, as a fraction of its side. Used to line it up on the ground.
    static let baseLine = 0.7

    let seed: UInt64
    /// 0...1 size, from young to full grown.
    let growth: Double
    /// -1...1 bend of the leaf tips.
    let sway: Double

    /// Leaf and dot colours: a dull yellow-green, and a warmer yellow for the dots.
    static let leaf = Color(hex: 0x8B9A4C)
    static let leafShade = Color(hex: 0x627232)
    static let midrib = Color(hex: 0xB6C56E)
    static let dot = Color(hex: 0xE9C94A)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let centre = CGPoint(x: size.width / 2, y: size.height * CGFloat(Self.baseLine))
            let squash = 0.55                           // the ring lies flat: vertical reach is shorter
            let count = 10
            let reach = s * 0.36 * CGFloat(growth)     // full leaf length at full growth
            for i in 0..<count {
                let k = Double(i)
                let angle = k / Double(count) * 2 * Double.pi + (unitHash(seed, UInt64(i)) - 0.5) * 0.3
                let len = reach * CGFloat(0.7 + 0.5 * unitHash(seed, UInt64(20 + i)))
                let dir = (x: cos(angle), y: sin(angle) * squash)
                let normal = (x: -dir.y, y: dir.x)
                let tip = CGPoint(x: centre.x + CGFloat(dir.x) * len + CGFloat(sway) * len * 0.12 * CGFloat(dir.x),
                                  y: centre.y + CGFloat(dir.y) * len)
                // Jagged outline: alternating teeth on each side of a leaf that narrows to a point.
                let teeth = 4
                var outline: [CGPoint] = []
                let halfWidth = len * 0.2
                func point(_ t: Double, _ side: Double, tooth: Double) -> CGPoint {
                    let along = CGPoint(x: centre.x + CGFloat(dir.x * t) * len, y: centre.y + CGFloat(dir.y * t) * len)
                    let w = CGFloat(halfWidth * sin(Double.pi * min(1, t + 0.15)) * tooth * side)
                    return CGPoint(x: along.x + CGFloat(normal.x) * w, y: along.y + CGFloat(normal.y) * w)
                }
                outline.append(centre)
                for j in 1...teeth {
                    let t = Double(j) / Double(teeth + 1)
                    outline.append(point(t, 1, tooth: j % 2 == 0 ? 0.55 : 1.0))
                }
                outline.append(tip)
                for j in stride(from: teeth, through: 1, by: -1) {
                    let t = Double(j) / Double(teeth + 1)
                    outline.append(point(t, -1, tooth: j % 2 == 0 ? 1.0 : 0.55))
                }
                var path = Path()
                path.move(to: outline[0])
                for q in outline.dropFirst() { path.addLine(to: q) }
                path.closeSubpath()
                // A flat shadow under each leaf, then the leaf, then its midrib.
                ctx.fill(path.applying(CGAffineTransform(translationX: 0, y: 0.03 * s)), with: .color(Self.leafShade.opacity(0.7)))
                ctx.fill(path, with: .color(Self.leaf))
                var rib = Path()
                rib.move(to: centre)
                rib.addLine(to: CGPoint(x: centre.x + (tip.x - centre.x) * 0.8, y: centre.y + (tip.y - centre.y) * 0.8))
                ctx.stroke(rib, with: .color(Self.midrib.opacity(0.8)), style: StrokeStyle(lineWidth: max(0.8, 0.012 * s), lineCap: .round))
            }
            // Older weeds have a few small yellow dots at the centre, as if going to flower.
            if growth > 0.85 {
                let dots = 4
                for d in 0..<dots {
                    let a = Double(d) / Double(dots) * 2 * Double.pi + unitHash(seed, 60 + UInt64(d)) * 0.5
                    let r = s * 0.035
                    let c = CGPoint(x: centre.x + CGFloat(cos(a)) * r * 1.6, y: centre.y + CGFloat(sin(a)) * r * 0.9)
                    let dr = max(1.4, 0.03 * s)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - dr / 2, y: c.y - dr / 2, width: dr, height: dr)),
                             with: .color(Self.dot))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
