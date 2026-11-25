import Foundation

// MARK: - Provider capabilities (additive, non-breaking)
//
// A lightweight, declarative description of what a provider/account can do, used
// to drive conditional UI. This is an *additive* helper — it does not change the
// `MediaProvider` contract; a provider can advertise capabilities by conforming
// to `CapabilityReporting` (optional, with a `.video`-only default).

/// The broad content/feature capabilities a provider may expose.
public struct ProviderCapability: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Browse and play video libraries (movies, TV). Every provider has this.
    public static let video = ProviderCapability(rawValue: 1 << 0)
    /// Search remote subtitle services and download subtitles.
    public static let remoteSubtitles = ProviderCapability(rawValue: 1 << 2)
    /// Discover server-defined collections within a video library.
    public static let libraryCollections = ProviderCapability(rawValue: 1 << 3)
    /// Browse server video playlists in their matching libraries.
    public static let videoPlaylists = ProviderCapability(rawValue: 1 << 4)
    /// Discover the current server viewer's collections, independent of a library.
    public static let personalCollections = ProviderCapability(rawValue: 1 << 5)

    /// The baseline every provider supports today.
    public static let videoOnly: ProviderCapability = [.video]
}

/// Optional protocol a provider may adopt to advertise its capabilities. Default
/// is video-only, so existing providers need no changes.
public protocol CapabilityReporting {
    var capabilities: ProviderCapability { get }
}

public extension CapabilityReporting {
    var capabilities: ProviderCapability { .videoOnly }
}

public extension Sequence {
    /// Whether any element in this sequence advertises `capability`.
    func advertisesCapability(_ capability: ProviderCapability) -> Bool {
        contains { element in
            (element as? CapabilityReporting)?.capabilities.contains(capability) == true
        }
    }
}
