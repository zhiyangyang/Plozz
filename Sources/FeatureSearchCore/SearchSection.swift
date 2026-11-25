import Foundation
import CoreModels

/// A titled group of search results (e.g. "Movies", "TV Shows", "Episodes"),
/// rendered as one section of the results grid.
public struct SearchSection: Identifiable, Equatable, Sendable {
    /// What a section *is*, independent of what it is called.
    ///
    /// Identity deliberately does NOT come from the displayed title. The title is
    /// localized, so keying `id` off it would change a section's SwiftUI identity
    /// the moment the user switches language — tearing down and rebuilding the
    /// grid, and dropping tvOS focus in the process. `Kind` is also what lets the
    /// view model rebuild a section (watched-state flips, availability
    /// enrichment) without round-tripping through display text.
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case movies
        case tvShows
        case episodes
        case other

        /// The section header shown to the user.
        ///
        /// These carry semantic keys rather than natural-language ones because
        /// "Movies"/"Episodes" are short nouns that recur elsewhere in the app
        /// with different senses (a library type, a filter, a media kind), and a
        /// section header is exactly the kind of string a translator needs
        /// disambiguated. Everything here is a static literal, so the compiler
        /// still extracts key, default value and comment automatically.
        public var title: LocalizedStringResource {
            switch self {
            case .movies:
                return LocalizedStringResource(
                    "search.section.movies",
                    defaultValue: "Movies",
                    comment: "Header for the search-results section listing movies."
                )
            case .tvShows:
                return LocalizedStringResource(
                    "search.section.tvShows",
                    defaultValue: "TV Shows",
                    comment: "Header for the search-results section listing TV series."
                )
            case .episodes:
                return LocalizedStringResource(
                    "search.section.episodes",
                    defaultValue: "Episodes",
                    comment: "Header for the search-results section listing individual episodes."
                )
            case .other:
                return LocalizedStringResource(
                    "search.section.other",
                    defaultValue: "Other",
                    comment: "Header for the search-results section collecting result types with no section of their own: seasons, videos, folders, collections."
                )
            }
        }
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let items: [MediaItem]

    /// The localized section header. Derived from `kind`, never stored, so it can
    /// never disagree with identity or go stale after a language change.
    public var title: LocalizedStringResource { kind.title }

    public init(kind: Kind, items: [MediaItem]) {
        self.kind = kind
        self.items = items
    }

    /// Groups a flat result list into stably-ordered sections by kind, dropping
    /// empty groups. Order mirrors the search query's `IncludeItemTypes`
    /// (movies, then series, then episodes), with any other kinds last.
    public static func sections(from items: [MediaItem]) -> [SearchSection] {
        let groups: [(kind: Kind, mediaKinds: Set<MediaItemKind>)] = [
            (.movies, [.movie]),
            (.tvShows, [.series]),
            (.episodes, [.episode]),
            (.other, [.season, .video, .folder, .collection, .unknown])
        ]
        return groups.compactMap { group in
            let matching = items.filter { group.mediaKinds.contains($0.kind) }
            return matching.isEmpty ? nil : SearchSection(kind: group.kind, items: matching)
        }
    }

}
