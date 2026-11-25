#if canImport(UIKit)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest
#if os(iOS)
import Vision
#endif

@MainActor
final class SeasonEpisodePresentationTests: XCTestCase {
    func testUnavailableArtworkIsAnEmptyThemeAwareBoxWithOnlyADashedOutline() throws {
        var themedPixels: [[UInt8]] = []
        for colorScheme in [ColorScheme.light, .dark] {
            for symbol in [MediaArtworkPlaceholder.Symbol.playback, .media] {
                let content = SeasonEpisodeRowArtwork(showsMediaEdge: symbol == .playback) {
                    MediaArtworkPlaceholder(glyphSize: 16, symbol: symbol)
                }
                .environment(\.colorScheme, colorScheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, 80, accuracy: 0.5)
                XCTAssertEqual(image.size.height, 45, accuracy: 0.5)
                if symbol == .media {
                    let bitmap = try rgbaPixels(in: image)
                    themedPixels.append(bitmap.pixels)
                    for y in 12..<(bitmap.height - 12) {
                        for x in 12..<(bitmap.width - 12) {
                            XCTAssertEqual(
                                bitmap.pixels[(y * bitmap.width + x) * 4 + 3], 0,
                                "Unavailable artwork must have no interior fill or center glyph."
                            )
                        }
                    }
                    let edgeAlpha = (16..<(bitmap.width - 16)).map { x in bitmap.pixels[x * 4 + 3] }
                    XCTAssertTrue(edgeAlpha.contains { $0 > 0 }, "The outline must reach the box edge.")
                    XCTAssertTrue(edgeAlpha.contains(0), "Dashes must have gaps, with no solid border underneath.")
                }
            }
        }
        XCTAssertNotEqual(themedPixels[0], themedPixels[1], "The gray outline must adapt to light and dark themes.")
    }

    func testUnavailableSeasonArtworkOutlinesTheEntirePortraitBox() throws {
        let renderer = ImageRenderer(content: SeasonDownloadRowArtwork(showsMediaEdge: false) {
            MediaArtworkPlaceholder(symbol: .media)
        })
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 46, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 68, accuracy: 0.5)
        let bitmap = try rgbaPixels(in: image)
        let centerAlpha = bitmap.pixels[((bitmap.height / 2) * bitmap.width + bitmap.width / 2) * 4 + 3]
        XCTAssertEqual(centerAlpha, 0)
        let edgeAlpha = (16..<(bitmap.width - 16)).map { x in bitmap.pixels[x * 4 + 3] }
        XCTAssertTrue(edgeAlpha.contains { $0 > 0 })
        XCTAssertTrue(edgeAlpha.contains(0))
    }

    private func rgbaPixels(in image: UIImage) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return (width, height, pixels)
    }

    func testMetadataRowsKeepTheSameArtworkAndWrappingAtLargeText() throws {
        for availability in [
            SeasonEpisodeAvailability.inLibrary, .missing, .unaired,
            .airingToday, .recentlyReleased, .releaseDateUnknown,
        ] {
            let content = episodeRow(number: 1, availability: availability)
                .environment(\.dynamicTypeSize, .accessibility5)
                .frame(width: 320).padding(16)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            XCTAssertEqual(image.size.width, 352, accuracy: 0.5)
            XCTAssertGreaterThan(image.size.height, 90)
            let attachment = XCTAttachment(image: image)
            attachment.name = "episode-row-large-\(availability)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testLibraryAvailabilityLeavesNoStatusLineOrReservedSpacing() throws {
        for size in [DynamicTypeSize.large, .accessibility5] {
            let title = Text("Episode title")
            let expected = try XCTUnwrap(ImageRenderer(content:
                title.environment(\.dynamicTypeSize, size)
            ).uiImage)
            let content = VStack(alignment: .leading, spacing: 3) {
                title
                SeasonEpisodeAvailabilityLabel(availability: .inLibrary)
            }
            .environment(\.dynamicTypeSize, size)
            let actual = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.5)
            XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.5)
        }
    }

    private func downloadButton(destination: MediaDownloadDestination = .iPhone) -> some View {
        Button {} label: {
            SeriesDownloadActionLabel(
                title: SeriesDownloadAction.download.title(for: destination),
                subtitle: "All available episodes in this season, for offline viewing.",
                systemImage: SeriesDownloadAction.download.systemImage
            ) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 25))
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(number: Int, availability: SeasonEpisodeAvailability) -> some View {
        SeasonEpisodeRowContent(
            number: number,
            title: number == 1 ? "The Beginning of a Very Long Adventure" : "Episode title"
        ) {
            SeasonEpisodeRowArtwork(showsMediaEdge: availability == .inLibrary) {
                MediaArtworkPlaceholder(
                    glyphSize: 16, symbol: availability == .inLibrary ? .playback : .media
                )
            }
        } status: {
            SeasonEpisodeAvailabilityLabel(
                availability: availability,
                airDate: MediaItem.calendarDayReleaseDate(from: "2026-09-13")
            )
        } accessory: {
            if availability == .inLibrary {
                Button {} label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 25))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download Episode")
            }
        }
    }

    #if os(iOS)
    func testEpisodeRowsLabelMissingAvailabilityButNotOrdinaryLibraryAvailability() throws {
        for availability in [SeasonEpisodeAvailability.inLibrary, .missing] {
            let content = episodeRow(number: 2, availability: availability)
                .font(.body)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.colorScheme, .light)
                .frame(width: 320).padding(16).background(.white)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            let text = try recognizedText(in: XCTUnwrap(renderer.uiImage)).lowercased()
            XCTAssertTrue(text.contains("episode title"), text)
            if availability == .inLibrary {
                XCTAssertFalse(text.contains("library"), text)
            } else {
                XCTAssertTrue(text.contains("missing from library"), text)
            }
        }
    }

    func testAlternateVersionAvailabilityLabelRemainsVisible() throws {
        let content = SeasonEpisodeAvailabilityLabel(
            availability: .inLibrary, title: "Available in Another Version"
        )
        .font(.body)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.colorScheme, .light)
        .frame(width: 320).padding(16).background(.white)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let text = try recognizedText(in: XCTUnwrap(renderer.uiImage)).lowercased()
        XCTAssertTrue(text.contains("available in another version"), text)
    }

    func testFullDownloadLabelNeverTruncatesOnSmallPhoneOrLargestText() throws {
        for (destination, deviceName) in [
            (MediaDownloadDestination.iPhone, "iphone"), (.iPad, "ipad"),
        ] {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let content = downloadButton(destination: destination)
                    .font(.body)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, .light)
                    .frame(width: 280)
                    .padding(16)
                    .background(.white)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                let text = try recognizedText(in: image).lowercased()
                for word in [
                    "download", "to", "this", deviceName, "all", "available",
                    "episodes", "season", "offline", "viewing",
                ] {
                    XCTAssertTrue(text.contains(word), "Missing \(word) at \(size): \(text)")
                }
                XCTAssertFalse(text.contains("…"), text)
                let attachment = XCTAttachment(image: image)
                attachment.name = "episode-download-label-\(deviceName)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }


    private func recognizedText(in image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    #endif
}
#endif
