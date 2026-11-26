import CoreModels
import XCTest
@testable import CoreUI

@MainActor
final class SeriesArtworkIdentityTests: XCTestCase {
    private func episode(_ id: String = "episode-1", ids: [String: String]) -> MediaItem {
        var item = MediaItem(
            id: id, title: "Episode title", kind: .episode, parentTitle: "The Series",
            seasonNumber: 3, episodeNumber: 4, productionYear: 2004,
            seriesID: "series-1", providerIDs: ids
        )
        item.sourceAccountID = "plex-account"
        return item
    }

    func testSeriesArtworkNeverReinterpretsChildIDsAsShowIDs() {
        let child = episode(ids: [
            "TMDb ID": "episode-tmdb", "IMDb": "ttEpisode", "TVDB ID": "episode-tvdb",
            "TvMaze": "episode-tvmaze", "PlexGuid": "plex://episode/child"
        ])
        let series = PosterCardView.seriesArtworkItem(for: child)
        XCTAssertEqual(series.id, "series-1")
        XCTAssertEqual(series.kind, .series)
        XCTAssertEqual(series.title, "The Series")
        XCTAssertEqual(series.sourceAccountID, child.sourceAccountID)
        XCTAssertNil(series.seasonNumber)
        XCTAssertNil(series.episodeNumber)
        XCTAssertNil(series.productionYear, "An episode's air year is not the show's premiere year.")
        for namespace in [ProviderIDNamespace.tmdb, .imdb, .tvdb, .tvmaze, .plexGuid] {
            XCTAssertNil(series.providerID(namespace), "\(namespace) still identifies the episode.")
        }
        XCTAssertEqual(child.providerID(.tmdb), "episode-tmdb", "The playable episode must remain unchanged.")
    }

    func testExplicitSeriesIDsWinOverEveryChildAlias() {
        let child = episode(ids: [
            "Tmdb": "child", "SeriesTheMovieDb": "series-tmdb",
            "IMDb": "ttChild", "SeriesImdb": "ttSeries",
            "Tvdb": "child-tvdb", "SeriesTheTvdb": "series-tvdb",
            "TvMaze": "child-tvmaze", "SeriesTvMaze": "series-tvmaze"
        ])
        let series = PosterCardView.seriesArtworkItem(for: child)
        XCTAssertEqual(series.providerID(.tmdb), "series-tmdb")
        XCTAssertEqual(series.providerID(.imdb), "ttSeries")
        XCTAssertEqual(series.providerID(.tvdb), "series-tvdb")
        XCTAssertEqual(series.providerID(.tvmaze), "series-tvmaze")
    }

    func testSeriesArtworkCarriesSourcedSeriesFallbacksButNeverTheEpisodeStill() throws {
        var child = episode(ids: ["Tmdb": "child-id", "SeriesTmdb": "show-id"])
        child.posterURL = URL(string: "https://library.example.test/episode.jpg")
        child.backdropURL = URL(string: "https://library.example.test/episode-backdrop.jpg")
        child.seriesPosterURL = URL(string: "https://art.example.test/show-poster.jpg")
        child.fallbackArtworkURL = URL(string: "https://art.example.test/show-backdrop.jpg")
        child.metadataProvenance[.posterURL] = MetadataAttribution(source: .tmdb)
        child.metadataProvenance[.backdropURL] = MetadataAttribution(source: .tvdb)
        child = child.taggingSource("share-account")
        let series = PosterCardView.seriesArtworkItem(for: child)
        XCTAssertEqual(series.posterURL, child.seriesPosterURL)
        XCTAssertEqual(series.backdropURL, child.fallbackArtworkURL)
        XCTAssertFalse(series.metadataArtworkURLs(for: .poster).contains { $0.value == child.posterURL })
        XCTAssertFalse(series.metadataArtworkURLs(for: .homeHero).contains { $0.value == child.backdropURL })
        XCTAssertEqual(series.metadataArtworkURLs(for: .poster).first?.source, .tmdb)
        XCTAssertEqual(series.metadataArtworkURLs(for: .homeHero).first?.source, .tvdb)
        XCTAssertTrue(series.artworkReferences(for: .poster).isEmpty)
        XCTAssertNil(series.libraryArtworkURL(series.fallbackArtworkURL))
        XCTAssertEqual(series.artworkSourceAccountID(for: try XCTUnwrap(child.seriesPosterURL)), "share-account")
        XCTAssertEqual(series.providerID(.tmdb), "show-id")
        XCTAssertEqual(child.providerID(.tmdb), "child-id")
    }

    func testShowScopedAnimeIDsSurviveEpisodeArtworkConversion() {
        let child = episode(ids: ["AniList": "21", "MAL": "20", "AniDB": "5", "Kitsu": "12"])
        let series = PosterCardView.seriesArtworkItem(for: child)
        XCTAssertEqual(MetadataQuery(series).contentType, .anime)
        XCTAssertEqual(MetadataQuery(series).animeIDs, MetadataQuery(child).seriesScoped.animeIDs)
        let explicit = episode(ids: ["AniList": "21", "SeriesAniList": "99"])
        XCTAssertEqual(PosterCardView.seriesArtworkItem(for: explicit).providerID(.aniList), "99")
    }

    func testSiblingEpisodesShareLogoMemoButAccountsStaySeparate() {
        let first = episode(ids: ["Tmdb": "child-1", "PlexGuid": "plex://episode/first"])
        let second = episode("episode-2", ids: ["Tmdb": "child-2", "PlexGuid": "plex://episode/second"])
        func key(_ item: MediaItem) -> HeroLogoMemo.Key {
            HeroLogoMemo.key(for: [], fallback: HeroLogoFallback(
                for: PosterCardView.seriesArtworkItem(for: item), resolve: { nil }
            ))
        }
        XCTAssertEqual(key(first), key(second))
        var anotherAccount = first
        anotherAccount.sourceAccountID = "other-account"
        XCTAssertNotEqual(key(first), key(anotherAccount))
    }

    func testConversionKeepsMatchingRestrictionsAndLeavesRealSeriesUntouched() {
        var child = episode(ids: [:])
        child.allowsTitleBasedMetadataMatching = false
        let target = PosterCardView.seriesArtworkItem(for: child)
        XCTAssertFalse(target.allowsTitleBasedMetadataMatching)
        XCTAssertEqual(MetadataQuery(target).title, "")
        let series = MediaItem(id: "show", title: "Real show", kind: .series, productionYear: 2002,
                               providerIDs: ["Tmdb": "show-id"])
        XCTAssertEqual(PosterCardView.seriesArtworkItem(for: series), series)
    }

    func testMissingSeriesTitleCannotSearchForAShowUsingAnEpisodeTitle() {
        let titles: [String?] = [nil, "", " \n "]
        for title in titles {
            var child = episode(ids: ["Tmdb": "episode-id"])
            child.parentTitle = title
            let query = MetadataQuery(PosterCardView.seriesArtworkItem(for: child))
            XCTAssertEqual(query.title, "")
            XCTAssertNil(query.providerIDs.providerID(.tmdb))
            child.providerIDs["SeriesTmdb"] = "show-id"
            let exact = MetadataQuery(PosterCardView.seriesArtworkItem(for: child))
            XCTAssertEqual(exact.providerIDs.providerID(.tmdb), "show-id",
                           "Missing display metadata must not discard an authoritative show ID.")
        }
    }
}
