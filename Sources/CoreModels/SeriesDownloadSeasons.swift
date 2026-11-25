import Foundation

/// Keeps provider names verbatim while localizing app-supplied fallbacks.
public enum SeriesDownloadSeasonTitle: Equatable, Sendable {
    case content(String)
    case localized(LocalizedStringResource)
}

/// A single season identity, with independent library content and request state.
public struct SeriesDownloadSeason: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int?
    public fileprivate(set) var librarySeasons: [MediaItem] = []
    public fileprivate(set) var looseEpisodes: [MediaItem] = []

    public var hasLibraryContent: Bool {
        !librarySeasons.isEmpty || !looseEpisodes.isEmpty
    }

    public var title: SeriesDownloadSeasonTitle {
        if let title = librarySeasons.first?.title {
            return .content(title)
        }
        if number == 0 { return .localized("Specials") }
        if let number { return .localized("Season \(number)") }
        return .localized("Season")
    }

}

/// Joins by season number, not by provider-local IDs or translated season names.
/// Unnumbered library entries remain distinct rather than being guessed away.
public struct SeriesDownloadSeasons: Equatable, Sendable {
    public let rows: [SeriesDownloadSeason]
    public let unassignedEpisodes: [MediaItem]

    public init(
        librarySeasons: [MediaItem],
        looseEpisodes: [MediaItem]
    ) {
        var byID: [String: SeriesDownloadSeason] = [:]
        var seenLibraryIDs = Set<String>()
        for season in librarySeasons where season.kind == .season && season.locallyValidatedPlayableSource {
            guard seenLibraryIDs.insert(season.stablePresentationID).inserted else { continue }
            let number = season.seasonNumber.flatMap { $0 >= 0 ? $0 : nil }
            let id = number.map { "season:\($0)" } ?? "library:\(season.stablePresentationID)"
            var row = byID[id] ?? SeriesDownloadSeason(id: id, number: number)
            row.librarySeasons.append(season)
            byID[id] = row
        }

        var unassigned: [MediaItem] = []
        var seenEpisodeIDs = Set<String>()
        for episode in looseEpisodes where episode.kind == .episode && episode.locallyValidatedPlayableSource {
            guard seenEpisodeIDs.insert(episode.stablePresentationID).inserted else { continue }
            guard let number = episode.seasonNumber, number >= 0 else {
                unassigned.append(episode)
                continue
            }
            let id = "season:\(number)"
            var row = byID[id] ?? SeriesDownloadSeason(id: id, number: number)
            row.looseEpisodes.append(episode)
            byID[id] = row
        }

        rows = byID.values.sorted {
            let left = $0.number ?? Int.max
            let right = $1.number ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }
        unassignedEpisodes = unassigned
    }
}
