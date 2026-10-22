import Foundation

public enum OpenMeteoError: Error { case badResponse, missingData }

public struct OpenMeteoClient: Sendable {
    public var session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public static func url(latitude: Double, longitude: Double, pastDays: Int = 7) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,precipitation,weather_code,cloud_cover,wind_speed_10m,is_day"),
            .init(name: "hourly", value: "temperature_2m,precipitation,wind_speed_10m,cloud_cover,is_day"),
            .init(name: "daily", value: "sunrise,sunset"),
            .init(name: "past_days", value: String(pastDays)),
            .init(name: "forecast_days", value: "2"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        return c.url!
    }

    public func fetch(latitude: Double, longitude: Double, now: Date = Date()) async throws -> WeatherReport {
        var req = URLRequest(url: Self.url(latitude: latitude, longitude: longitude), timeoutInterval: 8)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw OpenMeteoError.badResponse }
        return try Self.parse(data, latitude: latitude, longitude: longitude, fetchedAt: now)
    }

    // MARK: Parsing

    struct Raw: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double, apparent_temperature: Double, precipitation: Double
            let weather_code: Int, cloud_cover: Double, wind_speed_10m: Double, is_day: Int
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double?], precipitation: [Double?]
            let wind_speed_10m: [Double?], cloud_cover: [Double?], is_day: [Int?]
        }
        struct Daily: Decodable { let time: [Double]; let sunrise: [Double?]; let sunset: [Double?] }
        let current: Current, hourly: Hourly, daily: Daily
    }

    public static func parse(_ data: Data, latitude: Double, longitude: Double, fetchedAt: Date) throws -> WeatherReport {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let h = raw.hourly
        let samples: [WeatherSample] = h.time.indices.compactMap { i in
            guard let t = h.temperature_2m[i] else { return nil }
            return WeatherSample(date: Date(timeIntervalSince1970: h.time[i]), temperatureC: t,
                                 precipitationMM: h.precipitation[i] ?? 0, windKmh: h.wind_speed_10m[i] ?? 0,
                                 cloudCover: h.cloud_cover[i] ?? 0, isDay: (h.is_day[i] ?? 1) == 1)
        }
        // Today's entry = the latest sunrise that has started (or starts within the 45 minute
        // dawn window). Picking the "closest" sunrise wrongly chose tomorrow's in the evening.
        let pairs = raw.daily.sunrise.indices.compactMap { i -> (Date, Date)? in
            guard let r = raw.daily.sunrise[i], let s = raw.daily.sunset[i] else { return nil }
            return (Date(timeIntervalSince1970: r), Date(timeIntervalSince1970: s))
        }.sorted { $0.0 < $1.0 }
        let dawnWindow: TimeInterval = 45 * 60
        guard let today = pairs.last(where: { $0.0 <= fetchedAt.addingTimeInterval(dawnWindow) }) ?? pairs.first else {
            throw OpenMeteoError.missingData
        }
        let c = raw.current
        return WeatherReport(
            current: CurrentConditions(temperatureC: c.temperature_2m, apparentTemperatureC: c.apparent_temperature,
                                       precipitationMM: c.precipitation, windKmh: c.wind_speed_10m,
                                       cloudCover: c.cloud_cover, isDay: c.is_day == 1,
                                       condition: WeatherCondition(wmoCode: c.weather_code)),
            hourly: samples, sunrise: today.0, sunset: today.1,
            fetchedAt: fetchedAt, latitude: latitude, longitude: longitude)
    }
}
