import CoreModels
import CoreNetworking
import Foundation
import Observation

/// Pages one studio's or tag's movies in the current library.
///
/// The first page is published as soon as it arrives; later pages load when the
/// grid reaches its end. A large studio therefore never blocks first paint on a
/// full-library scan.
@MainActor
@Observable
public final class MovieCatalogViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    public let term: MovieCatalogTerm
    public private(set) var state: LoadState = .idle
    public private(set) var items: [MediaItem] = []
    public private(set) var scannedCount = 0
    public private(set) var totalCount = 0
    public private(set) var hasMore = false
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: AppError?

    private let provider: any MediaProvider
    private let libraryID: String?
    private let pageLimit: Int
    private var nextStartIndex = 0
    private var pagesLoaded = 0
    private var seen = Set<String>()
    /// `nil` means the first page has not chosen a query path yet.
    private var usedNativeFilter: Bool?

    public init(
        term: MovieCatalogTerm,
        provider: any MediaProvider,
        libraryID: String?,
        pageLimit: Int = 60
    ) {
        self.term = term
        self.provider = provider
        self.libraryID = libraryID
        self.pageLimit = max(1, pageLimit)
    }

    public func loadFirstPage() async {
        guard state != .loading, !isLoadingMore else { return }

        state = .loading
        items = []
        scannedCount = 0
        totalCount = 0
        hasMore = false
        loadMoreError = nil
        nextStartIndex = 0
        pagesLoaded = 0
        seen = []
        usedNativeFilter = nil
        PlozzLog.networking.info(
            "Movie catalog start kind=\(termKind) library=\(libraryID ?? "all") limit=\(pageLimit)"
        )

        do {
            guard let page = try await fetchNextPage() else {
                state = .failed(.notFound)
                return
            }
            apply(page)
            state = .loaded
            logFirstPage()
        } catch is CancellationError {
            state = .idle
        } catch {
            PlozzLog.app.error(
                "Movie catalog failed library=\(libraryID ?? "all") "
                    + "error=\(String(describing: error))"
            )
            state = .failed((error as? AppError) ?? .serverUnreachable)
        }
    }

    public func loadMoreIfNeeded(currentItem: MediaItem) async {
        guard state == .loaded, hasMore, !isLoadingMore, loadMoreError == nil else { return }
        guard items.last?.stablePresentationID == currentItem.stablePresentationID else { return }
        await loadMore()
    }

    public func loadMore() async {
        guard state == .loaded, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        do {
            guard let page = try await fetchNextPage() else {
                hasMore = false
                return
            }
            apply(page)
            if !hasMore { logFinished() }
        } catch is CancellationError {
            // Keep the already-published pages; the next appearance can retry.
        } catch {
            loadMoreError = (error as? AppError) ?? .serverUnreachable
        }
    }

    private func fetchNextPage() async throws -> MediaPage? {
        let request = PageRequest(
            startIndex: nextStartIndex,
            limit: pageLimit,
            sort: SortDescriptor(field: .releaseDate, direction: .descending)
        )

        if usedNativeFilter == nil {
            if let page = try await provider.items(
                in: libraryID, kind: .movie, matching: term, page: request
            ) {
                usedNativeFilter = true
                return page
            }
            usedNativeFilter = false
        }

        if usedNativeFilter == true {
            return try await provider.items(
                in: libraryID, kind: .movie, matching: term, page: request
            )
        }

        guard let libraryID, !libraryID.isEmpty else { throw AppError.notFound }
        return try await provider.items(in: libraryID, kind: .movie, page: request)
    }

    private func apply(_ page: MediaPage) {
        pagesLoaded += 1
        nextStartIndex = page.endIndex
        for item in page.items where item.kind == .movie && term.matches(item) {
            let key = "\(item.sourceAccountID ?? ""):\(item.id)"
            guard seen.insert(key).inserted else { continue }
            items.append(item)
        }
        scannedCount = page.endIndex
        // Native pages already report the filtered total. A local scan reports
        // the whole library, so its "total" is just what we have matched so far.
        totalCount = usedNativeFilter == true
            ? max(page.totalCount, items.count)
            : items.count
        hasMore = page.hasMore && !page.items.isEmpty
    }

    private var termKind: String {
        term.kind == .studio ? "studio" : "tag"
    }

    private func logFirstPage() {
        PlozzLog.networking.info(
            "Movie catalog first-page kind=\(termKind) library=\(libraryID ?? "all") "
                + "mode=\(usedNativeFilter == true ? "native" : "scan") "
                + "items=\(items.count) total=\(totalCount) hasMore=\(hasMore)"
        )
    }

    private func logFinished() {
        PlozzLog.networking.info(
            "Movie catalog done kind=\(termKind) library=\(libraryID ?? "all") "
                + "mode=\(usedNativeFilter == true ? "native" : "scan") "
                + "pages=\(pagesLoaded) items=\(items.count) total=\(totalCount)"
        )
    }
}
