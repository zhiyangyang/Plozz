import AVKit
import CoreModels
import CoreUI
import EnginePlozzigen
import SwiftUI
@testable import AppShelliOS
@testable import FeaturePlayback

struct PlayerLayoutFixture: View {
    fileprivate static let capturesFilm = ProcessInfo.processInfo.arguments.contains("--capture-open-movie")
    private static let populated = ProcessInfo.processInfo.arguments.contains("--populated-player")
    private static let sample = MediaItem(id: "sample", title: "Big Buck Bunny", kind: .movie, versions: [
        .init(id: "hd", width: 1920, height: 1080), .init(id: "sd", width: 854, height: 480)
    ])
    @State private var showsVersions = false
    @State private var version = "hd"
    @State private var model: PlayerViewModel
    @State private var timelineSampleIndex = 0
    @State private var scrubStarts = 0
    @State private var continueWatchingSelection = "none"
    @State private var continueWatchingSelections = 0
    private let chapterScrollFixture = ProcessInfo.processInfo.arguments.contains("--chapter-scroll-fixture")
    private let continueWatchingFixture = ProcessInfo.processInfo.arguments.contains("--continue-watching-player-fixture")

    init() {
        let provider = PlayerLayoutProvider()
        let isContinueWatching = ProcessInfo.processInfo.arguments.contains("--continue-watching-player-fixture")
        let episode = MediaItem(id: "layout", title: "Mud", kind: isContinueWatching ? .movie : .episode, seriesID: "series")
        let playlist = VideoPlaylistPlaybackContext(
            origin: .init(playlistID: "playlist", accountID: "layout", index: 0, totalCount: 1, item: episode),
            provider: provider
        )
        let model = PlayerViewModel(
            provider: provider, itemID: episode.id, episodeItem: episode,
            streamingOptions: Self.populated ? .init(quality: .hd1080) : nil,
            playlistContext: isContinueWatching ? nil : playlist
        )
        if isContinueWatching {
            model.continueWatchingSnapshot = {
                ["plex", "silo"].map { (accountID: String) in
                    MediaItem(
                        id: "\(accountID)-continue", title: "Continue \(accountID)", kind: .movie,
                        runtime: 3_600, resumePosition: 600, sourceAccountID: accountID
                    )
                }
            }
        }
        model.controls.duration = ProcessInfo.processInfo.arguments.contains("--long-video") ? 5_400 : 1_200
        model.controls.currentSeconds = ProcessInfo.processInfo.arguments.contains("--timeline-rollovers") ? 0 : 600
        model.controls.bufferedSeconds = 900
        model.controls.title = Self.capturesFilm ? "Big Buck Bunny" : "Wayward"
        model.controls.subtitle = Self.capturesFilm ? "" : "S1 E4 - Mud"
        model.controls.intendsPause = !Self.capturesFilm && !ProcessInfo.processInfo.arguments.contains("--playing")
        model.controls.isScrubbing = ProcessInfo.processInfo.arguments.contains("--scrubbing")
        model.controls.scrubSeconds = model.controls.currentSeconds
        model.controls.engineCapabilities = ProcessInfo.processInfo.arguments.contains("--no-playback-speed")
            ? [] : [.playbackSpeed]
        if ProcessInfo.processInfo.arguments.contains("--playback-menu") {
            model.controls.engineCapabilities.formUnion([.videoZoom, .dialogEnhance])
        }
        if Self.populated {
            model.controls.audioOptions = TrackMenuBuilder.audioOptions(
                tracks: PlayerLayoutFixtures.audio, selectedID: 1, preferred: []
            )
            model.controls.subtitleOptions = TrackMenuBuilder.subtitleOptions(
                tracks: PlayerLayoutFixtures.captions, selectedID: nil, preferred: [], detectedLanguages: [:]
            )
            model.controls.engineCapabilities.insert(.videoZoom)
            model.controls.playbackSpeed = 1
        }
        model.controls.subtitleDelayAdjustable = ProcessInfo.processInfo.arguments.contains("--subtitle-delay")
        if ProcessInfo.processInfo.arguments.contains("--audio-delay") {
            model.controls.engineCapabilities.insert(.audioDelay)
        }
        model.controls.infoCard.cast = [MediaPerson(id: "actor", name: "Actor", role: "Character")]
        _model = State(initialValue: model)
    }

