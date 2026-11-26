#if canImport(SwiftUI)
import XCTest
import SwiftUI
import CoreModels
@testable import CoreUI
final class MediaFileBrowserNavigationTests: XCTestCase {
    func testFileBrowserTargetsOwningShareNotSelectedPlaybackServer() throws {
        let item = MediaItem(
            id: "series:show", title: "Show", kind: .series,
            fileBrowserContainerID: "share:files:d:TV/Show",
            sourceAccountID: "owning-share",
            additionalSourceAccountIDs: ["other-server"],
            selectedSourceAccountID: "other-server"
        )
        let target = try XCTUnwrap(item.navigationTarget(for: .browseFiles))
        XCTAssertEqual(target.id, "share:files:d:TV/Show")
        XCTAssertEqual(target.kind, .folder)
        XCTAssertEqual(target.sourceAccountID, "owning-share")
        XCTAssertFalse(target.allowsTitleBasedMetadataMatching)
        XCTAssertTrue(target.sources.isEmpty)
        XCTAssertNil(target.selectedSourceAccountID)
        XCTAssertNil(target.fileBrowserContainerID)
        XCTAssertNil(target.navigationTarget(for: .browseFiles))
    }
}

#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

#if canImport(UIKit)
@MainActor
final class PreviewCardLayoutTests: XCTestCase {
    func testRelatedPresetTitlesReserveIdenticalHeightsAtEveryWidthAndTextSize() {
        let titles = CardCaptionPreference.allCases.map(\.displayName)
        for width in [CGFloat(180), 260, 340] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                let heights = titles.map { title in
                    let card = PreviewCard(
                        title: title, isSelected: false, accent: .blue,
                        compact: true, swatchHeight: 150, titleLineLimit: nil,
                        titleSizeGroup: titles, action: {}
                    ) {
                        CardStyleSwatch(style: .borderless)
                    }
                    .environment(\.dynamicTypeSize, textSize)
                    .frame(width: width)
                    return UIHostingController(rootView: card)
                        .sizeThatFits(in: CGSize(width: width, height: 2_000)).height
                }
                for height in heights {
                    XCTAssertEqual(height, heights[0], accuracy: 0.5, "\(width) / \(textSize)")
                    XCTAssertGreaterThan(height, 150)
                    XCTAssertLessThan(height, 1_000)
                }
            }
        }
    }
}

@MainActor
final class MediaFolderCardLayoutTests: XCTestCase {
    func testFallbackNamesDoNotExpandCardsWithHiddenCaptions() {
        for style in [CardStyle.framed, .borderless] {
            for width in [CGFloat(86), 126, 220] {
                let short = MediaItem(id: "short", title: "Films", kind: .movie)
                let long = MediaItem(
                    id: "folder", title: "A very long folder name that wraps across several lines", kind: .folder
                )
                XCTAssertEqual(
                    height(MediaFolderCardLabel(item: long), width: width, style: style, captionsHidden: true),
                    height(PosterCardView(item: short, enablesAsyncArtworkFallback: false, action: {}),
                           width: width, style: style, captionsHidden: true),
                    accuracy: 0.5
                )
            }
        }
    }

    func testMixedFolderAndMediaCardsKeepIdenticalHeights() {
        for style in [CardStyle.framed, .borderless] {
            for width in [CGFloat(126), 220] {
                let plain = MediaItem(id: "d:Movies", title: "Movies", kind: .folder)
                let long = MediaItem(
                    id: "d:long", title: "A very long folder title that should never add extra lines",
                    kind: .folder, productionYear: 2020
                )
                let movie = MediaItem(id: "movie:film", title: "Film", kind: .movie, productionYear: 2020)
                let expected = height(
                    PosterCardView(item: movie, enablesAsyncArtworkFallback: false, action: {}),
                    width: width, style: style
                )
                for folder in [plain, long] {
                    XCTAssertEqual(
                        height(MediaFolderCardLabel(item: folder), width: width, style: style),
                        expected, accuracy: 0.5
                    )
                }
            }
        }
    }

