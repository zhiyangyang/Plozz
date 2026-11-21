import Foundation

/// A provider-neutral term used to browse the current movie library.
///
/// The personal build exposes studio and tag chips on a movie's detail page.
/// Both open the same catalog page, backed by one paging model. When Emby gave
/// us the server's own id, the catalog query uses `StudioIds`/`TagIds`; the
/// name remains for display and the fallback local match.
public struct MovieCatalogTerm: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case studio
        case tag
    }

    public let kind: Kind
    public let name: String
    /// The server's own studio/tag id, when it exposed one.
    public let serverID: String?

    public init(kind: Kind, name: String, serverID: String? = nil) {
        self.kind = kind
        self.name = name
        self.serverID = serverID
    }

    public static func studio(_ name: String, id: String? = nil) -> Self {
        .init(kind: .studio, name: name, serverID: id)
    }

    public static func tag(_ name: String, id: String? = nil) -> Self {
        .init(kind: .tag, name: name, serverID: id)
    }

    public var value: String { name }

    /// Stable identity for SwiftUI and caches. Server ids are account-local and
    /// should not leak into the visible name.
    public var id: String {
        "\(kind == .studio ? "studio" : "tag"):\(name.lowercased())#\(serverID ?? "")"
    }

    public func matches(_ item: MediaItem) -> Bool {
        let candidates: [String]
        switch kind {
        case .studio:
            candidates = item.studios
        case .tag:
            candidates = item.tags
        }
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        return candidates.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(target) == .orderedSame
        }
    }
}
