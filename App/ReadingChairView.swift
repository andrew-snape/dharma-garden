import SwiftUI
import DharmaGardenCore
import DharmaGardenArt

/// Downloads a Project Gutenberg book once and keeps the text in Application Support, so a book opens instantly (and
/// offline) after its first read.
@MainActor
final class BookShelf: ObservableObject {
    enum Failure: Error { case badResponse, notText }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Books", isDirectory: true)
    }

    private func cacheURL(_ book: ReadingBook) -> URL {
        Self.cacheDirectory.appendingPathComponent("pg\(book.id).txt")
    }

    func isDownloaded(_ book: ReadingBook) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(book).path)
    }

    /// The book's paragraphs, from the cache when it is there, otherwise downloaded and then cached.
    func paragraphs(of book: ReadingBook) async throws -> [String] {
        let url = cacheURL(book)
        if let cached = try? String(contentsOf: url, encoding: .utf8) {
            return await Self.parse(cached)
        }
        var request = URLRequest(url: book.textURL)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.badResponse }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.notText }
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        return await Self.parse(text)
    }

    /// Splitting a whole novel into paragraphs is too much work for the main thread.
    private nonisolated static func parse(_ text: String) async -> [String] {
        await Task.detached(priority: .userInitiated) { ReadingLibrary.paragraphs(from: text) }.value
    }
}

/// Where the reader left off in each book: the index of the paragraph at the top of the page.
enum ReadingProgress {
    private static func key(_ book: ReadingBook) -> String { "reading.position.\(book.id)" }

    static func position(of book: ReadingBook) -> Int? {
        UserDefaults.standard.object(forKey: key(book)) as? Int
    }

    static func save(_ index: Int, for book: ReadingBook) {
        UserDefaults.standard.set(index, forKey: key(book))
    }
}

/// The sheet that opens when the player sits in the reading chair: a shelf of Project Gutenberg books, and a plain
/// reader for the one chosen. Drawn in the garden's panel style, like the shop and the book.
struct ReadingChairView: View {
    let palette: ScenePalette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shelf = BookShelf()
    @State private var open: ReadingBook?

    var body: some View {
        GardenSheetFrame(title: open?.title ?? "Reading chair", palette: palette, onDone: { dismiss() }) { style in
            if let book = open {
                BookReader(book: book, shelf: shelf, style: style) { open = nil }
            } else {
                shelfList(style)
            }
        }
        .frame(minWidth: 540, minHeight: 680)
    }

    private func shelfList(_ style: ScenePanelStyle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pull up a chair").font(.headline)
                    Text("Free classics from Project Gutenberg. Pick one and read in the sun; the garden keeps your place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel(style)
                ForEach(ReadingLibrary.books) { book in
                    Button { open = book } label: { row(book, style) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ book: ReadingBook, _ style: ScenePanelStyle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundStyle(Color.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title).font(.headline)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                Text(book.blurb).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if ReadingProgress.position(of: book) != nil {
                Text("Continue").font(.caption.bold()).foregroundStyle(Color.orange)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .panel(style)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title), by \(book.author)")
    }
}

/// One book, as paragraphs in a scrolling serif page. Loads on appear, jumps to the saved place and keeps it up to date.
private struct BookReader: View {
    let book: ReadingBook
    @ObservedObject var shelf: BookShelf
    let style: ScenePanelStyle
    let onBack: () -> Void

    @AppStorage("reading.fontSize") private var fontSize = 17.0
    @State private var paragraphs: [String] = []
    @State private var failed = false
    @State private var loading = true
    /// The paragraph last scrolled to. Saved as the reading position.
    @State private var current = 0

    var body: some View {
        VStack(spacing: 10) {
            controls
            page.panel(style)
        }
        .task(id: book.id) { await load() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { onBack() } label: { Label("Books", systemImage: "chevron.left") }
            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button { fontSize = max(13, fontSize - 1) } label: { Image(systemName: "textformat.size.smaller") }
                .help("Smaller text")
            Button { fontSize = min(30, fontSize + 1) } label: { Image(systemName: "textformat.size.larger") }
                .help("Larger text")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .panel(style)
    }

    @ViewBuilder private var page: some View {
        if loading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Fetching \(book.title)\u{2026}").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if failed {
            VStack(spacing: 10) {
                Text("Couldn't fetch this book.").font(.headline)
                Text("Check your internet connection and try again.").foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: fontSize * 0.7) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, text in
                            Text(text)
                                .font(.system(size: fontSize, design: .serif))
                                .lineSpacing(fontSize * 0.3)
                                .textSelection(.enabled)
                                .id(index)
                                .onAppear {
                                    current = index
                                    ReadingProgress.save(index, for: book)
                                }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    if let saved = ReadingProgress.position(of: book), saved < paragraphs.count {
                        proxy.scrollTo(saved, anchor: .top)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            paragraphs = try await shelf.paragraphs(of: book)
            failed = paragraphs.isEmpty
        } catch {
            failed = true
        }
        loading = false
    }
}