    private func height<Content: View>(
        _ content: Content, width: CGFloat, style: CardStyle, captionsHidden: Bool = false
    ) -> CGFloat {
        let view = content
            .environment(\.plozzCardStyle, style)
            .environment(\.plozzCardCaptionsHidden, captionsHidden)
            .frame(width: width, alignment: .topLeading)
        return UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: 1_000))
            .height
    }
}
#endif

final class PosterCardPresentationTests: XCTestCase {
    func testHiddenSuppressesOnlyWatchMarks() {
        for kind in [MediaItemKind.movie, .episode, .video, .series, .season] {
            for played in [false, true] {
                let state = MediaPlaybackIndicatorState(MediaItem(id: "item", title: "Item", kind: kind, isPlayed: played))
                XCTAssertNil(MediaPlaybackIndicatorPresentation.status(
                    for: state, hidesStatus: false, indicator: .hidden, showsEpisodeCount: true
                ))
            }
        }
        let series = MediaPlaybackIndicatorState(MediaItem(
            id: "series", title: "Series", kind: .series,
            resumePosition: 120, playedPercentage: 0.4, unwatchedEpisodeCount: 3
        ))
        XCTAssertEqual(MediaPlaybackIndicatorPresentation.status(
            for: series, hidesStatus: false, indicator: .hidden, showsEpisodeCount: true
        ), .episodeCount(3))
        XCTAssertTrue(MediaPlaybackIndicatorPresentation.showsProgress(for: series))
        XCTAssertNil(MediaPlaybackIndicatorPresentation.status(
            for: series, hidesStatus: false, indicator: .hidden, showsEpisodeCount: false
        ))
        let external = MediaPlaybackIndicatorState(MediaItem(
            id: "external", title: "External", kind: .movie, locallyValidatedPlayableSource: false
        ))
        XCTAssertEqual(MediaPlaybackIndicatorPresentation.status(
            for: external, hidesStatus: false, indicator: .hidden, showsEpisodeCount: true
        ), MediaPlaybackIndicatorPresentation.status(
            for: external, hidesStatus: false, indicator: .unwatched, showsEpisodeCount: true
        ))
        for watched in [false, true] {
            XCTAssertFalse(NativePosterIndicators.episode(
                isWatched: watched, hasProgress: false, isVisible: true, style: .hidden, badgeSize: 24, flagSize: 24
            ).hasContent(indicator: .hidden, showsEpisodeCount: true))
        }
    }

    func testProgressFallsBackToResumePositionWhenPercentageIsMissing() {
        for kind in [MediaItemKind.movie, .episode] {
            var item = MediaItem(id: "resume", title: "Resume", kind: kind, runtime: 3600, resumePosition: 900)
            let resumed = MediaPlaybackIndicatorState(item)
            XCTAssertEqual(resumed.playedPercentage, 0.25)
            XCTAssertTrue(MediaPlaybackIndicatorPresentation.showsProgress(for: resumed))

            item.playedPercentage = 0.4
            XCTAssertEqual(MediaPlaybackIndicatorState(item).playedPercentage, 0.4)
            item.playedPercentage = nil
            item.resumePosition = 0
            XCTAssertFalse(MediaPlaybackIndicatorPresentation.showsProgress(for: MediaPlaybackIndicatorState(item)))
            item.resumePosition = 3600
            XCTAssertFalse(MediaPlaybackIndicatorPresentation.showsProgress(for: MediaPlaybackIndicatorState(item)))
        }
    }


    func testContainerCoversAcceptTheirAuthoredShapeWithoutRelaxingMediaPosters() {
        for kind: MediaItemKind in [.collection, .playlist, .folder] {
            XCTAssertTrue(PosterCardPresentation.preservesContainerArtwork(for: kind))
        }

        for kind: MediaItemKind in [.movie, .series, .season, .episode, .video] {
            XCTAssertFalse(PosterCardPresentation.preservesContainerArtwork(for: kind))
        }
    }

