import CoreModels
import Foundation
import Observation

/// The server's native "More Like This" list for one movie.
///
/// Emby/Jellyfin own the similarity model, so this does not need external
/// metadata keys or client-side genre scoring. Providers without a native
/// endpoint return an empty list and the row hides.
@MainActor
@Observable
public final class SimilarMoviesViewModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    public private(set) var state: LoadState = .idle
    public private(set) var items: [MediaItem] = []

    private let seed: MediaItem
    private let provider: any MediaProvider
    private let accountID: String?
    private let limit: Int

    public init(
        seed: MediaItem,
        provider: any MediaProvider,
        accountID: String?,
        limit: Int = 20
    ) {
        self.seed = seed
        self.provider = provider
        self.accountID = accountID
        self.limit = max(1, limit)
    }

    public func load() async {
        guard state != .loading else { return }
        guard seed.kind == .movie, !seed.id.isEmpty else {
            state = .loaded
            return
        }

        state = .loading
        do {
            let response = try await provider.similarItems(to: seed.id, limit: limit)
            var seen = Set<String>()
            items = response.compactMap { item in
                guard item.id != seed.id, item.kind == .movie else { return nil }
                let key = "\(item.sourceAccountID ?? ""):\(item.id)"
                guard seen.insert(key).inserted else { return nil }
                guard item.sourceAccountID == nil, let accountID else { return item }
                return item.taggingSource(accountID)
            }
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed((error as? AppError) ?? .serverUnreachable)
        }
    }
}
