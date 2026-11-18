import Foundation

/// A Project Gutenberg book offered on the reading chair.
public struct ReadingBook: Equatable, Sendable, Identifiable {
    /// The Project Gutenberg ebook number.
    public let id: Int
    public let title: String
    public let author: String
    /// One line on why it suits an afternoon in the garden.
    public let blurb: String

    /// The plain-text file for this book on gutenberg.org.
    public var textURL: URL { URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).txt")! }
    /// The book's page on gutenberg.org.
    public var pageURL: URL { URL(string: "https://www.gutenberg.org/ebooks/\(id)")! }
}

public enum ReadingLibrary {
    /// The shelf, in the order shown. Every title is public domain on Project Gutenberg.
    public static let books: [ReadingBook] = [
        ReadingBook(id: 113, title: "The Secret Garden", author: "Frances Hodgson Burnett",
                    blurb: "A lonely girl finds a locked garden and brings it back to life."),
        ReadingBook(id: 289, title: "The Wind in the Willows", author: "Kenneth Grahame",
                    blurb: "Riverbank adventures with Mole, Rat, Badger and Toad."),
        ReadingBook(id: 11, title: "Alice's Adventures in Wonderland", author: "Lewis Carroll",
                    blurb: "Down the rabbit hole, past a very peculiar tea party."),
        ReadingBook(id: 45, title: "Anne of Green Gables", author: "L. M. Montgomery",
                    blurb: "A talkative orphan wins over a farm on Prince Edward Island."),
        ReadingBook(id: 14838, title: "The Tale of Peter Rabbit", author: "Beatrix Potter",
                    blurb: "A short one: a rabbit, a vegetable patch and Mr. McGregor."),
        ReadingBook(id: 1342, title: "Pride and Prejudice", author: "Jane Austen",
                    blurb: "Manners, matchmaking and Mr. Darcy."),
        ReadingBook(id: 158, title: "Emma", author: "Jane Austen",
                    blurb: "A well-meaning matchmaker gets it all wrong."),
        ReadingBook(id: 1661, title: "The Adventures of Sherlock Holmes", author: "Arthur Conan Doyle",
                    blurb: "Twelve short cases, each finished in one sitting."),
        ReadingBook(id: 55, title: "The Wonderful Wizard of Oz", author: "L. Frank Baum",
                    blurb: "A Kansas farm girl, a tornado and the yellow brick road."),
        ReadingBook(id: 16, title: "Peter Pan", author: "J. M. Barrie",
                    blurb: "The boy who would not grow up, and Neverland."),
        ReadingBook(id: 236, title: "The Jungle Book", author: "Rudyard Kipling",
                    blurb: "Mowgli and the animals of the Indian jungle."),
        ReadingBook(id: 271, title: "Black Beauty", author: "Anna Sewell",
                    blurb: "A horse tells his own story."),
        ReadingBook(id: 514, title: "Little Women", author: "Louisa May Alcott",
                    blurb: "Four sisters grow up in New England."),
        ReadingBook(id: 1260, title: "Jane Eyre", author: "Charlotte Bront\u{EB}",
                    blurb: "A governess, a grand house and a secret."),
        ReadingBook(id: 2591, title: "Grimms' Fairy Tales", author: "Brothers Grimm",
                    blurb: "Short tales you can dip into anywhere."),
        ReadingBook(id: 205, title: "Walden", author: "Henry David Thoreau",
                    blurb: "Two years of quiet living by a pond, and a bean field."),
        ReadingBook(id: 2680, title: "Meditations", author: "Marcus Aurelius",
                    blurb: "An emperor's private notes to himself on living well."),
        ReadingBook(id: 2017, title: "Dhammapada", author: "F. Max M\u{FC}ller",
                    blurb: "Short verses from the Buddha on the mind, kindness and letting go."),
        ReadingBook(id: 45109, title: "The Enchiridion", author: "Epictetus",
                    blurb: "A small Stoic handbook on what is and isn't within our control."),
        ReadingBook(id: 2388, title: "The Song Celestial", author: "Edwin Arnold",
                    blurb: "A warrior's crisis on the battlefield, and the god who guides him."),
    ]

    /// The reading text of a Project Gutenberg plain-text file as paragraphs: the licence header and footer are cut
    /// off at the START and END markers, line breaks inside a paragraph become spaces, and blank lines separate
    /// paragraphs. A file without markers is used whole.
    public static func paragraphs(from raw: String) -> [String] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = text.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.hasPrefix("*** START OF") }) {
            lines.removeSubrange(...start)
        }
        if let end = lines.firstIndex(where: { $0.hasPrefix("*** END OF") }) {
            lines.removeSubrange(end...)
        }
        var result: [String] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { result.append(current.joined(separator: " ")) }
            current = []
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush() } else { current.append(trimmed) }
        }
        flush()
        return result
    }
}
