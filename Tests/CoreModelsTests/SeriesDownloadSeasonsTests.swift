import XCTest
@testable import CoreModels

final class SeriesDownloadSeasonsTests: XCTestCase {
    private func librarySeason(_ number: Int?, id: String? = nil, title: String = "Library Season") -> MediaItem {
        var item = MediaItem(id: id ?? "library-\(number ?? -1)", title: title, kind: .season)
        item.seasonNumber = number
        return item
    }

    private func episode(_ id: String, season: Int?) -> MediaItem {
        var item = MediaItem(id: id, title: "Episode", kind: .episode)
        item.seasonNumber = season
        return item
    }

    private func english(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = Locale(identifier: "en")
        return String(localized: copy)
    }

    private func english(_ title: SeriesDownloadSeasonTitle) -> String {
        switch title {
        case .content(let value): value
        case .localized(let resource): english(resource)
        }
    }

    func testProviderSeasonNamesRemainContentEvenWhenTheyMatchAppCopy() {
        var season = librarySeason(1, id: "season")
        season.title = "Season 1"
        let list = SeriesDownloadSeasons(librarySeasons: [season], looseEpisodes: [])
        XCTAssertEqual(list.rows.count, 1)
        XCTAssertEqual(english(list.rows[0].title), "Season 1")
    }

    func testLooseEpisodesJoinTheirSeasonAndUnnumberedEpisodesRemainAccessible() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(1)],
            looseEpisodes: [episode("e1", season: 1), episode("e2", season: nil)]
        )
        XCTAssertEqual(list.rows.count, 1)
        XCTAssertEqual(list.rows[0].looseEpisodes.map(\.id), ["e1"])
        XCTAssertEqual(list.unassignedEpisodes.map(\.id), ["e2"])
    }

    func testDuplicateMetadataMergesWithoutLosingDistinctLibraryEntries() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [
                librarySeason(1, id: "one"),
                librarySeason(1, id: "two"),
                librarySeason(nil, id: "special"),
            ],
            looseEpisodes: []
        )
        XCTAssertEqual(list.rows.count, 2)
        XCTAssertEqual(list.rows[0].librarySeasons.count, 2)
        XCTAssertNil(list.rows[1].number)
    }

    func testLibraryOnlySeasonsAndStableOrderingSurviveRefresh() {
        let list = SeriesDownloadSeasons(
            librarySeasons: [librarySeason(3), librarySeason(1, id: "s1")],
            looseEpisodes: []
        )
        XCTAssertEqual(list.rows.map(\.number), [1, 3])
        XCTAssertEqual(SeriesDownloadSeasons(librarySeasons: [librarySeason(1, id: "s1"), librarySeason(3)], looseEpisodes: []), list)
    }
}