    private struct PlayerLayoutProvider: StreamingQualityProviding {
        let kind = ProviderKind.jellyfin
        let session = UserSession(
            server: MediaServer(id: "layout", name: "Layout", baseURL: URL(string: "https://fixture.invalid")!,
                                provider: .jellyfin),
            userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
        )
        func libraries() async throws -> [MediaLibrary] { [] }
        func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
        func latest(limit: Int) async throws -> [MediaItem] { [] }
        func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
            throw AppError.notFound
        }
        func item(id: String) async throws -> MediaItem { throw AppError.notFound }
        func children(of itemID: String) async throws -> [MediaItem] { [] }
        func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
        func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
        func playbackInfo(for itemID: String, mediaSourceID: String?, forceTranscode: Bool,
                          streaming: StreamingPlaybackOptions) async throws -> PlaybackRequest { throw AppError.notFound }
        func releaseStreamingSession(_ request: PlaybackRequest) async {}
        func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
        func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
    }

    var body: some View {
        ZStack {
            (chapterScrollFixture ? Color(red: 0.25, green: 0.45, blue: 0.65)
                : ProcessInfo.processInfo.arguments.contains("--white-video") ? Color.white : .black)
                .ignoresSafeArea()
            if ProcessInfo.processInfo.arguments.contains("--native-avkit") {
                NativePlayerGlassFixture(showsControls: true).ignoresSafeArea()
            } else {
                if ProcessInfo.processInfo.arguments.contains("--video") {
                    NativePlayerGlassFixture(showsControls: false).ignoresSafeArea()
                }
                PlozziOSPlayerControlsOverlay(
                    viewModel: model, keyboardActions: PlozziOSPlayerKeyboardActions(),
                    hasVersions: Self.populated, versionsPresented: showsVersions,
                    onShowVersions: { showsVersions = true }, onClose: {}
                )
                .plozzSheet(isPresented: $showsVersions) {
                    PlozziOSPlayerVersionSheet(item: Self.sample, mediaSourceID: version) { version = $0 }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("player-layout-fixture")
                .accessibilityValue("scrubbing:\(model.controls.isScrubbing),starts:\(scrubStarts)")
            }
        }
        .statusBarHidden()
        .onChange(of: model.controls.isScrubbing) { _, active in
            if active { scrubStarts += 1 }
        }
        .onChange(of: model.pendingContinueWatching?.stablePresentationID) { _, _ in
            guard continueWatchingFixture, let selected = model.pendingContinueWatching else { return }
            continueWatchingSelection = selected.id
            continueWatchingSelections += 1
            model.cancelContinueWatchingSelection()
        }
        .environment(\.themePalette, light ? .light : .dark)
        .environment(\.colorScheme, light ? .light : .dark)
        .preferredColorScheme(light ? .light : .dark)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .transformEnvironment(\.plozzReduceTransparency) { value in
            if chapterScrollFixture { value = true }
        }
        .transformEnvironment(\.plozzCardStyle) { value in
            if continueWatchingFixture {
                value = ProcessInfo.processInfo.arguments.contains("--cw-borderless") ? .borderless : .framed
            }
        }
        .transformEnvironment(\.plozzCardCaptionSettings) { value in
            if continueWatchingFixture {
                value = .init(preference: ProcessInfo.processInfo.arguments.contains("--cw-hide-labels") ? .hide : .show)
            }
        }
        .transformEnvironment(\.plozzContinueWatchingPresentation) { value in
            if continueWatchingFixture {
                let arguments = ProcessInfo.processInfo.arguments
                value.artworkStyle = arguments.contains("--cw-portrait-artwork") ? .portraitPosters
                    : arguments.contains("--cw-thumbnail") ? .thumbnail : .logoAndArtwork
            }
        }
        .task {
            guard chapterScrollFixture else { return }
            await model.load()
            model.controls.duration = 3_600
            model.controls.currentSeconds = 910
            model.controls.controlsVisible = true
            model.controls.infoCard.chapters = (0..<20).map {
                .init(start: Double($0) * 180, title: "Scene \($0 + 1)")
            }
        }
        .overlay(alignment: .topTrailing) {
            if continueWatchingFixture {
                Text(verbatim: "\(continueWatchingSelection):\(continueWatchingSelections)")
                    .accessibilityIdentifier("player-cw-selection")
                    .allowsHitTesting(false)
            }
            if ProcessInfo.processInfo.arguments.contains("--timeline-rollovers") {
                Button("Advance time") {
                    let duration = model.controls.duration
                    let samples = [0, 59, 60, 599, 600, 1_799, 1_800, 3_599, 3_600, duration - 1, duration]
                        .filter { $0 <= duration }
                    timelineSampleIndex = min(timelineSampleIndex + 1, samples.count - 1)
                    model.controls.currentSeconds = samples[timelineSampleIndex]
                }
                .accessibilityIdentifier("fixture-next-time")
                .accessibilityValue("\(timelineSampleIndex)")
                .padding(.top, 110)
            }
        }
    }

    private enum PlayerLayoutFixtures {
        static let audio: [MediaTrack] = [.init(id: 1, kind: .audio, displayTitle: "English", language: "en", codec: "aac", channels: 2)]
        static let captions: [MediaTrack] = [.init(id: 2, kind: .subtitle, displayTitle: "English", language: "en", codec: "srt")]
    }

    private var light: Bool { ProcessInfo.processInfo.arguments.contains("--light") }
}

private struct NativePlayerGlassFixture: UIViewControllerRepresentable {
    let showsControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let url = PlayerLayoutFixture.capturesFilm
            ? URL.documentsDirectory.appendingPathComponent("player-capture.mp4")
            : Bundle.main.url(forResource: "four-three", withExtension: "mp4")
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            preconditionFailure("Missing local player reference video.")
        }
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = showsControls
        controller.allowsVideoFrameAnalysis = false
        if PlayerLayoutFixture.capturesFilm {
            controller.player?.isMuted = true
            controller.player?.play()
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
