import Foundation

/// A place the garden can take its weather from. The coordinates feed Open-Meteo; the names are for display.
public struct Town: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var admin1: String?
    public var country: String?

    public init(name: String, latitude: Double, longitude: Double, admin1: String? = nil, country: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.admin1 = admin1
        self.country = country
    }

    /// "Mount Duneed, Victoria, Australia". Missing parts are left out.
    public var displayName: String {
        [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The town used until the user picks another one.
    public static let mountDuneed = Town(name: "Mount Duneed", latitude: -38.2167, longitude: 144.2833,
                                         admin1: "Victoria", country: "Australia")
}

/// Town search through Open-Meteo's geocoding API (no key needed). Building the URL and parsing the
/// response are pure, so tests use a JSON fixture and never touch the network.
public enum Geocoding {
    public static let endpoint = "https://geocoding-api.open-meteo.com/v1/search"

    public enum GeocodingError: Error, Equatable { case badResponse }

    /// The search URL for a town name, or nil when the query is blank.
    public static func searchURL(query: String, count: Int = 5) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var c = URLComponents(string: endpoint)!
        c.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url
    }

    /// Towns from a search response. A response with no matches has no `results` key and gives [].
    public static func parse(_ data: Data) throws -> [Town] {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.results ?? []).map { hit in
            Town(name: hit.name, latitude: hit.latitude, longitude: hit.longitude,
                 admin1: hit.admin1, country: hit.country)
        }
    }

    /// Searches for towns by name. A blank query returns no towns without a request.
    public static func search(_ query: String, count: Int = 5, session: URLSession = .shared) async throws -> [Town] {
        guard let url = searchURL(query: query, count: count) else { return [] }
        let req = URLRequest(url: url, timeoutInterval: 8)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw GeocodingError.badResponse }
        return try parse(data)
    }

    private struct Response: Decodable {
        let results: [Hit]?
    }

    private struct Hit: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country: String?
    }
}
