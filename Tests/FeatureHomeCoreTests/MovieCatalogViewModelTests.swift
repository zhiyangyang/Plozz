import CoreModels
import XCTest
@testable import FeatureHomeCore

@MainActor
final class MovieCatalogViewModelTests: XCTestCase {
    func testStudioCatalogPublishesFirstPageThenLoadsMore() async {
        let provider = CatalogStub(movies: [
            movie("a1", "Alpha One", year: 2001, studio: "Alpha"),
            movie("b1", "Beta One", year: 2002, studio: "Beta"),
            movie("a2", "Alpha Two", year: 2010, studio: "Alpha"),
            movie("a3", "Alpha Three", year: 2020, studio: "Alpha"),
            movie("b2", "Beta Two", year: 2011, studio: "Beta"),
        ])

        let model = MovieCatalogViewModel(
            term: .studio("Alpha"), provider: provider, libraryID: "library", pageLimit: 2
        )
        await model.loadFirstPage()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.items.map(\.id), ["a1"])
        XCTAssertTrue(model.hasMore)

        while model.hasMore {
            await model.loadMore()
        }

        XCTAssertEqual(model.items.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(model.scannedCount, 5)
        XCTAssertEqual(model.totalCount, 3)
    }

    func testEmbyNativeTermFilterPagesWithoutScanningTheLibrary() async {
        let provider = CatalogStub(movies: [
            movie("alpha", "Alpha", year: 2020, studio: "Alpha"),
            movie("beta", "Beta", year: 2021, studio: "Beta"),
            movie("gamma", "Gamma", year: 2022, studio: "Alpha"),
        ])
        provider.nativeMatching = true

        let model = MovieCatalogViewModel(
            term: .studio("Alpha"), provider: provider, libraryID: "library", pageLimit: 1
        )
        await model.loadFirstPage()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.items.map(\.id), ["alpha"])
        XCTAssertTrue(model.hasMore)

        await model.loadMore()

        XCTAssertEqual(model.items.map(\.id), ["alpha", "gamma"])
        XCTAssertEqual(model.totalCount, 2)
    }

    func testTagCatalogMatchesTrimmedCaseInsensitiveTag() async {
        let provider = CatalogStub(movies: [
            movie("one", "One", year: 2020, tags: ["Sci-Fi", "Drama"]),
            movie("two", "Two", year: 2021, tags: ["Drama"]),
        ])

        let model = MovieCatalogViewModel(
            term: .tag("  sci-fi "), provider: provider, libraryID: "library", pageLimit: 10
        )
        await model.loadFirstPage()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.items.map(\.id), ["one"])
    }

    func testCatalogReportsFailure() async {
        let provider = CatalogStub(movies: [], failure: .unauthorized)
        let model = MovieCatalogViewModel(
            term: .tag("Drama"), provider: provider, libraryID: "library"
        )
        await model.loadFirstPage()

        XCTAssertEqual(model.state, .failed(.unauthorized))
        XCTAssertTrue(model.items.isEmpty)
    }

    func testSimilarMoviesDropsSeedAndNonMovies() async {
        let seed = movie("seed", "Seed", year: 2020)
        let provider = CatalogStub(
            movies: [],
            similar: [
                seed,
                movie("similar", "Similar", year: 2019),
                MediaItem(id: "series", title: "Series", kind: .series),
            ]
        )
        let model = SimilarMoviesViewModel(seed: seed, provider: provider, accountID: nil)
        await model.load()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.items.map(\.id), ["similar"])
    }

    func testSimilarMoviesEmptyResponseIsLoaded() async {
        let seed = movie("seed", "Seed", year: 2020)
        let model = SimilarMoviesViewModel(
            seed: seed, provider: CatalogStub(movies: []), accountID: nil
        )
        await model.load()

        XCTAssertEqual(model.state, .loaded)
        XCTAssertTrue(model.items.isEmpty)
    }
}

private func movie(
    _ id: String,
    _ title: String,
    year: Int,
    studio: String? = nil,
    tags: [String] = []
) -> MediaItem {
    MediaItem(
        id: id,
        title: title,
        kind: .movie,
        productionYear: year,
        studios: studio.map { [$0] } ?? [],
        tags: tags
    )
}

private final class CatalogStub: MediaProvider, @unchecked Sendable {
    let kind: ProviderKind = .emby
    let session = UserSession(
        server: MediaServer(
            id: "server", name: "Library", baseURL: URL(string: "http://library.invalid")!,
            provider: .emby
        ),
        userID: "user", userName: "User", deviceID: "device", accessToken: "token"
    )

    var nativeMatching = false
    private let movies: [MediaItem]
    private let similar: [MediaItem]
    private let failure: AppError?

    init(movies: [MediaItem], similar: [MediaItem] = [], failure: AppError? = nil) {
        self.movies = movies
        self.similar = similar
        self.failure = failure
    }

    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }

    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        if let failure { throw failure }
        let start = min(max(0, page.startIndex), movies.count)
        let end = min(start + max(0, page.limit), movies.count)
        return MediaPage(
            items: Array(movies[start..<end]), startIndex: start, totalCount: movies.count
        )
    }

    func items(
        in containerID: String?,
        kind: MediaItemKind,
        matching term: MovieCatalogTerm,
        page: PageRequest
    ) async throws -> MediaPage? {
        guard nativeMatching else { return nil }
        if let failure { throw failure }
        let filtered = movies.filter(term.matches)
        let start = min(max(0, page.startIndex), filtered.count)
        let end = min(start + max(0, page.limit), filtered.count)
        return MediaPage(
            items: Array(filtered[start..<end]), startIndex: start, totalCount: filtered.count
        )
    }

    func similarItems(to itemID: String, limit: Int) async throws -> [MediaItem] {
        if let failure { throw failure }
        return Array(similar.prefix(max(0, limit)))
    }

    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
