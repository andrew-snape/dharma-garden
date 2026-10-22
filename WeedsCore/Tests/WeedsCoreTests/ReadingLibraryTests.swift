import XCTest
@testable import WeedsCore

final class ReadingLibraryTests: XCTestCase {
    func testShelfHasUniqueIDsAndURLs() {
        let books = ReadingLibrary.books
        XCTAssertEqual(Set(books.map(\.id)).count, books.count)
        XCTAssertEqual(books.first(where: { $0.id == 113 })?.textURL.absoluteString,
                       "https://www.gutenberg.org/cache/epub/113/pg113.txt")
        XCTAssertTrue(books.allSatisfy { !$0.title.isEmpty && !$0.author.isEmpty && !$0.blurb.isEmpty })
    }

    func testParagraphsCutLicenceAndJoinWrappedLines() {
        let raw = """
        The Project Gutenberg eBook of Test\r
        \r
        *** START OF THE PROJECT GUTENBERG EBOOK TEST ***\r
        \r
        CHAPTER I\r
        \r
        It was a bright cold day\r
          in April, and the clocks\r
        were striking thirteen.\r
        \r
        \r
        Second paragraph.\r
        *** END OF THE PROJECT GUTENBERG EBOOK TEST ***\r
        Licence text here.
        """
        XCTAssertEqual(ReadingLibrary.paragraphs(from: raw),
                       ["CHAPTER I", "It was a bright cold day in April, and the clocks were striking thirteen.",
                        "Second paragraph."])
    }

    func testTextWithoutMarkersIsUsedWhole() {
        XCTAssertEqual(ReadingLibrary.paragraphs(from: "One\nline\n\nTwo"), ["One line", "Two"])
    }
}