    func testCollectionCoversFillWhilePlaylistAndFolderCoversStillFit() {
        XCTAssertFalse(PosterCardPresentation.fitsContainerArtwork(for: .collection))
        for kind: MediaItemKind in [.playlist, .folder] {
            XCTAssertTrue(PosterCardPresentation.fitsContainerArtwork(for: kind))
        }
    }

    func testMissingLibraryArtworkUsesNeutralMediaInsteadOfPlaybackSymbol() {
        let item = MediaItem(
            id: "metadata", title: "Not in Library", kind: .movie,
            locallyValidatedPlayableSource: false
        )
        XCTAssertEqual(MediaArtworkPlaceholder.Symbol(for: item), .media)
        XCTAssertEqual(MediaArtworkPlaceholder.Symbol.media.rawValue, "rectangle.dashed")
    }

    func testLibraryItemsWithMissingArtworkKeepTheirPlaybackSymbol() {
        for kind in [MediaItemKind.movie, .series, .season, .episode] {
            let item = MediaItem(id: "library-item", title: "In Library", kind: kind)
            XCTAssertEqual(MediaArtworkPlaceholder.Symbol(for: item), .playback)
        }
    }

func testFolderUsesDedicatedArtworkWithoutPlaybackChrome() {
        XCTAssertTrue(PosterCardPresentation.usesFolderArtwork(for: .folder))
        XCTAssertFalse(PosterCardPresentation.showsWatchStatus(for: .folder))
        XCTAssertFalse(PosterCardPresentation.showsPlaybackIndicators(for: .folder))
        XCTAssertEqual(PosterCardPresentation.folderIconSize(for: .poster), 48)
        XCTAssertEqual(PosterCardPresentation.folderIconOpacity(isFocused: false), 0.4)
        XCTAssertLessThan(
            PosterCardPresentation.folderIconOpacity(isFocused: true),
            0.6,
            "focused folder glyph stays subdued like a library-type watermark"
        )
    }

    func testPlayableMediaKeepsNormalPosterAndPlaybackChrome() {
        for kind in [MediaItemKind.movie, .series, .episode, .video] {
            XCTAssertFalse(PosterCardPresentation.usesFolderArtwork(for: kind))
            XCTAssertTrue(PosterCardPresentation.showsWatchStatus(for: kind))
            XCTAssertTrue(PosterCardPresentation.showsPlaybackIndicators(for: kind))
        }
    }

    func testNavigationContainersNeverShowPlaybackStatus() {
        for kind: MediaItemKind in [.folder, .collection, .playlist] {
            XCTAssertFalse(PosterCardPresentation.showsWatchStatus(for: kind))
            XCTAssertFalse(PosterCardPresentation.showsPlaybackIndicators(for: kind))
            for played in [false, true] {
                let state = MediaPlaybackIndicatorState(MediaItem(
                    id: "container", title: "Container", kind: kind,
                    resumePosition: 20, playedPercentage: 0.3, unwatchedEpisodeCount: 12, isPlayed: played
                ))
                XCTAssertFalse(MediaPlaybackIndicatorPresentation.showsProgress(for: state))
                for indicator in WatchStatusIndicator.allCases {
                    XCTAssertNil(MediaPlaybackIndicatorPresentation.status(
                        for: state, hidesStatus: false, indicator: indicator, showsEpisodeCount: true
                    ))
                }
            }
        }
    }

    func testZeroRemainingEpisodesNeverFallsBackToAnUnwatchedFlag() {
        for kind: MediaItemKind in [.series, .season] {
            for count in [nil, 0, 12] as [Int?] {
                let state = MediaPlaybackIndicatorState(MediaItem(
                    id: "series", title: "Series", kind: kind, unwatchedEpisodeCount: count
                ))
                XCTAssertEqual(
                    MediaPlaybackIndicatorPresentation.showsUnwatchedFlag(for: state, hidesStatus: false),
                    count != 0
                )
            }
        }
    }

