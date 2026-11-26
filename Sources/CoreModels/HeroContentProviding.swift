import Foundation

/// The narrow library identity a Random hero fetch needs. Home already loaded this
/// metadata while building its rows, so carrying it into the provider avoids a
/// second `libraries()` network request solely to rediscover each container's kind.
public struct HeroRandomLibrary: Hashable, Sendable {
    public let accountID: String
    public let libraryID: String
    public let kind: MediaItemKind

    public init(accountID: String, libraryID: String, kind: MediaItemKind) {
        self.accountID = accountID
        self.libraryID = libraryID
        self.kind = kind
    }
}

/// Injected source of **random** hero picks drawn from already-resolved libraries.
/// Implemented over `MediaProvider.items(in:kind:page:)` with `SortField.random`
/// so it works for both Jellyfin and Plex.
public typealias RandomLibraryContentProviding = @Sendable (_ libraries: [HeroRandomLibrary], _ limit: Int) async -> [MediaItem]

public typealias HeroCollectionContentProviding = @Sendable (
    _ collection: HeroCollectionSelection, _ limit: Int
) async throws -> MediaPage

public enum HeroCollectionProvider {
    public static let none: HeroCollectionContentProviding = { _, _ in throw AppError.notFound }
}

public enum HeroRandomProvider {
    /// The no-op random provider (e.g. previews/tests with no accounts).
    public static let none: RandomLibraryContentProviding = { _, _ in [] }
}
