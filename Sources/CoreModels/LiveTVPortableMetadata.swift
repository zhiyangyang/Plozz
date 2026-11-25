import Foundation

/// Portable feed identity for a guide mapping: never an address or local key.
public struct LiveTVPortableChannelIdentityHint: Codable, Equatable, Sendable {
    public let sourceID: String
    public let nativeID: String

    public init(sourceID: String, nativeID: String) {
        self.sourceID = sourceID
        self.nativeID = nativeID
    }

    public var isSafe: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:+"))
        return [sourceID, nativeID].allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 512 && $0.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

public struct LiveTVPortableGuideMapping: Codable, Equatable, Sendable {
    public let guideSourceID: String
    public let guideChannelID: String

    public init(guideSourceID: String, guideChannelID: String) {
        self.guideSourceID = guideSourceID
        self.guideChannelID = guideChannelID
    }

    /// Portable feed identity, not a device's configured/discovered guide ID.
    /// Exact addresses include credential changes; neither addresses nor local
    /// HMAC keys leave the device. Older unbound mappings remain pending.
    public static func boundSourceID(playlist: LiveTVPlaylistSource, guideURL: URL) -> String {
        "feed-v1-" + LiveTVChannelHealthIdentity.digest([
            "live-tv-portable-guide-v1", playlist.id, playlist.playlistURL.absoluteString,
            guideURL.absoluteString
        ])
    }

    public var hasBoundSourceIdentity: Bool {
        let prefix = "feed-v1-"
        guard guideSourceID.hasPrefix(prefix) else { return false }
        let digest = guideSourceID.dropFirst(prefix.count)
        return digest.utf8.count == 64 && digest.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    /// Arbitrary XMLTV IDs may contain addresses. Only station-ID tokens cross
    /// the non-secret channel; unsupported mappings remain in the local cache.
    public var isSafe: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:@+"))
        return [guideSourceID, guideChannelID].allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 512
                && !($0.contains(":") && $0.contains("@"))
                && $0.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}
