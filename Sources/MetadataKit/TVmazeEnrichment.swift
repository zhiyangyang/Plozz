import Foundation
import CoreModels
import CoreNetworking

/// The consolidated TVmaze result: the scattered id (KeylessIDResolver), poster/still
/// (TVmazeArtworkProvider), and overview (OverviewRouter) paths gathered behind one
/// lookup so the pipeline resolves a show once and reads every TVmaze capability
/// from it.
public struct TVmazeResolved: Sendable, Equatable {
    public var showID: Int
    public var imdbID: String?
    public var tvdbID: String?
    public var posterURL: URL?
    public var episodeStillURL: URL?
    public var overview: String?

    public init(
        showID: Int,
        imdbID: String? = nil,
        tvdbID: String? = nil,
        posterURL: URL? = nil,
        episodeStillURL: URL? = nil,
        overview: String? = nil
    ) {
        self.showID = showID
        self.imdbID = imdbID
        self.tvdbID = tvdbID
        self.posterURL = posterURL
        self.episodeStillURL = episodeStillURL
        self.overview = overview
    }
}

/// Seam over TVmaze so the enrichment adapter's mapping is testable without network.
public protocol TVmazeEnriching: Sendable {
    func resolve(_ query: MetadataQuery, wantEpisodeStill: Bool, wantOverview: Bool) async -> TVmazeResolved?
}

/// Keyless TVmaze client that resolves a western-TV show once and reads its ids,
/// poster, per-episode still, and (episode or show) summary. Consolidates the three
/// previously separate TVmaze call sites.
public struct TVmazeClient: TVmazeEnriching {
    private let http: MetadataDiscoveryHTTPClient

    public init(http: MetadataDiscoveryHTTPClient = .init()) {
        self.http = http
    }

    public func resolve(
        _ query: MetadataQuery,
        wantEpisodeStill: Bool,
        wantOverview: Bool
    ) async -> TVmazeResolved? {
        guard query.contentType == .tvShow, let show = await fetchShow(for: query) else { return nil }
        var out = TVmazeResolved(showID: show.id)
        out.imdbID = show.externals?.imdb.flatMap { $0.isEmpty ? nil : $0 }
        out.tvdbID = show.externals?.thetvdb.map(String.init)
        out.posterURL = show.image?.original.flatMap { URL(string: $0) }

        if let season = query.seasonNumber, let episode = query.episodeNumber,
           wantEpisodeStill || wantOverview,
           let ep = await fetchEpisode(showID: show.id, season: season, episode: episode) {
            if wantEpisodeStill { out.episodeStillURL = ep.image?.original.flatMap { URL(string: $0) } }
            if wantOverview { out.overview = OverviewRouter.strippedHTML(ep.summary) }
        }
        if wantOverview, out.overview == nil {
            out.overview = OverviewRouter.strippedHTML(show.summary)
        }
        return out
    }

    private func fetchShow(for query: MetadataQuery) async -> Show? {
        let known = Self.showIdentity(for: query)
        // An id lookup is exact, so it settles identity outright — no title, no year,
        // no ambiguity. TVmaze answers it with a 301 to the show, which URLSession
        // follows. Both id kinds are tried: a library can carry either.
        for url in Self.lookupURLs(for: known) {
            if let show = await MetadataHTTP.get(Show.self, url: url) { return show }
        }
        guard let escaped = metadataEscaped(query.title),
              let url = URL(string: "https://api.tvmaze.com/singlesearch/shows?q=\(escaped)"),
              let candidate = await MetadataHTTP.get(Show.self, url: url)
        else { return nil }
        // Falling back to a title search, which matches on the title alone. Two shows
        // can share a name: "Lucky!" (2022, ended) and "Lucky" (2026, airing weekly)
        // both answer to the same query, and taking the wrong one would attach a live
        // weekly schedule to a series that finished years ago.
        guard Self.isConsistentIdentity(
            candidateIMDb: candidate.externals?.imdb,
            candidateTVDB: candidate.externals?.thetvdb,
            known: known
        ) else { return nil }
        return candidate
    }

    /// Exact-lookup URLs for whichever ids the query carries, most reliable first.
    static func lookupURLs(for known: ShowIdentity) -> [URL] {
        var urls: [URL] = []
        if let imdb = known.imdb, isIMDbID(imdb),
           let url = URL(string: "https://api.tvmaze.com/lookup/shows?imdb=\(imdb)") {
            urls.append(url)
        }
        // Only a numeric TVDB id: a stored slug would 404 and cost a request.
        if let tvdb = known.tvdb, Int(tvdb) != nil,
           let url = URL(string: "https://api.tvmaze.com/lookup/shows?thetvdb=\(tvdb)") {
            urls.append(url)
        }
        return urls
    }

