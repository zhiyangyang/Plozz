import CoreModels
import MetadataKit

/// Builds the series-scoped lookup subject used for episode-level presentation.
/// This is identity shaping only; it does not resolve any artwork itself.
public enum ArtworkSubject {
    public static func seriesArtworkItem(for item: MediaItem) -> MediaItem {
        let episode = item.artworkLookupItem
        guard episode.kind == .episode || episode.kind == .season else { return episode }
        let query = MetadataQuery(episode).seriesScoped
        let hasSeriesTitle = episode.parentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        var ids = query.providerIDs
        ids.removeProviderID(.plexGuid)
        for (namespace, value) in [
            (ProviderIDNamespace.aniList, query.animeIDs.anilist),
            (.myAnimeList, query.animeIDs.mal), (.aniDB, query.animeIDs.anidb)
        ] where ids.providerID(namespace) == nil {
            if let value { ids[namespace.canonicalKey] = String(value) }
        }
        var series = MediaItem(
            id: episode.seriesID ?? episode.id,
            title: episode.parentTitle ?? episode.title,
            kind: .series,
            genres: episode.genres,
            tags: episode.tags,
            seriesID: episode.seriesID,
            posterURL: episode.seriesPosterURL,
            backdropURL: episode.fallbackArtworkURL,
            fallbackArtworkURL: episode.fallbackArtworkURL,
            logoURL: episode.logoURL,
            providerIDs: ids,
            allowsTitleBasedMetadataMatching: episode.allowsTitleBasedMetadataMatching && hasSeriesTitle,
            metadataProvenance: episode.metadataProvenance,
            sourceAccountID: episode.sourceAccountID,
            artworkSourceAccountIDsByURL: episode.artworkSourceAccountIDsByURL
        )
        series.artworkMetadataSourcesByURL = episode.artworkMetadataSourcesByURL
        if let selection = episode.artworkSelections.first(where: { $0.placement == .seriesPoster }) {
            series.artworkSelections = [
                .init(placement: .poster, references: selection.references),
                selection
            ]
        }
        if let logo = episode.artworkSelections.first(where: { $0.placement == .logo }) {
            series.artworkSelections.append(logo)
        }
        return series
    }
}
