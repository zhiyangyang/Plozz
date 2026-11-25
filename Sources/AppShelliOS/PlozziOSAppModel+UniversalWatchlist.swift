#if os(iOS)
import AppRuntime
import CoreModels
import ProviderPlex
import FeatureWatchlistCore
import Foundation

/// iOS/iPadOS adapter onto the shared ``UniversalWatchlistHost`` runtime — see the
/// tvOS adapter for why the logic itself lives in `AppRuntime` rather than here.
extension PlozziOSAppModel: UniversalWatchlistHost {
    /// See `UniversalWatchlistHost.activeProfileAwaitsUnlock`.
    var activeProfileAwaitsUnlock: Bool { activeProfileNeedsUnlock }

    static func universalWatchlistStorageDirectory() -> URL? {
        writableStateDirectory()?
            .appendingPathComponent("PlozzMediaState", isDirectory: true)
            .appendingPathComponent("Watchlist", isDirectory: true)
    }

    var universalWatchlistStorageDirectory: URL? {
        Self.universalWatchlistStorageDirectory()
    }

    var plexWatchlistIdentityGeneration: Int { plexHomeUsers?.plexIdentityGeneration ?? 0 }

    var plexDiscoverTokens: PlexDiscoverTokenBox { plexHomeUsers.plexDiscoverTokens }



}
#endif
