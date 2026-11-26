import XCTest
@testable import CoreModels

final class SeriesDownloadPresentationTests: XCTestCase {
    private let season = MediaItem(id: "season-1", title: "Season 1", kind: .season)

    private func item(kind: MediaItemKind = .series) -> MediaItem {
        MediaItem(id: "show", title: "A Show", kind: kind)
    }

    func testLibraryDownloadsRemainAvailableForASeriesWithSeasons() {
        let presentation = SeriesDownloadPresentation(
            item: item(), children: [season]
        )
        XCTAssertTrue(presentation.isVisible)
        XCTAssertTrue(presentation.hasLibraryDownloads)
    }

    func testMoviesAndEpisodesKeepTheirExistingControls() {
        for kind in [MediaItemKind.movie, .episode] {
            let presentation = SeriesDownloadPresentation(
                item: item(kind: kind), children: [season]
            )
            XCTAssertFalse(presentation.isVisible)
            XCTAssertFalse(presentation.hasLibraryDownloads)
        }
    }

    func testLooseEpisodesStillProvideOfflineDownloads() {
        let episode = MediaItem(id: "episode-1", title: "Episode 1", kind: .episode)
        let presentation = SeriesDownloadPresentation(
            item: item(), children: [episode]
        )
        XCTAssertTrue(presentation.hasLibraryDownloads)
        XCTAssertTrue(presentation.isVisible)
    }

    func testBulkDownloadLabelsDescribeTheirActualActions() {
        let cases: [(SeriesDownloadAction, String, String, Bool)] = [
            (.download, "Download All Available Episodes", "arrow.down.circle", true),
            (.preparing, "Preparing Downloads…", "clock", false),
            (.pause, "Pause Downloads", "pause.circle", true),
            (.resume, "Resume Downloads", "play.circle", true)
        ]
        for (action, title, icon, enabled) in cases {
            var resource = action.title
            resource.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: resource), title)
            XCTAssertEqual(action.systemImage, icon)
            XCTAssertEqual(action.isEnabled, enabled)
        }
    }

    func testDownloadDestinationCopyNamesThePhysicalDevice() {
        let cases: [(MediaDownloadDestination, String, String)] = [
            (.iPhone, "Download to This iPhone", "Downloading to this iPhone"),
            (.iPad, "Download to This iPad", "Downloading to this iPad"),
            (.device, "Download to This Device", "Downloading to this device"),
        ]
        for (destination, title, progressTitle) in cases {
            var resource = SeriesDownloadAction.download.title(for: destination)
            resource.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: resource), title)
            resource = destination.downloadingTitle
            resource.locale = Locale(identifier: "en")
            XCTAssertEqual(String(localized: resource), progressTitle)
            for action in [SeriesDownloadAction.preparing, .pause, .resume] {
                XCTAssertEqual(
                    String(localized: action.title(for: destination)),
                    String(localized: action.title)
                )
            }
        }
    }
}