    func testAnAdmittedRewatchStillShowsProgressBelowOnePercent() {
        let item = MediaItem(
            id: "rewatch",
            title: "How To Train Your Dragon",
            kind: .movie,
            resumePosition: 60,
            playedPercentage: 0.0076,
            isPlayed: true
        )

        XCTAssertTrue(
            MediaPlaybackIndicatorPresentation.showsProgress(for: MediaPlaybackIndicatorState(item)),
            "The shared time threshold must not add a one-percent floor"
        )
    }

    func testBriefPlaybackKeepsTheUnstartedPresentationAndExistingWatchedHistory() {
        for kind in [MediaItemKind.movie, .episode, .video] {
            for played in [false, true] {
                let untouched = MediaItem(id: "item", title: "Title", kind: kind, runtime: 3600, isPlayed: played)
                var brief = untouched
                brief.resumePosition = 2
                brief.playedPercentage = 2.0 / 3600
                let state = MediaPlaybackIndicatorState(brief)
                XCTAssertEqual(state, MediaPlaybackIndicatorState(untouched))
                XCTAssertFalse(MediaPlaybackIndicatorPresentation.showsProgress(for: state))
                XCTAssertEqual(
                    MediaPlaybackIndicatorPresentation.showsUnwatchedFlag(for: state, hidesStatus: false),
                    !played
                )
                XCTAssertEqual(
                    MediaPlaybackIndicatorPresentation.showsWatchedBadge(for: state, hidesStatus: false),
                    played
                )
                XCTAssertEqual(brief.resumePosition, 2)
            }
        }
    }

    /// The upper bound stays: something watched through keeps its resume point
    /// cleared and reports a full percentage, and should wear the watched mark
    /// rather than a bar pinned at the end.
    func testAFullyWatchedTitleKeepsItsWatchedMarkInsteadOfAFullBar() {
        let item = MediaItem(
            id: "seen",
            title: "Finished",
            kind: .movie,
            playedPercentage: 1,
            isPlayed: true
        )

        XCTAssertFalse(MediaPlaybackIndicatorPresentation.showsProgress(for: MediaPlaybackIndicatorState(item)))
        XCTAssertTrue(
            MediaPlaybackIndicatorPresentation.showsWatchedBadge(
                for: MediaPlaybackIndicatorState(item),
                hidesStatus: false
            )
        )
    }

    /// A container has no resume point of its own — it reports the fraction of its
    /// episodes watched — so an untouched one must not gain a bar at zero.
    func testAnUntouchedContainerShowsNoProgress() {
        let item = MediaItem(
            id: "series",
            title: "Untouched",
            kind: .series,
            playedPercentage: 0
        )

        XCTAssertFalse(MediaPlaybackIndicatorPresentation.showsProgress(for: MediaPlaybackIndicatorState(item)))
    }

    func testEpisodeCountsAreExactAndOnlyForVisibleOwnedContainers() {
        for kind in [MediaItemKind.series, .season, .episode, .movie] {
            for count in [nil, -1, 0, 1, 8, 999, 12_345] as [Int?] {
                var item = MediaItem(id: "item", title: "Item", kind: kind, playedPercentage: 0.3, unwatchedEpisodeCount: count)
                let expected = (kind == .series || kind == .season) && (count ?? 0) > 0 ? count : nil
                XCTAssertEqual(MediaPlaybackIndicatorPresentation.episodeCount(
                    for: MediaPlaybackIndicatorState(item), enabled: true, hidesStatus: false), expected)
                XCTAssertNil(MediaPlaybackIndicatorPresentation.episodeCount(
                    for: MediaPlaybackIndicatorState(item), enabled: false, hidesStatus: false))
                XCTAssertNil(MediaPlaybackIndicatorPresentation.episodeCount(
                    for: MediaPlaybackIndicatorState(item), enabled: true, hidesStatus: true))
            }
        }
    }

