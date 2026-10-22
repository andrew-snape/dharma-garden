import Foundation

public enum Season: String, Codable, Sendable { case summer, autumn, winter, spring }

public enum SeasonProvider {
    /// Meteorological seasons; flipped for the southern hemisphere (latitude < 0).
    public static func season(on date: Date, latitude: Double, calendar: Calendar = .init(identifier: .gregorian)) -> Season {
        let month = calendar.component(.month, from: date)
        let north: Season = switch month {
        case 12, 1, 2: .winter
        case 3, 4, 5: .spring
        case 6, 7, 8: .summer
        default: .autumn
        }
        guard latitude < 0 else { return north }
        return switch north {
        case .winter: .summer
        case .summer: .winter
        case .spring: .autumn
        case .autumn: .spring
        }
    }
}