    /// The **show-level** external ids a query carries.
    ///
    /// A season or episode item's own `Imdb`/`Tvdb` values identify that episode,
    /// not its series, so reading them here would compare an episode's id against a
    /// show's and reject every candidate. Those kinds read the series-scoped
    /// namespaces instead, which is also a better lookup key than a title search.
    static func showIdentity(for query: MetadataQuery) -> ShowIdentity {
        let ids = query.providerIDs
        switch query.kind {
        case .season, .episode:
            return ShowIdentity(
                imdb: ids.providerID(.seriesImdb)?.nonEmptyOrNil,
                tvdb: ids.providerID(.seriesTvdb)?.nonEmptyOrNil
            )
        default:
            return ShowIdentity(
                imdb: ids.providerID(.imdb)?.nonEmptyOrNil,
                tvdb: ids.providerID(.tvdb)?.nonEmptyOrNil
            )
        }
    }

    struct ShowIdentity: Equatable {
        var imdb: String?
        var tvdb: String?
    }

    /// Whether a title-searched candidate can be the show the query names.
    ///
    /// Rejects only on a **conflict** — a well-formed id of the same kind with a
    /// different value. An absent id proves nothing (TVmaze cross-references some
    /// shows and not others), so a candidate it can't corroborate is still accepted;
    /// the server's own ids are treated as authoritative when both sides have one.
    ///
    /// Ill-formed ids are ignored rather than treated as conflicts. Servers store a
    /// TVDB *slug* ("lucky") as often as a numeric id, and a slug can never equal
    /// TVmaze's integer — comparing them would reject every candidate and silently
    /// disable TVmaze for those libraries.
    static func isConsistentIdentity(
        candidateIMDb: String?,
        candidateTVDB: Int?,
        known: ShowIdentity
    ) -> Bool {
        if let mine = known.imdb, let theirs = candidateIMDb?.nonEmptyOrNil,
           Self.isIMDbID(mine), Self.isIMDbID(theirs),
           mine.caseInsensitiveCompare(theirs) != .orderedSame {
            return false
        }
        if let mine = known.tvdb.flatMap(Int.init), let theirs = candidateTVDB, mine != theirs {
            return false
        }
        return true
    }

    static func isIMDbID(_ value: String) -> Bool {
        value.count > 2 && value.lowercased().hasPrefix("tt")
            && value.dropFirst(2).allSatisfy(\.isNumber)
    }

    private func fetchEpisode(showID: Int, season: Int, episode: Int) async -> Episode? {
        guard let url = URL(string: "https://api.tvmaze.com/shows/\(showID)/episodebynumber?season=\(season)&number=\(episode)") else {
            return nil
        }
        return await MetadataHTTP.get(Episode.self, url: url)
    }

    private struct Show: Decodable {
        let id: Int
        let summary: String?
        let image: Image?
        let externals: Externals?
        struct Externals: Decodable {
            let imdb: String?
            let thetvdb: Int?
        }
    }

    private struct Episode: Decodable {
        let summary: String?
        let image: Image?
    }

    private struct Image: Decodable {
        let original: String?
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}

/// TVmaze as the western-TV id / episode-summary / episode-still / poster-fallback
/// source. TV only; anime is served by AniList/Kitsu.
public struct TVmazeEnrichmentProvider: MetadataEnrichmentProvider {
    public let id: MetadataSource = .tvmaze
    public let capabilities: Set<MetadataCapability> = [.externalIDs, .canonicalText, .episodeStill, .poster]
    public let policy: ProviderPolicy
    private let client: any TVmazeEnriching

    public init(
        client: any TVmazeEnriching = TVmazeClient(),
        policy: ProviderPolicy = ProviderPolicy(version: 8)
    ) {
        self.client = client
        self.policy = policy
    }

    public func enrich(_ query: MetadataQuery, missing: Set<MetadataField>) async -> MetadataEnrichment {
        guard query.contentType == .tvShow else { return MetadataEnrichment() }
        var out = MetadataEnrichment()

        let wantStill = missing.contains(.episodeThumbnail)
        let wantOverview = missing.contains(.overview)
        let wantsShowResolve = wantStill || wantOverview || missing.contains(.posterURL)
            || missing.contains { $0.rawValue.hasPrefix("providerID.") }
        guard wantsShowResolve, let resolved = await client.resolve(
            query, wantEpisodeStill: wantStill, wantOverview: wantOverview
        ) else { return out }

        let sourceURL = URL(string: "https://api.tvmaze.com/shows/\(resolved.showID)")
        if let imdb = resolved.imdbID {
            out.externalIDs["Imdb"] = SourcedValue(value: imdb, source: .tvmaze, sourceURL: sourceURL)
        }
        if let tvdb = resolved.tvdbID {
            out.externalIDs["Tvdb"] = SourcedValue(value: tvdb, source: .tvmaze, sourceURL: sourceURL)
        }
        if wantOverview, let overview = resolved.overview, !overview.isEmpty {
            out.overview = SourcedValue(value: overview, source: .tvmaze, sourceURL: sourceURL)
        }
        if missing.contains(.posterURL), let poster = resolved.posterURL {
            out.posterURL = SourcedValue(value: poster, source: .tvmaze, sourceURL: sourceURL)
        }
        if wantStill, let still = resolved.episodeStillURL {
            out.episodeStillURL = SourcedValue(value: still, source: .tvmaze, sourceURL: sourceURL)
        }
        return out
    }
}