    func testHostedEnvironmentCarriesIndependentEpisodeCountPreference() {
        var source = EnvironmentValues()
        source.plozzShowsUnwatchedEpisodeCount = true
        source.plozzWatchStatusIndicator = .watched
        var hosted = EnvironmentValues()
        hosted.copyHostedPresentation(from: source)
        XCTAssertTrue(hosted.plozzShowsUnwatchedEpisodeCount)
        XCTAssertEqual(hosted.plozzWatchStatusIndicator, .watched)
        source.plozzShowsUnwatchedEpisodeCount = false
        hosted.copyHostedPresentation(from: source)
        XCTAssertFalse(hosted.plozzShowsUnwatchedEpisodeCount)
    }

    func testHostedEnvironmentCarriesEveryWatchIndicatorColor() {
        var source = EnvironmentValues()
        var hosted = EnvironmentValues()
        for color in WatchIndicatorColor.allCases {
            source.plozzWatchIndicatorColor = color
            hosted.copyHostedPresentation(from: source)
            XCTAssertEqual(hosted.plozzWatchIndicatorColor, color)
        }
    }

    func testHostedEnvironmentCarriesIndependentEpisodeCountStyle() {
        var source = EnvironmentValues()
        var hosted = EnvironmentValues()
        for indicator in WatchStatusIndicator.allCases {
            source.plozzWatchStatusIndicator = indicator
            for style in EpisodeCountBadgeStyle.allCases {
                source.plozzEpisodeCountBadgeStyle = style
                hosted.copyHostedPresentation(from: source)
                XCTAssertEqual(hosted.plozzWatchStatusIndicator, indicator)
                XCTAssertEqual(hosted.plozzEpisodeCountBadgeStyle, style)
            }
        }
    }

    func testProgressTakesPriorityOverWatchedBadge() {
        let item = MediaItem(
            id: "movie",
            title: "Movie",
            kind: .movie,
            playedPercentage: 0.5,
            isPlayed: true
        )

        XCTAssertTrue(MediaPlaybackIndicatorPresentation.showsProgress(for: MediaPlaybackIndicatorState(item)))
        XCTAssertFalse(
            MediaPlaybackIndicatorPresentation.showsWatchedBadge(
                for: MediaPlaybackIndicatorState(item),
                hidesStatus: false
            )
        )
    }

    func testUnwatchedFlagOnlyShowsBeforeMeaningfulPlaybackStarts() {
        let untouched = MediaItem(id: "new", title: "New", kind: .episode)
        let started = MediaItem(
            id: "started",
            title: "Started",
            kind: .episode,
            resumePosition: 60
        )

        XCTAssertTrue(
            MediaPlaybackIndicatorPresentation.showsUnwatchedFlag(
                for: MediaPlaybackIndicatorState(untouched),
                hidesStatus: false
            )
        )
        XCTAssertFalse(
            MediaPlaybackIndicatorPresentation.showsUnwatchedFlag(
                for: MediaPlaybackIndicatorState(started),
                hidesStatus: false
            )
        )
    }
    // MARK: - Series-artwork title (Continue Watching)

    /// A card that draws the show's name over its artwork must never reach for an
    /// episode's own title to do it. When the series name is missing and spoiler
    /// text is hidden, the episode title is exactly the string being protected —
    /// and this mode would print it in the largest type on the card.
    func testSeriesArtworkNeverDrawsAnEpisodeTitleWhileTextIsHidden() {
        XCTAssertEqual(
            PosterCardPresentation.seriesArtworkTitleSource(
                kind: .episode,
                hasSeriesTitle: false,
                hidesText: true
            ),
            .maskedEpisode
        )
    }

    func testSeriesArtworkPrefersTheSeriesTitleWhenKnown() {
        for hidesText in [false, true] {
            XCTAssertEqual(
                PosterCardPresentation.seriesArtworkTitleSource(
                    kind: .episode,
                    hasSeriesTitle: true,
                    hidesText: hidesText
                ),
                .seriesTitle,
                "the series name is spoiler-safe either way (hidesText: \(hidesText))"
            )
        }
    }

    /// With protection off there is nothing to protect, so a nameless episode may
    /// fall back to its own title rather than showing a bare "Episode 5".
    func testSeriesArtworkFallsBackToTheOwnTitleWhenNothingIsHidden() {
        XCTAssertEqual(
            PosterCardPresentation.seriesArtworkTitleSource(
                kind: .episode,
                hasSeriesTitle: false,
                hidesText: false
            ),
            .ownTitle
        )
    }

