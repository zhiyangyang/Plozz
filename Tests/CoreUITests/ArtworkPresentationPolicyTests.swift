import CoreModels
import SwiftUI
import XCTest
@testable import CoreUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ArtworkPresentationPolicyTests: XCTestCase {
    func testDisplayIdentityRetainsCandidatesButNotSubjectPolicyOrCredentialChanges() throws {
        let first = ArtworkReference.remote(URL(string: "https://example.test/first.jpg")!)
        let second = ArtworkReference.remote(URL(string: "https://example.test/second.jpg")!)
        func identity(
            _ references: [ArtworkReference], subject: String? = "account:item", policy: String = "library"
        ) -> ArtworkDisplayIdentity {
            .init(subject: subject, policy: policy, references: references, variant: .posterCard)
        }
        XCTAssertEqual(identity([first]), identity([second, first]))
        XCTAssertNotEqual(identity([first]), identity([first], subject: "other-account:item"))
        XCTAssertNotEqual(identity([first]), identity([first], policy: "online"))
        XCTAssertNotEqual(identity([first], subject: nil), identity([second], subject: nil))
        func network(_ revision: CredentialRevision) throws -> ArtworkReference {
            .networkFile(try NetworkArtworkReference(
                accountID: "share", credentialRevision: revision, catalogArtworkID: "poster",
                representation: RemoteFileRepresentation(
                    size: 1024, identity: RemoteFileIdentity(kind: .modificationTime, modifiedAt: .distantPast),
                    consistency: .changeDetecting
                ), sourceRevision: "1"
            ))
        }
        XCTAssertNotEqual(
            identity([try network(CredentialRevision())]),
            identity([try network(CredentialRevision())])
        )
    }

    #if canImport(UIKit)
    func testLandscapeHeroesKeepSourcePreferenceBetweenUsableBackdrops() async {
        let library = ArtworkReference.remote(URL(string: "https://example.test/library.jpg")!)
        let online = URL(string: "https://example.test/online.jpg")!
        let landscape = heroImage(width: 16, height: 9)
        for prefersOnline in [true, false] {
            let result = await ArtworkFirstPaintResolver.resolve(
                references: [library], variant: .heroPreview, maxAspectRatio: 3,
                prefersLandscape: true, asyncOnlineURL: { online },
                prefersOnlineArtwork: prefersOnline,
                imageLoader: { _ in landscape }
            )
            XCTAssertEqual(result?.reference, prefersOnline ? .remote(online) : library)
        }
    }

    func testLandscapeHeroesDeferPostersUntilBothSourcesHaveBeenChecked() async {
        let libraryPoster = ArtworkReference.remote(URL(string: "https://example.test/library-poster.jpg")!)
        let libraryBackdrop = ArtworkReference.remote(URL(string: "https://example.test/library-backdrop.jpg")!)
        let online = URL(string: "https://example.test/online.jpg")!
        let portrait = heroImage(width: 2, height: 3)
        let landscape = heroImage(width: 16, height: 9)
        for prefersOnline in [true, false] {
            for onlineIsLandscape in [true, false] {
                let result = await ArtworkFirstPaintResolver.resolve(
                    references: [libraryPoster, libraryBackdrop],
                    variant: .heroPreview, maxAspectRatio: 3, prefersLandscape: true,
                    asyncOnlineURL: { online }, prefersOnlineArtwork: prefersOnline,
                    imageLoader: { reference in
                        reference == libraryBackdrop || (reference == .remote(online) && onlineIsLandscape)
                            ? landscape : portrait
                    }
                )
                XCTAssertEqual(result?.reference,
                               prefersOnline && onlineIsLandscape ? .remote(online) : libraryBackdrop)
                XCTAssertEqual(result?.isLandscape, true)
            }
        }
        let onlineOnlyBackdrop = await ArtworkFirstPaintResolver.resolve(
            references: [libraryPoster], variant: .heroPreview,
            prefersLandscape: true, asyncOnlineURL: { online }, prefersOnlineArtwork: false,
            imageLoader: { $0 == libraryPoster ? portrait : landscape }
        )
        XCTAssertEqual(onlineOnlyBackdrop?.reference, .remote(online))
    }

    func testPosterOnlyHeroesRetainFallbacksWhenLibraryBackdropsFail() async {
        let broken = ArtworkReference.remote(URL(string: "https://example.test/broken.jpg")!)
        let library = ArtworkReference.remote(URL(string: "https://example.test/poster.jpg")!)
        let online = URL(string: "https://example.test/online.jpg")!
        let portrait = heroImage(width: 2, height: 3)
        for prefersOnline in [true, false] {
            for hasLibraryPoster in [true, false] {
                let result = await ArtworkFirstPaintResolver.resolve(
                    references: hasLibraryPoster ? [broken, library] : [broken],
                    variant: .heroPreview, maxAspectRatio: 3, prefersLandscape: true,
                    asyncOnlineURL: { online }, prefersOnlineArtwork: prefersOnline,
                    imageLoader: { $0 == broken ? nil : portrait }
                )
                XCTAssertEqual(result?.reference,
                               prefersOnline || !hasLibraryPoster ? .remote(online) : library)
                XCTAssertEqual(result?.isLandscape, false)
            }
        }
        let unavailable = await ArtworkFirstPaintResolver.resolve(
            references: [broken], variant: .heroPreview, prefersLandscape: true,
            asyncOnlineURL: { online }, imageLoader: { _ in nil }
        )
        XCTAssertNil(unavailable)
    }

    func testLandscapeHeroCancellationCannotPublishADeferredPoster() async {
        let library = ArtworkReference.remote(URL(string: "https://example.test/library.jpg")!)
        let online = URL(string: "https://example.test/online-poster.jpg")!
        let portrait = heroImage(width: 2, height: 3)
        let task = Task {
            await ArtworkFirstPaintResolver.resolve(
                references: [library], variant: .heroPreview, prefersLandscape: true,
                asyncOnlineURL: { online },
                imageLoader: { reference in
                    if reference == library {
                        withUnsafeCurrentTask { $0?.cancel() }
                        return nil
                    }
                    return portrait
                }
            )
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    func testLandscapeHeroResolutionDoesNotReuseCompactPortraitFirstPaint() async {
        let library = ArtworkReference.remote(URL(string: "https://example.test/library.jpg")!)
        let online = URL(string: "https://example.test/online-poster.jpg")!
        let portrait = heroImage(width: 2, height: 3)
        let landscape = heroImage(width: 16, height: 9)
        let sharedKey = UUID().uuidString
        for prefersLandscape in [false, true] {
            let result = await ArtworkFirstPaintResolver.resolve(
                references: [library], variant: .heroPreview,
                prefersLandscape: prefersLandscape, asyncOnlineURL: { online },
                sharedKey: sharedKey,
                imageLoader: { $0 == library ? landscape : portrait }
            )
            XCTAssertEqual(result?.reference, prefersLandscape ? library : .remote(online))
        }
        XCTAssertNotEqual(
            ArtworkResolveKey.make(
                references: [library], variant: .heroPreview, maxAspectRatio: 3, pinIdentity: "hero"
            ),
            ArtworkResolveKey.make(
                references: [library], variant: .heroPreview, maxAspectRatio: 3, pinIdentity: "hero",
                prefersLandscape: true
            )
        )
    }

    private func heroImage(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testTextlessPrimaryWinsBeforeOrdinaryProviderArtwork() async throws {
        let clean = ArtworkReference.remote(URL(string: "https://example.test/clean.jpg")!)
        let library = ArtworkReference.remote(URL(string: "https://example.test/library.jpg")!)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        for preference in [ArtworkPreference.recommended, .online] {
            let policy = ArtworkPresentationPolicy(area: .continueWatching, settings: .init(preference: preference))
            let lookup = PolicyOnlineProbe()
            let result = await ArtworkFirstPaintResolver.resolve(
                references: [clean, library], prefersPrimaryReference: policy.prefersTextlessArtwork,
                variant: .landscapeCard, asyncOnlineURL: { await lookup.lookup() },
                prefersOnlineArtwork: policy.prefersOnlineArtwork,
                imageLoader: { _ in image }
            )
            XCTAssertEqual(result?.reference, clean)
            let count = await lookup.requests
            XCTAssertEqual(count, 0, "A known textless image must not be bypassed by a generic lookup.")
        }
    }

    func testUnavailableTextlessPrimaryRetainsProviderThenLibraryFallbacks() async throws {
        let clean = ArtworkReference.remote(URL(string: "https://example.test/unavailable-clean.jpg")!)
        let library = ArtworkReference.remote(URL(string: "https://example.test/library.jpg")!)
        let generic = URL(string: "https://example.test/generic.jpg")!
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image {
            UIColor.green.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        for genericLoads in [true, false] {
            let result = await ArtworkFirstPaintResolver.resolve(
                references: [clean, library], prefersPrimaryReference: true,
                variant: .landscapeCard, asyncOnlineURL: { generic },
                imageLoader: { reference in
                    reference == library || (genericLoads && reference == .remote(generic)) ? image : nil
                }
            )
            XCTAssertEqual(result?.reference, genericLoads ? .remote(generic) : library)
        }
    }

    func testTextlessPriorityHasASeparateFirstPaintCacheIdentity() {
        let references = [ArtworkReference.remote(URL(string: "https://example.test/clean.jpg")!)]
        let normal = ArtworkResolveKey.make(
            references: references, variant: .landscapeCard, maxAspectRatio: nil, pinIdentity: "series"
        )
        let textless = ArtworkResolveKey.make(
            references: references, variant: .landscapeCard, maxAspectRatio: nil, pinIdentity: "series",
            prefersPrimaryReference: true
        )
        XCTAssertNotEqual(normal, textless, "A pinned generic winner must not seed a textless-priority request.")
    }
    #endif

    func testSharedRowLayoutsResolveIndependentPageScopes() {
        for (view, area) in [
            (CardCaptionView.home, ArtworkArea.homeRows),
            (.recommended, .recommended), (.browse, .browse),
            (.collections, .collections), (.playlists, .playlists), (.watchlist, .watchlist),
            (.episodes, .episodes), (.search, .search)
        ] {
            var environment = EnvironmentValues()
            environment.plozzCardCaptionView = view
            environment.plozzArtworkSettings = .init(overrides: [area: .online])
            XCTAssertEqual(environment.plozzArtworkPolicy.area, area)
            XCTAssertTrue(environment.plozzArtworkPolicy.prefersOnlineArtwork)
        }
    }

    func testHomeAndLibraryHeroesDoNotUseTheirRowsOrEachOthersChoice() {
        let settings = ArtworkSettings(preference: .library, overrides: [.home: .online, .recommended: .online])
        let home = ArtworkPresentationPolicy(area: .homeRows, settings: settings)
        let library = home.forArea(.recommended)
        XCTAssertFalse(home.prefersOnlineArtwork)
        XCTAssertEqual(home.heroPolicy.area, .home)
        XCTAssertTrue(home.heroPolicy.prefersOnlineArtwork)
        XCTAssertTrue(library.prefersOnlineArtwork)
        XCTAssertEqual(library.heroPolicy.area, .recommendedHero)
        XCTAssertFalse(library.heroPolicy.prefersOnlineArtwork)
        XCTAssertEqual(library.heroPolicy.heroPolicy, library.heroPolicy)
    }

func testContinueWatchingRowScopeDoesNotDependOnItsParentPage() {
        for view in [CardCaptionView.home, .recommended] {
            var environment = EnvironmentValues()
            environment.plozzCardCaptionView = view
            environment.plozzArtworkSettings = .init(overrides: [.continueWatching: .library])
            environment.plozzArtworkArea = .continueWatching
            let policy = environment.plozzArtworkPolicy
            XCTAssertEqual(policy.area, .continueWatching)
            XCTAssertFalse(policy.prefersOnlineArtwork)
            XCTAssertFalse(policy.prefersTextlessArtwork)
            let episode = EpisodeArtworkSource(
                item: .init(id: "episode", title: "Episode", kind: .episode),
                spoilerSettings: .default, policy: policy
            )
            XCTAssertEqual(episode.policy.area, .continueWatching)
        }
    }

    #if canImport(UIKit)
    func testCancellingPendingProviderLookupReturnsWithoutWaitingForItsAnswer() async throws {
        let lookup = PolicyOnlineGate()
        let returned = expectation(description: "Cancelled artwork returns promptly")
        let task = Task {
            let result = await ArtworkFirstPaintResolver.resolve(
                references: [], variant: .posterCard,
                asyncOnlineURL: { await lookup.lookup() }, prefersOnlineArtwork: true
            )
            returned.fulfill()
            return result
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while await lookup.requests == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let requests = await lookup.requests
        XCTAssertEqual(requests, 1)
        task.cancel()
        await fulfillment(of: [returned], timeout: 1)
        await lookup.finish()
        let result = await task.value
        XCTAssertNil(result)
    }
    #endif

func testCaptionContextAndExplicitAreaSelectTheCorrectOverride() {
        var environment = EnvironmentValues()
        var settings = ArtworkSettings(preference: .library)
        settings.setOverride(.online, for: .search)
        environment.plozzArtworkSettings = settings
        environment.plozzCardCaptionView = .search
        XCTAssertEqual(environment.plozzArtworkPolicy.area, .search)
        XCTAssertTrue(environment.plozzArtworkPolicy.prefersOnlineArtwork)
        environment.plozzArtworkArea = .details
        XCTAssertFalse(environment.plozzArtworkPolicy.prefersOnlineArtwork)
        environment.plozzArtworkArea = nil
        XCTAssertTrue(environment.plozzArtworkPolicy.prefersOnlineArtwork)
    }

func testBackdropSourcesRespectPerAreaLibraryOverrides() throws {
        let selected = try XCTUnwrap(URL(string: "https://library.example.test/selected.jpg"))
        let alternate = ArtworkReference.remote(try XCTUnwrap(URL(string: "https://library.example.test/alternate.jpg")))
        let item = MediaItem(
            id: "series", title: "Series", kind: .series, heroBackdropURL: selected,
            artworkSelections: [.init(placement: .detailBackdrop, references: [alternate, .remote(selected)])]
        )
        var settings = ArtworkSettings()
        settings.setOverride(.library, for: .details)
        let policy = ArtworkPresentationPolicy(area: .home, settings: settings)
        XCTAssertEqual(
            MediaArtworkSource(item: item, placement: .detailBackdrop, policy: policy.forArea(.details)).references.first,
            .remote(selected)
        )
        XCTAssertEqual(
            MediaArtworkSource(item: item, placement: .detailBackdrop, policy: policy.forArea(.playback)).references.first,
            .remote(selected)
        )
    }

}

#if canImport(UIKit)
private struct PolicyArtworkLoader: ArtworkNetworkFileLoading {
    let data: Data
    func loadArtwork(_ reference: NetworkArtworkReference, maximumBytes: Int) async throws -> Data { data }
}
#endif

private actor PolicyOnlineProbe {
    private(set) var requests = 0
    func lookup() -> URL? {
        requests += 1
        return nil
    }
}


private actor PolicyOnlineGate {
    private(set) var requests = 0
    private var continuation: CheckedContinuation<URL?, Never>?

    func lookup() async -> URL? {
        requests += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
