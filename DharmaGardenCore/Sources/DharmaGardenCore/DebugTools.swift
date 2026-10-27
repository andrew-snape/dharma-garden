import Foundation

/// Developer tools for the garden. Catch-up goes through `GardenEngine.advance` one day at a time,
/// the same code path as real play.
public enum DebugTools {
    /// Moisture the whole plot is raised to at the start of a simulated day when auto-water is on.
    public static let autoWaterLevel = 70.0

    public struct Summary: Equatable, Sendable {
        public var planted: Int
        public var blooming: Int
        public var fading: Int
        public var weeds: Int
    }

    /// Fast-forwards the garden by whole days from its `lastSimulatedAt`.
    /// - Parameters:
    ///   - garden: the garden to fast-forward.
    ///   - days: the number of whole days to simulate. Values of zero or less return `garden` unchanged.
    ///   - autoWater: at the start of each simulated day, the plot is raised to at least `autoWaterLevel`
    ///     and every weed is cleared.
    ///   - weather: per-hour samples. When nil, mild neutral weather is used (see `DebugTools`).
    ///   - calendar: the calendar used to generate the neutral weather when `weather` is nil.
    public static func advance(garden: Garden, days: Int, autoWater: Bool = false,
                               weather: [WeatherSample]? = nil, calendar: Calendar = .current) -> Garden {
        guard days > 0 else { return garden }
        let start = garden.lastSimulatedAt
        let samples = weather ?? DebugTools.neutralWeather(from: start, hours: days * 24, calendar: calendar)
        var g = garden
        for day in 0..<days {
            if autoWater { waterPlot(&g) }
            let dayEnd = start.addingTimeInterval(Double(day + 1) * 86_400)
            g = GardenEngine.advance(g, weather: samples, to: dayEnd)
        }
        return g
    }

    /// Plants `count` flowers at deterministic spots across the plot, rotating through `flowers`.
    /// Spends no carrots or seeds, and stops early if the plot is full.
    public static func fillWithPlants(garden: Garden, count: Int, flowers: [FlowerType] = FlowerType.allCases) -> Garden {
        guard count > 0, !flowers.isEmpty else { return garden }
        var g = garden
        var placed = 0, attempt = 0
        while placed < count && attempt < count * 40 {
            let p = g.plot.point(seed: DeterministicHash.seed(attempt, 4242), inset: Tuning.sowInset)
            if GardenEngine.plant(flowers[placed % flowers.count], at: p, in: &g) { placed += 1 }
            attempt += 1
        }
        return g
    }

    /// A fresh garden, as on first launch.
    public static func reset(now: Date) -> Garden {
        Garden(now: now)
    }

    public static func summary(of garden: Garden) -> Summary {
        var s = Summary(planted: 0, blooming: 0, fading: 0, weeds: garden.weeds.count)
        for plant in garden.plants where !plant.isDead {
            s.planted += 1
            switch plant.lifeStage {
            case .blooming: s.blooming += 1
            case .fading: s.fading += 1
            default: break
            }
        }
        return s
    }

    /// Raises every soil cell inside the plot to the auto-water level, moistens plants, and clears weeds.
    static func waterPlot(_ g: inout Garden) {
        let plot = g.plot
        for i in g.soil.values.indices {
            let centre = SoilField.cellCentre(column: i % SoilField.columns, row: i / SoilField.columns)
            if plot.contains(centre) { g.soil.values[i] = max(g.soil.values[i], autoWaterLevel) }
        }
        g.weeds = []
        GardenEngine.refreshMoisture(&g)
    }

    /// Hourly mild weather for `hours` hours after the hour containing `start` (18 C, no rain, 5 km/h wind,
    /// daytime 07:00-19:00 local time).
    static func neutralWeather(from start: Date, hours: Int, calendar: Calendar) -> [WeatherSample] {
        let first = GardenEngine.hourStart(start)
        return (1...max(1, hours)).map { h in
            let date = first.addingTimeInterval(Double(h) * 3600)
            let hour = calendar.component(.hour, from: date)
            return WeatherSample(date: date, temperatureC: 18, precipitationMM: 0, windKmh: 5,
                                 cloudCover: 0, isDay: (7..<19).contains(hour))
        }
    }
}