    /// A movie or series IS the show, so its own title is the right one.
    func testSeriesArtworkUsesTheOwnTitleForNonEpisodes() {
        for kind in [MediaItemKind.movie, .series, .season] {
            XCTAssertEqual(
                PosterCardPresentation.seriesArtworkTitleSource(
                    kind: kind,
                    hasSeriesTitle: false,
                    hidesText: true
                ),
                .ownTitle,
                "kind: \(kind)"
            )
        }
    }
}
#endif

/// Which artwork already has the show's name printed on it.
///
/// A poster is designed to be seen alone, so it is designed to name itself.
/// Laying our own wordmark over one prints the title twice — which is what the
/// "Let's go KAIKIGUMI" and "Black Cat and a Witch" cards were doing, because
/// those series have no untitled wide art and the poster is all there is.
final class TitleBearingArtworkTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    /// An episode's *series poster* names the show, so a card that falls back to
    /// it must not name it again.
    func testSeriesPosterCountsAsTitleBearing() {
        let episode = MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            seriesPosterURL: url("https://example.test/series-poster.jpg")
        )
        XCTAssertTrue(
            PosterCardPresentation.titleBearingArtwork(for: episode)
                .contains(.remote(url("https://example.test/series-poster.jpg")))
        )
    }

    /// A backdrop is not key art and is left alone — this is the common case, and
    /// the one that must keep its logo.
    func testBackdropIsNotTitleBearing() {
        let episode = MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            seriesPosterURL: url("https://example.test/series-poster.jpg"),
            backdropURL: url("https://example.test/backdrop.jpg"),
            fallbackArtworkURL: url("https://example.test/series-backdrop.jpg")
        )
        let titled = PosterCardPresentation.titleBearingArtwork(for: episode)
        XCTAssertFalse(titled.contains(.remote(url("https://example.test/backdrop.jpg"))))
        XCTAssertFalse(titled.contains(.remote(url("https://example.test/series-backdrop.jpg"))))
    }

    /// A movie or series *is* the show, so its own poster is the one that names it.
    func testOwnPosterCountsForAMovie() {
        let movie = MediaItem(
            id: "m", title: "A Movie", kind: .movie,
            posterURL: url("https://example.test/poster.jpg")
        )
        XCTAssertTrue(
            PosterCardPresentation.titleBearingArtwork(for: movie)
                .contains(.remote(url("https://example.test/poster.jpg")))
        )
    }

    /// An episode's OWN poster is its still, not the show's key art, so it names
    /// nothing and must not suppress the logo.
    func testEpisodeOwnPosterIsNotTreatedAsKeyArt() {
        let episode = MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            posterURL: url("https://example.test/episode-still.jpg")
        )
        XCTAssertFalse(
            PosterCardPresentation.titleBearingArtwork(for: episode)
                .contains(.remote(url("https://example.test/episode-still.jpg")))
        )
    }

    /// An item with no artwork at all suppresses nothing.
    func testNoArtworkSuppressesNothing() {
        let bare = MediaItem(id: "x", title: "Bare", kind: .series)
        XCTAssertTrue(PosterCardPresentation.titleBearingArtwork(for: bare).isEmpty)
    }
}

