import XCTest
@testable import CoreModels

final class EpisodeReleaseDisplayTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_900_000_000) // 2030-03-17
    private let enUS = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    private func western(title: String? = "Chapter 5", precision: AirDatePrecision = .dateAndTime) -> UpcomingEpisode {
        UpcomingEpisode(
            seriesIdentity: .external(source: "tvmaze", value: "1"),
            seasonNumber: 1, episodeNumber: 2, title: title,
            airDate: epoch, datePrecision: precision, source: .tvmaze, refreshedAt: epoch)
    }

    func testUpcomingBadgeNumberAndDate() {
        let d = EpisodeReleaseDisplay.make(for: .upcoming(western()), spoilersEnabled: false, locale: enUS, timeZone: utc)
        XCTAssertEqual(
            d.badge,
            LocalizedStringResource("episodeRelease.badge.upcoming", defaultValue: "Airing soon"))
        XCTAssertEqual(d.numberLabel, "S1 E2")
        XCTAssertEqual(d.title, "Chapter 5")
        XCTAssertTrue(d.isExpectedNotGuaranteed)
        XCTAssertTrue(String(localized: d.summaryLineParts.badge!).contains("Airing soon"))
        XCTAssertEqual(d.summaryLineParts.numberLabel, "S1 E2")
    }

    func testSpoilersHideTitleButKeepNumberAndDate() {
        let d = EpisodeReleaseDisplay.make(for: .upcoming(western()), spoilersEnabled: true, locale: enUS, timeZone: utc)
        XCTAssertNil(d.title, "Spoiler mode hides the upcoming title")
        XCTAssertEqual(d.numberLabel, "S1 E2")
        XCTAssertNotNil(d.dateLabel)
    }

    func testAbsoluteAnimeNumberLabel() {
        let anime = UpcomingEpisode(
            seriesIdentity: .external(source: "anilist", value: "21"),
            absoluteEpisodeNumber: 1075, airDate: epoch, datePrecision: .dateAndTime,
            source: .anilist, refreshedAt: epoch)
        let d = EpisodeReleaseDisplay.make(for: .upcoming(anime), spoilersEnabled: false, locale: enUS, timeZone: utc)
        XCTAssertEqual(d.numberLabel, "Ep 1075")
    }

    func testExactTimestampIncludesTimeDateOnlyDoesNot() {
        let exact = EpisodeReleaseDisplay.make(for: .upcoming(western(precision: .dateAndTime)), spoilersEnabled: false, locale: enUS, timeZone: utc)
        XCTAssertTrue(exact.dateLabel?.contains(":") ?? false, "An exact schedule localizes a time")
        let dateOnly = EpisodeReleaseDisplay.make(for: .upcoming(western(precision: .dateOnly)), spoilersEnabled: false, locale: enUS, timeZone: utc)
        XCTAssertFalse(dateOnly.dateLabel?.contains(":") ?? true, "A date-only schedule invents no time")
    }

    func testBadgesPerState() {
        let up = western()
        XCTAssertEqual(
            EpisodeReleaseDisplay.make(for: .airedGracePeriod(up), spoilersEnabled: false, locale: enUS, timeZone: utc).badge,
            LocalizedStringResource("episodeRelease.badge.airedGracePeriod", defaultValue: "Aired today"))
        XCTAssertEqual(
            EpisodeReleaseDisplay.make(for: .airedMissing(up), spoilersEnabled: false, locale: enUS, timeZone: utc).badge,
            LocalizedStringResource("episodeRelease.badge.airedMissing", defaultValue: "Not in your library"))
        XCTAssertEqual(
            EpisodeReleaseDisplay.make(for: .requested(up), spoilersEnabled: false, locale: enUS, timeZone: utc).badge,
            LocalizedStringResource("episodeRelease.badge.requested", defaultValue: "Requested"))
        var item = MediaItem(id: "x", title: "Ep", kind: .episode)
        item.seasonNumber = 1; item.episodeNumber = 2
        let present = EpisodeReleaseDisplay.make(for: .present(item: item), spoilersEnabled: false, locale: enUS, timeZone: utc)
        XCTAssertNil(present.badge)
        XCTAssertFalse(present.isExpectedNotGuaranteed)
    }

    func testRequestedIsDefiniteNotEstimated() {
        XCTAssertFalse(EpisodeReleaseDisplay.make(for: .requested(western()), spoilersEnabled: false, locale: enUS, timeZone: utc).isExpectedNotGuaranteed)
    }
}
