import XCTest
import Observation
@testable import CoreModels

/// Locks down `HeroSettings` value semantics (clamping, de-dup, lenient decode)
/// and `HeroSettingsStore` persistence (round-trip + per-profile scoping).
final class HeroSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HeroSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultIsActiveWithoutOptInCollection() {
        let d = HeroSettings.default
        XCTAssertTrue(d.isActive)
        XCTAssertEqual(d.sources, HeroSourceKind.allCases.filter { $0 != .collection })
        XCTAssertTrue(d.collections.isEmpty)
        XCTAssertTrue(d.hideWatched)
        XCTAssertFalse(d.showsRatings)
        XCTAssertEqual(d.maxItems, 8)
    }

    func testCollectionSelectionRoundTripsAndTransfersOnlyWithItsProfile() throws {
        var settings = HeroSettings.default
        settings.sources = [.collection]
        settings.collections = [
            .init(accountID: "a", libraryID: "movies", collectionID: "c", title: "Favorites"),
            .init(accountID: "b", libraryID: "shows", collectionID: "c", title: "Favorites", serverUserID: "viewer")
        ]
        XCTAssertEqual(try JSONDecoder().decode(HeroSettings.self, from: JSONEncoder().encode(settings)), settings)
        HeroSettingsStore(defaults: defaults, namespace: "one").save(settings)
        let snapshot = ProfileSettingsTransfer.capture(namespace: "one", defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "two", defaults: defaults)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "two").load(), settings)
        XCTAssertTrue(HeroSettingsStore(defaults: defaults).load().collections.isEmpty)
        XCTAssertTrue(settings.requiresExternalWatchHistory)
    }

    func testOldSettingsDoNotAdoptCollectionWithoutSelection() throws {
        let settings = try JSONDecoder().decode(HeroSettings.self, from: Data(#"{"sources":["watchlist"]}"#.utf8))
        XCTAssertTrue(settings.collections.isEmpty)
        XCTAssertFalse(settings.sources.contains(.collection))
    }

    func testPersonalCollectionSelectionRoundTripsWithoutInventingALibrary() throws {
        var settings = HeroSettings.default
        settings.sources = [.collection]
        settings.collections = [.init(accountID: "a", collectionID: "personal", title: "Favorites", serverUserID: "viewer")]
        HeroSettingsStore(defaults: defaults, namespace: "one").save(settings)
        let snapshot = ProfileSettingsTransfer.capture(namespace: "one", defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "two", defaults: defaults)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "two").load(), settings)
        XCTAssertNil(settings.collections.first?.libraryKey)
        let legacy = try JSONDecoder().decode(HeroCollectionSelection.self, from: Data(
            #"{"accountID":"a","libraryID":"movies","collectionID":"c","title":"Favorites"}"#.utf8
        ))
        XCTAssertEqual(legacy.libraryKey, "a:movies")
    }

    func testLegacyCollectionMigratesWithoutResurrectingAClearedSelection() throws {
        let legacy = #"{"sources":["collection"],"collection":{"accountID":"a","libraryID":"movies","collectionID":"c","title":"Favorites","serverUserID":"viewer"}}"#
        let migrated = try JSONDecoder().decode(HeroSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(migrated.collections, [
            .init(accountID: "a", libraryID: "movies", collectionID: "c", title: "Favorites", serverUserID: "viewer")
        ])
        let cleared = legacy.dropLast() + #","collections":[]}"#
        XCTAssertTrue(try JSONDecoder().decode(HeroSettings.self, from: Data(cleared.utf8)).collections.isEmpty)
        let encoded = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["collection"])
        XCTAssertNotNil(object["collections"])
    }

    func testSelectionIdentityIncludesScopeButNotItsDisplayName() {
        let first = HeroCollectionSelection(accountID: "a", libraryID: "movies", collectionID: "c", title: "Original", serverUserID: "viewer")
        let renamed = HeroCollectionSelection(accountID: "a", libraryID: "movies", collectionID: "c", title: "Renamed", serverUserID: "viewer")
        let others: [HeroCollectionSelection] = [
            .init(accountID: "b", libraryID: "movies", collectionID: "c", title: "Original", serverUserID: "viewer"),
            .init(accountID: "a", libraryID: "shows", collectionID: "c", title: "Original", serverUserID: "viewer"),
            .init(accountID: "a", libraryID: "movies", collectionID: "c", title: "Original", serverUserID: "child"),
            .init(accountID: "a", collectionID: "c", title: "Original", serverUserID: "viewer")
        ]
        XCTAssertEqual(first.id, renamed.id)
        XCTAssertEqual(HeroCollectionSelection.normalized([first, renamed] + others), [first] + others)
    }

    func testMaxItemsIsClamped() {
        let low = HeroSettings(isEnabled: true, sources: [.continueWatching], maxItems: 0, randomLibraryKeys: [], autoAdvance: true, autoAdvanceSeconds: 10)
        XCTAssertEqual(low.maxItems, HeroSettings.maxItemsRange.lowerBound)
        let high = HeroSettings(isEnabled: true, sources: [.continueWatching], maxItems: 999, randomLibraryKeys: [], autoAdvance: true, autoAdvanceSeconds: 10)
        XCTAssertEqual(high.maxItems, HeroSettings.maxItemsRange.upperBound)
    }

    func testAutoAdvanceSecondsIsClamped() {
        let s = HeroSettings(isEnabled: true, sources: [.watchlist], maxItems: 5, randomLibraryKeys: [], autoAdvance: true, autoAdvanceSeconds: 1)
        XCTAssertEqual(s.autoAdvanceSeconds, HeroSettings.autoAdvanceRange.lowerBound)
    }

    func testDuplicateSourcesAreCollapsedPreservingOrder() {
        let s = HeroSettings(isEnabled: true, sources: [.watchlist, .continueWatching, .watchlist], maxItems: 5, randomLibraryKeys: [], autoAdvance: false, autoAdvanceSeconds: 10)
        XCTAssertEqual(s.sources, [.watchlist, .continueWatching])
    }

    func testEmptySourcesIsNotActive() {
        let s = HeroSettings(isEnabled: true, sources: [], maxItems: 5, randomLibraryKeys: [], autoAdvance: false, autoAdvanceSeconds: 10)
        XCTAssertFalse(s.isActive)
    }

    func testDisabledIsNotActive() {
        let s = HeroSettings(isEnabled: false, sources: [.watchlist], maxItems: 5, randomLibraryKeys: [], autoAdvance: false, autoAdvanceSeconds: 10)
        XCTAssertFalse(s.isActive)
    }

    func testStoreRoundTrip() {
        let store = HeroSettingsStore(defaults: defaults, namespace: nil)
        let settings = HeroSettings(isEnabled: true, sources: [.watchlist, .randomFromLibrary], maxItems: 6, hideWatched: false, randomLibraryKeys: ["a:1", "a:2"], autoAdvance: false, autoAdvanceSeconds: 20)
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testStoreDefaultsWhenEmpty() {
        let store = HeroSettingsStore(defaults: defaults, namespace: nil)
        XCTAssertEqual(store.load(), .default)
    }

    func testNamespacesAreIsolated() {
        let primary = HeroSettingsStore(defaults: defaults, namespace: nil)
        let other = HeroSettingsStore(defaults: defaults, namespace: "profile-2")
        let a = HeroSettings(isEnabled: true, sources: [.watchlist], maxItems: 3, randomLibraryKeys: [], autoAdvance: true, autoAdvanceSeconds: 10)
        let b = HeroSettings(isEnabled: false, sources: [.watchlist], maxItems: 9, randomLibraryKeys: ["x:1"], autoAdvance: false, autoAdvanceSeconds: 30)
        primary.save(a)
        other.save(b)
        XCTAssertEqual(primary.load(), a)
        XCTAssertEqual(other.load(), b)
    }

    func testLenientDecodeFillsMissingFieldsWithDefaults() throws {
        // A partial blob (as an older app version might have written) must decode
        // with the absent fields at their defaults, not fail the whole decode.
        let json = #"{"isEnabled":false,"maxItems":4}"#
        let decoded = try JSONDecoder().decode(HeroSettings.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.maxItems, 4)
        XCTAssertEqual(decoded.sources, HeroSettings.default.sources)
        XCTAssertEqual(decoded.autoAdvanceSeconds, HeroSettings.default.autoAdvanceSeconds)
        XCTAssertTrue(decoded.hideWatched)
        XCTAssertFalse(decoded.showsRatings)
    }

    // MARK: Hero style

    func testHeroShowcaseIsProfileScopedAndKeepsRowsWhenHeroIsDisabled() {
        let primary = HeroSettingsStore(defaults: defaults)
        let secondary = HeroSettingsStore(defaults: defaults, namespace: "hero-showcase-test")
        var settings = HeroSettings.default
        settings.style = .heroShowcase
        secondary.save(settings)
        XCTAssertEqual(primary.load().style, .heroShowcase)
        XCTAssertEqual(secondary.load().style, .heroShowcase)
        XCTAssertTrue(secondary.load().hasFeaturedHero)
        XCTAssertTrue(secondary.load().followsFocus)
        settings.isEnabled = false
        secondary.save(settings)
        XCTAssertFalse(secondary.load().hasFeaturedHero)
        XCTAssertTrue(secondary.load().followsFocus)
        settings.isEnabled = true
        settings.sources = []
        XCTAssertFalse(settings.hasFeaturedHero)
    }

    func testExistingSettingsKeepTheCarousel() throws {
        let decoded = try JSONDecoder().decode(
            HeroSettings.self, from: Data(#"{"isEnabled":true,"maxItems":4}"#.utf8)
        )
        XCTAssertEqual(decoded.style, .carousel)
        XCTAssertFalse(decoded.followsFocus)
        XCTAssertFalse(decoded.showsCardCaptions, "The hero names the focused title, so cards start without one")
    }

    func testFreshProfilesDefaultToSpotlightAndShowcaseWithoutChangingSavedProfiles() {
        let existing = HeroSettingsStore(defaults: defaults)
        var classic = HeroSettings.default
        classic.style = .carousel
        existing.save(classic)
        let fresh = HeroSettingsStore(defaults: defaults, namespace: "new-profile")
        XCTAssertTrue(fresh.load().spotlightEnabled)
        XCTAssertTrue(fresh.load().immersiveRows)
        XCTAssertEqual(existing.load(), classic)
    }

    func testIndependentHomeControlsPreserveTheOtherChoiceAndCustomization() throws {
        for originalStyle in HeroStyle.allCases {
            for enabled in [false, true] {
                var original = HeroSettings.default
                original.style = originalStyle
                original.isEnabled = enabled
                original.maxItems = 13
                original.sources = [.watchlist]
                for desired in [false, true] {
                    var spotlight = original
                    spotlight.spotlightEnabled = desired
                    XCTAssertEqual(spotlight.spotlightEnabled, desired)
                    XCTAssertEqual(spotlight.immersiveRows, original.immersiveRows)
                    var rows = original
                    rows.immersiveRows = desired
                    XCTAssertEqual(rows.immersiveRows, desired)
                    XCTAssertEqual(rows.spotlightEnabled, original.spotlightEnabled)
                    for changed in [spotlight, rows] {
                        XCTAssertEqual(changed.sources, original.sources)
                        XCTAssertEqual(changed.maxItems, original.maxItems)
                        let restored = try JSONDecoder().decode(HeroSettings.self, from: JSONEncoder().encode(changed))
                        XCTAssertEqual(restored, changed)
                    }
                }
            }
        }
    }

    func testLegacyShowcaseDoesNotGainSpotlightWhenChoosingClassicRows() throws {
        var settings = try JSONDecoder().decode(
            HeroSettings.self, from: Data(#"{"isEnabled":true,"style":"followsFocus"}"#.utf8)
        )
        XCTAssertFalse(settings.spotlightEnabled)
        settings.immersiveRows = false
        XCTAssertEqual(settings.style, .carousel)
        XCTAssertFalse(settings.isEnabled)
        settings.spotlightEnabled = true
        XCTAssertEqual(settings.style, .carousel)
        XCTAssertTrue(settings.hasFeaturedHero)
        settings.immersiveRows = true
        XCTAssertEqual(settings.style, .heroShowcase)
        settings.spotlightEnabled = false
        XCTAssertEqual(settings.style, .followsFocus)
        XCTAssertFalse(settings.hasFeaturedHero)
    }

    func testAnUnknownStyleFallsBackWithoutResettingOtherSettings() throws {
        let data = Data(#"{"maxItems":4,"style":"someday","backdropTransition":"spin"}"#.utf8)
        let decoded = try JSONDecoder().decode(HeroSettings.self, from: data)
        XCTAssertEqual(decoded.style, .carousel)
        XCTAssertEqual(decoded.maxItems, 4)
    }

    func testFollowingFocusRoundTripsAndNeedsOnlyTheSwitch() {
        var settings = HeroSettings.default
        settings.style = .followsFocus
        settings.showsCardCaptions = true
        settings.sources = []
        let store = HeroSettingsStore(defaults: defaults)
        store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.style, .followsFocus)
        XCTAssertTrue(loaded.showsCardCaptions)
        XCTAssertTrue(loaded.followsFocus, "Its titles come from the rows, not the carousel's sources")

        settings.isEnabled = false
        XCTAssertTrue(settings.followsFocus, "Immersive is a layout, not the Spotlight's switch")
    }

    func testInMemoryStoreRoundTrips() {
        let store = InMemoryHeroSettingsStore()
        XCTAssertEqual(store.load(), .default)
        let s = HeroSettings(isEnabled: true, sources: [.continueWatching], maxItems: 2, randomLibraryKeys: [], autoAdvance: true, autoAdvanceSeconds: 8)
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testRetiredSlideTransitionDoesNotResetOrPersistAlongsideHomeChoices() throws {
        let data = Data(#"{"style":"followsFocus","backdropTransition":"slide","showsCardCaptions":true,"maxItems":4}"#.utf8)
        let decoded = try JSONDecoder().decode(HeroSettings.self, from: data)
        XCTAssertEqual(decoded.style, .followsFocus)
        XCTAssertTrue(decoded.showsCardCaptions)
        XCTAssertEqual(decoded.maxItems, 4)

        let encoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["backdropTransition"])
    }
    // MARK: Adopting a newly-added source

    func testAnExistingProfilePicksUpASourceAddedLater() {
        // Settings store the exact list chosen, so a source added in a later version
        // would stay invisible to everyone who already has settings — the people
        // most likely to want it. A case never shown can't be one they declined.
        let legacy = #"{"isEnabled":true,"sources":["continueWatching","watchlist"],"maxItems":6}"#
        let decoded = try? JSONDecoder().decode(HeroSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded?.sources, [.continueWatching, .watchlist, .recentlyAdded])
    }

    func testASourceTheUserSwitchedOffStaysOff() {
        // The decisive case: once a blob records the generation it was offered,
        // "absent" means declined rather than unseen. Without that, turning Recently
        // Added off would switch itself back on at the next load.
        var settings = HeroSettings.default
        settings.sources = [.continueWatching, .watchlist]
        let data = try? JSONEncoder().encode(settings)
        let reloaded = data.flatMap { try? JSONDecoder().decode(HeroSettings.self, from: $0) }
        XCTAssertEqual(reloaded?.sources, [.continueWatching, .watchlist])
    }

    func testAnEmptySelectionIsNotRepopulated() {
        // No sources means "hero off by source"; adding one would switch it back on.
        let legacy = #"{"isEnabled":true,"sources":[],"maxItems":6}"#
        let decoded = try? JSONDecoder().decode(HeroSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded?.sources, [])
    }

    func testHomeRatingsOptInSurvivesPersistenceAndProfileTransfer() {
        var settings = HeroSettings.default
        settings.showsRatings = true
        let first = HeroSettingsStore(defaults: defaults, namespace: "first")
        let second = HeroSettingsStore(defaults: defaults, namespace: "second")
        first.save(settings)
        XCTAssertTrue(first.load().showsRatings)
        XCTAssertFalse(second.load().showsRatings)
        let snapshot = ProfileSettingsTransfer.capture(namespace: "first", defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "second", defaults: defaults)
        XCTAssertEqual(second.load(), settings)

        settings.showsRatings = false
        first.save(settings)
        XCTAssertFalse(first.load().showsRatings)
        XCTAssertTrue(second.load().showsRatings)
    }

    func testMissingOrMalformedRatingPreferenceDefaultsOffWithoutResettingOtherSettings() throws {
        for field in ["", #","showsRatings":null"#, #","showsRatings":"invalid""#] {
            let data = Data(#"{"maxItems":4,"hideWatched":false\#(field)}"#.utf8)
            let settings = try JSONDecoder().decode(HeroSettings.self, from: data)
            XCTAssertFalse(settings.showsRatings)
            XCTAssertEqual(settings.maxItems, 4)
            XCTAssertFalse(settings.hideWatched)
        }
    }

    func testHomeRatingsVisibilityStillHonorsSpoilersForEachPlayableKind() {
        for kind in [MediaItemKind.movie, .series, .season, .episode, .video] {
            var item = MediaItem(id: "title", title: "A title", kind: kind)
            item.isPlayed = false
            var settings = HeroSettings.default
            XCTAssertFalse(settings.shouldShowRatings(for: item, spoilerSettings: .default))
            item.isPlayed = true
            XCTAssertFalse(settings.shouldShowRatings(for: item, spoilerSettings: .default))

            settings.showsRatings = true
            let spoilers = SpoilerSettings(hideRatingsUntilWatched: true)
            XCTAssertTrue(settings.shouldShowRatings(for: item, spoilerSettings: spoilers))
            item.isPlayed = false
            XCTAssertFalse(settings.shouldShowRatings(for: item, spoilerSettings: spoilers))
            XCTAssertTrue(settings.shouldShowRatings(for: item, spoilerSettings: .default))
        }
    }

    @MainActor
    func testRatingsToggleUpdatesTheExistingHeroModel() {
        let store = InMemoryHeroSettingsStore()
        let model = HeroSettingsModel(store: store)
        XCTAssertFalse(model.settings.showsRatings)
        model.settings.showsRatings = true
        XCTAssertTrue(store.load().showsRatings)
        model.settings.showsRatings = false
        XCTAssertFalse(store.load().showsRatings)
    }
}
