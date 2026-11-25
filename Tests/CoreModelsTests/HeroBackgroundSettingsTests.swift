import XCTest
@testable import CoreModels

final class HeroBackgroundSettingsTests: XCTestCase {
    func testTrailerPolicyPreservesIndependentSurfacePreferences() throws {
        for policy in TrailerSourcePolicy.allCases {
            for mode in HeroBackgroundMode.allCases {
                for homeEnabled in [false, true] {
                    let settings = HeroBackgroundSettings(
                        homeTrailerEnabled: homeEnabled, detailMode: mode, trailerSources: policy
                    )
                    XCTAssertEqual(settings.homeTrailerPlaybackEnabled, homeEnabled && policy != .off)
                    XCTAssertEqual(settings.detailTrailerEnabled, mode == .trailer && policy != .off)
                    XCTAssertEqual(settings.effectiveDetailMode, mode == .trailer && policy == .off ? .off : mode)
                    XCTAssertTrue(settings.availableDetailModes.contains(settings.effectiveDetailMode))
                    XCTAssertEqual(try JSONDecoder().decode(
                        HeroBackgroundSettings.self, from: JSONEncoder().encode(settings)
                    ), settings)
                }
            }
        }
        var settings = HeroBackgroundSettings()
        settings.trailerSources = .off
        XCTAssertTrue(settings.homeTrailerEnabled)
        XCTAssertEqual(settings.detailMode, .trailer)
        settings.trailerSources = .serverOnly
        XCTAssertTrue(settings.homeTrailerPlaybackEnabled)
        XCTAssertTrue(settings.detailTrailerEnabled)
    }

    func testTrailerPolicyMigrationRetainsPreviouslyAvailableSources() throws {
        for json in [
            #"{}"#, #"{"homeTrailerEnabled":false,"detailMode":"trailer"}"#,
            #"{"trailerSources":"future-value"}"#, #"{"trailerSources":42}"#
        ] {
            let settings = try JSONDecoder().decode(HeroBackgroundSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.trailerSources, .serverAndYouTube)
        }
    }

    func testTrailerSourcesAreProfileScoped() throws {
        let suite = "TrailerPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = HeroBackgroundSettingsStore(defaults: defaults)
        let second = HeroBackgroundSettingsStore(defaults: defaults, namespace: "second")
        first.save(HeroBackgroundSettings(trailerSources: .off))
        second.save(HeroBackgroundSettings(trailerSources: .serverOnly))
        XCTAssertEqual(first.load().trailerSources, .off)
        XCTAssertEqual(second.load().trailerSources, .serverOnly)
    }

    func testTrailerSearchUsesSharedDestinationOutsideHomePrerequisites() {
        for id in ["trailer-sources", "hero-trailers", "hero-trailers-muted",
                   "detail-background", "detail-trailer-muted"] {
            XCTAssertEqual(SettingsSearchCatalog.entries.first { $0.id == id }?.page, .heroTrailers)
            XCTAssertFalse(SettingsSearchCatalog.carouselHeroTargets.contains(id))
        }
    }

    func testDefaultsAreMutedTrailerOnBothSurfaces() {
        let d = HeroBackgroundSettings.default
        XCTAssertTrue(d.homeTrailerEnabled)
        XCTAssertTrue(d.homeTrailerMuted)
        XCTAssertEqual(d.detailMode, .trailer)
        XCTAssertTrue(d.detailTrailerMuted)
        XCTAssertTrue(d.detailTrailerEnabled)
    }

    func testNewFormatRoundTrips() throws {
        let s = HeroBackgroundSettings(
            homeTrailerEnabled: false, homeTrailerMuted: false,
            detailMode: .trailer, detailTrailerMuted: false
        )
        let back = try JSONDecoder().decode(
            HeroBackgroundSettings.self, from: JSONEncoder().encode(s)
        )
        XCTAssertEqual(back, s)
    }

    func testLegacyThemeMusicFallsBackToStaticDetail() throws {
        let data = Data(#"{"mode":"themeMusic","trailerMuted":false}"#.utf8)
        let s = try JSONDecoder().decode(HeroBackgroundSettings.self, from: data)
        XCTAssertEqual(s.detailMode, .off)
        XCTAssertFalse(s.detailTrailerMuted)
    }

    func testLegacyTrailerMigratesToBothSurfaces() throws {
        let data = Data(#"{"mode":"trailer","trailerMuted":true}"#.utf8)
        let s = try JSONDecoder().decode(HeroBackgroundSettings.self, from: data)
        XCTAssertEqual(s.detailMode, .trailer)
        XCTAssertTrue(s.homeTrailerEnabled)
        XCTAssertTrue(s.homeTrailerMuted)
        XCTAssertTrue(s.detailTrailerMuted)
    }

    func testLenientDecodeFallsBackForUnknownMode() throws {
        let data = Data(#"{"mode":"future-mode"}"#.utf8)
        let s = try JSONDecoder().decode(HeroBackgroundSettings.self, from: data)
        XCTAssertEqual(s, .default)
    }
}
