import Foundation

public struct WeatherSample: Codable, Equatable, Sendable {
    public var date: Date          // start of the hour
    public var temperatureC: Double
    public var precipitationMM: Double
    public var windKmh: Double
    public var cloudCover: Double  // 0...100
    public var isDay: Bool

    public init(date: Date, temperatureC: Double, precipitationMM: Double = 0,
                windKmh: Double = 5, cloudCover: Double = 0, isDay: Bool = true) {
        self.date = date; self.temperatureC = temperatureC
        self.precipitationMM = precipitationMM; self.windKmh = windKmh
        self.cloudCover = cloudCover; self.isDay = isDay
    }
}