/// The blanket "an anime's backdrop is titled" rule was tried and reverted, and
/// these pin the revert so it is not re-derived from the same reasoning. Whether
/// a backdrop has the title burned into it is a fact about the pixels, and the
/// genre/id test that stood in for it was wrong in both directions at once.
final class AnimeBackdropKeepsItsLogoTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    private func animeEpisode() -> MediaItem {
        MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            genres: ["Anime"],
            fallbackArtworkURL: url("https://example.test/series-backdrop.jpg")
        )
    }

    /// The false-positive half of the reverted rule. "Arcane" carries an anime
    /// label but has an ordinary textless backdrop, and the rule took its logo
    /// away — a card the viewer had no complaint about before.
    func testAnimeLabelledBackdropIsNotTreatedAsTitled() {
        XCTAssertFalse(
            PosterCardPresentation.titleBearingArtwork(for: animeEpisode())
                .contains(.remote(url("https://example.test/series-backdrop.jpg")))
        )
    }

    /// Recognised-by-provider-id was the wider half of the same test, and is
    /// equally not evidence about the picture.
    func testAnimeProviderIDBackdropIsNotTreatedAsTitled() {
        let byID = MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            fallbackArtworkURL: url("https://example.test/b.jpg"),
            providerIDs: ["AniList": "12345"]
        )
        XCTAssertFalse(
            PosterCardPresentation.titleBearingArtwork(for: byID)
                .contains(.remote(url("https://example.test/b.jpg")))
        )
    }

    /// Live action was never affected, and still isn't — the rule that survives
    /// is about slots, and a backdrop slot is a backdrop slot either way.
    func testLiveActionBackdropIsUnaffected() {
        let liveAction = MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            genres: ["Drama"],
            fallbackArtworkURL: url("https://example.test/series-backdrop.jpg")
        )
        XCTAssertFalse(
            PosterCardPresentation.titleBearingArtwork(for: liveAction)
                .contains(.remote(url("https://example.test/series-backdrop.jpg")))
        )
    }

    /// What does survive: an anime's *poster* still names itself, exactly as a
    /// live-action one does. The slot rule is unchanged by the revert.
    func testAnimePosterIsStillTitleBearing() {
        let withPoster = MediaItem(
            id: "e", title: "Episode 7", kind: .episode,
            genres: ["Anime"],
            seriesPosterURL: url("https://example.test/series-poster.jpg")
        )
        XCTAssertTrue(
            PosterCardPresentation.titleBearingArtwork(for: withPoster)
                .contains(.remote(url("https://example.test/series-poster.jpg")))
        )
    }
}

/// Continue Watching draws the show's logo over the show's picture, so it wants a
/// picture with no lettering in it. Since no metadata field says whether a given
/// backdrop has words baked in, the card asks for art that is textless by
/// construction instead of guessing — these pin how that answer is used.
final class TextlessBackdropPreferenceTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    private var ladder: [ArtworkReference] {
        [
            .remote(url("https://server.test/backdrop.jpg")),
            .remote(url("https://server.test/poster.jpg")),
        ]
    }

    /// No answer yet is the common case on a cold launch, and must cost nothing:
    /// the card falls back to exactly the ladder it had before.
    func testNoTextlessAnswerLeavesTheLadderUntouched() {
        XCTAssertEqual(PosterCardPresentation.preferringTextless(nil, over: ladder), ladder)
    }

    /// The clean picture leads, and the server's art stays behind it — "textless"
    /// describes the URL we resolved, not a promise that it loads, and a blank
    /// card is worse than a doubled title.
    func testTextlessLeadsButServerArtIsKeptAsBackup() {
        let clean = url("https://tmdb.test/textless.jpg")
        let ordered = PosterCardPresentation.preferringTextless(clean, over: ladder)
        XCTAssertEqual(ordered.first, .remote(clean))
        XCTAssertEqual(ordered.count, ladder.count + 1)
        for reference in ladder {
            XCTAssertTrue(ordered.contains(reference), "dropped \(reference)")
        }
    }

    /// The resolved backdrop is sometimes the very picture the server was already
    /// serving. Naming it twice would make the retry loop try it twice before
    /// moving on, turning one dead URL into two wasted passes.
    func testAnAnswerAlreadyInTheLadderIsNotListedTwice() {
        let shared = url("https://server.test/backdrop.jpg")
        let ordered = PosterCardPresentation.preferringTextless(shared, over: ladder)
        XCTAssertEqual(ordered.first, .remote(shared))
        XCTAssertEqual(ordered.count, ladder.count)
        XCTAssertEqual(ordered.filter { $0 == .remote(shared) }.count, 1)
    }
}
