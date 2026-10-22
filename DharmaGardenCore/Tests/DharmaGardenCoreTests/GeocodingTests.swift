import XCTest
@testable import DharmaGardenCore

final class GeocodingTests: XCTestCase {
    let fixture = """
    {"results":[
      {"id":2161457,"name":"Mount Duneed","latitude":-38.21667,"longitude":144.28333,"elevation":21.0,
       "feature_code":"PPL","country_code":"AU","admin1":"Victoria","timezone":"Australia/Melbourne",
       "country":"Australia"},
      {"id":6255148,"name":"Mount Duneed","latitude":45.0,"longitude":-75.5,"country_code":"CA","country":"Canada"},
      {"id":1,"name":"Duneed","latitude":-38.2,"longitude":144.3,"admin1":"Victoria","country":"Australia"}
    ],"generationtime_ms":0.8}
    """.data(using: .utf8)!

    func testParsesNameLocationAdminAndCountry() throws {
        let towns = try Geocoding.parse(fixture)
        XCTAssertEqual(towns.count, 3)
        XCTAssertEqual(towns[0].name, "Mount Duneed")
        XCTAssertEqual(towns[0].admin1, "Victoria")
        XCTAssertEqual(towns[0].country, "Australia")
        XCTAssertEqual(towns[0].latitude, -38.21667, accuracy: 1e-9)
        XCTAssertEqual(towns[0].longitude, 144.28333, accuracy: 1e-9)
    }

    func testMissingAdminIsNil() throws {
        let towns = try Geocoding.parse(fixture)
        XCTAssertNil(towns[1].admin1)
        XCTAssertEqual(towns[1].country, "Canada")
        XCTAssertEqual(towns[1].displayName, "Mount Duneed, Canada")
    }

    func testDisplayNameJoinsTheParts() throws {
        let towns = try Geocoding.parse(fixture)
        XCTAssertEqual(towns[0].displayName, "Mount Duneed, Victoria, Australia")
        XCTAssertEqual(Town.melbourne.displayName, "Melbourne, Victoria, Australia")
    }

    func testNoMatchesGivesNoTowns() throws {
        let empty = #"{"generationtime_ms":0.4}"#.data(using: .utf8)!
        XCTAssertEqual(try Geocoding.parse(empty), [])
    }

    func testSearchURLCarriesTheQueryAndOptions() throws {
        let url = try XCTUnwrap(Geocoding.searchURL(query: "Mount Duneed"))
        let s = url.absoluteString
        XCTAssertTrue(s.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?"), s)
        XCTAssertTrue(s.contains("name=Mount%20Duneed"), s)
        XCTAssertTrue(s.contains("count=5"), s)
        XCTAssertTrue(s.contains("language=en"), s)
        XCTAssertTrue(s.contains("format=json"), s)
    }

    func testSearchURLTrimsAndEncodesSpecialCharacters() throws {
        let url = try XCTUnwrap(Geocoding.searchURL(query: "  Bass & Coast  "))
        XCTAssertTrue(url.absoluteString.contains("name=Bass%20%26%20Coast"), url.absoluteString)
    }

    func testBlankQueryHasNoURL() {
        XCTAssertNil(Geocoding.searchURL(query: ""))
        XCTAssertNil(Geocoding.searchURL(query: "   "))
    }

    func testMalformedResponseThrows() {
        XCTAssertThrowsError(try Geocoding.parse(Data("not json".utf8)))
    }
}
