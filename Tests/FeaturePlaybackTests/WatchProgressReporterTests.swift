#if canImport(AVFoundation)
import CoreModels
import XCTest

@testable import FeaturePlayback

@MainActor
final class WatchProgressReporterTests: XCTestCase {

    private var retainedHosts: [SpyReporterHost] = []

    override func tearDown() {
        retainedHosts.removeAll()
        super.tearDown()
    }

    private func makeSUT(
        checkpointInterval: TimeInterval = 0, // loop off by default; tests call emitCheckpoint directly
        item: MediaItem = MediaItem(id: "item-1", title: "Ep", kind: .episode, runtime: 1_000)
    ) -> (WatchProgressReporter, SpyReporterHost, RecordingProvider, CheckpointRecorder) {
        let host = SpyReporterHost()
        host.request = PlaybackRequest(
            item: item,
            streamURL: URL(string: "https://example.test/a.m3u8")!,
            playSessionID: "session-1"
        )
        host.engineDuration = 1_000
        retainedHosts.append(host)
        let provider = RecordingProvider()
        let recorder = CheckpointRecorder()
        let sut = WatchProgressReporter(
            host: host,
            provider: provider,
            itemID: "item-1",
            checkpointInterval: checkpointInterval,
            onCheckpoint: { position, percent in recorder.record(position: position, percent: percent) }
        )
        return (sut, host, provider, recorder)
    }

    // MARK: helpers

    private func waitForEvents(
        _ provider: RecordingProvider,
        count: Int,
        timeout: TimeInterval = 2.0
    ) async -> [RecordingProvider.Reported] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let events = await provider.events
            if events.count >= count { return events }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return await provider.events
    }

    // MARK: report fan-out

    func testExistingShortResumeIsNotClearedByThreshold() async {
        let (sut, host, provider, recorder) = makeSUT(
            item: MediaItem(id: "item-1", title: "Movie", kind: .movie, resumePosition: 15)
        )
        await sut.reportStart(isPaused: false, positionOverride: 15)
        host.engineCurrentTime = 20
        host.resumePosition = 20
        sut.checkpointNow()
        await sut.finishSession(position: 20, duration: 1_000)?.value
        let events = await provider.events
        XCTAssertEqual(events.map(\.position), [15, 20])
        XCTAssertEqual(recorder.positions, [20])
    }

    func testStopDrainsEarlierProgressAndRejectsLateEvents() async {
        let (sut, host, provider, _) = makeSUT()
        await sut.reportStart(isPaused: false, positionOverride: 0)
        host.engineCurrentTime = 950
        await provider.hold(.progress)
        sut.reportProgress()
        await provider.waitUntilHeld()
        sut.cancel()
        let stop = Task {
            await sut.report(event: .stop, isPaused: true, positionOverride: 950, durationOverride: 1_000)
        }
        await Task.yield()
        sut.reportStateChange(paused: false)
        sut.reportProgress()
        await provider.release()
        await stop.value
        await sut.report(event: .progress, isPaused: false)
        await sut.report(event: .stop, isPaused: true)
        let events = await provider.events
        XCTAssertEqual(events.map(\.event), [.start, .progress, .stop])
        XCTAssertEqual(events.last?.position, 950)
    }

    func testStopWhileStartIsSuspendedCannotBeFollowedByDeferredPause() async {
        let (sut, _, provider, _) = makeSUT()
        await provider.hold(.start)
        let start = Task { await sut.reportStart(isPaused: false, positionOverride: 0) }
        await provider.waitUntilHeld()
        sut.reportStateChange(paused: true)
        sut.cancel()
        let stop = Task { await sut.report(event: .stop, isPaused: true, positionOverride: 950) }
        await Task.yield()
        await provider.release()
        await start.value
        await stop.value
        let events = await provider.events
        XCTAssertEqual(events.first?.event, .start)
        XCTAssertEqual(events.last?.event, .stop)
        XCTAssertEqual(events.filter { $0.event == .stop }.count, 1)
    }

    func testReplacementDefersStateUntilItsOwnStartAndKeepsQueuedIdentity() async {
        let (sut, host, provider, _) = makeSUT()
        await sut.reportStart(isPaused: false, positionOverride: 0)
        host.engineCurrentTime = 300
        await provider.hold(.progress)
        sut.reportProgress()
        await provider.waitUntilHeld()
        let outgoing = sut.finishSession(position: 300, duration: 1_000)
        host.request?.playSessionID = "session-2"
        sut.beginSession()
        host.engineCurrentTime = 400
        sut.reportStateChange(paused: true)
        let replacement = Task { await sut.reportStart(isPaused: false, positionOverride: 400) }
        await Task.yield()
        await provider.release()
        await outgoing?.value
        await replacement.value
        let events = await provider.events
        XCTAssertEqual(events.map(\.event), [.start, .progress, .stop, .start, .pause])
        XCTAssertEqual(events.map(\.sessionID), ["session-1", "session-1", "session-1", "session-2", "session-2"])
        XCTAssertEqual(events[1].position, 300)
    }

    func testCancelledCallerCannotCancelFinalReport() async {
        let (sut, _, provider, _) = makeSUT()
        await sut.reportStart(isPaused: false, positionOverride: 0)
        await provider.hold(.stop)
        let stop = Task {
            await sut.report(event: .stop, isPaused: true, positionOverride: 950, durationOverride: 1_000)
        }
        await provider.waitUntilHeld()
        stop.cancel()
        await provider.release()
        await stop.value
        let events = await provider.events
        XCTAssertEqual(events.map(\.event), [.start, .stop])
        XCTAssertEqual(events.last?.duration, 1_000)
    }

    func testStateChangesSupersedeQueuedHeartbeatsWithoutReorderingLifecycle() async {
        let (sut, host, provider, _) = makeSUT()
        await provider.hold(.start)
        let start = Task { await sut.reportStart(isPaused: false, positionOverride: 0) }
        await provider.waitUntilHeld()
        host.engineCurrentTime = 10
        sut.reportProgress()
        sut.reportStateChange(paused: true)
        sut.reportStateChange(paused: false)
        host.engineCurrentTime = 20
        sut.reportProgress()
        let stop = sut.finishSession(position: 20, duration: 1_000)
        await provider.release()
        await start.value
        await stop?.value
        let events = await provider.events
        XCTAssertEqual(events.map(\.event), [.start, .pause, .unpause, .stop])
        XCTAssertEqual(events.map(\.position), [0, 10, 10, 20])
    }

    // MARK: defer-until-started

    func testStateChangeBeforeStartIsDeferredThenFlushedWhenDifferent() async {
        let (sut, _, provider, _) = makeSUT()
        // A pause arrives before .start — must NOT report yet.
        sut.reportStateChange(paused: true)
        await Task.yield()
        var events = await provider.events
        XCTAssertTrue(events.isEmpty, "a state change before start must be deferred")

        // Start unpaused → flush the deferred pause (differs from started state).
        await sut.reportStart(isPaused: false, positionOverride: 0)
        events = await provider.events
        XCTAssertEqual(events.map(\.event), [.start, .pause])
    }

    func testDeferredStateMatchingStartIsNotReplayed() async {
        let (sut, _, provider, _) = makeSUT()
        sut.reportStateChange(paused: true)
        // Start ALSO paused → nothing to replay.
        await sut.reportStart(isPaused: true, positionOverride: 0)
        let events = await provider.events
        XCTAssertEqual(events.map(\.event), [.start], "a deferred state equal to the start state isn't replayed")
    }

    func testStateChangeAfterStartReportsImmediately() async {
        let (sut, _, provider, _) = makeSUT()
        await sut.reportStart(isPaused: false, positionOverride: 0)
        sut.reportStateChange(paused: true)
        // reportStateChange spawns a Task; poll until it lands.
        let events = await waitForEvents(provider, count: 2)
        XCTAssertEqual(events.map(\.event), [.start, .pause])
    }

    // MARK: checkpoint dedup + guards

    func testCheckpointFiresOnForwardProgressAndDedupes() async {
        let (sut, host, _, recorder) = makeSUT()
        sut.startCheckpointLoop(seedPosition: 100) // seed, loop off (interval 0)
        host.resumePosition = 100
        sut.emitCheckpoint()
        XCTAssertEqual(recorder.positions, [], "no forward progress past the seed → no checkpoint")

        host.resumePosition = 250
        sut.emitCheckpoint()
        XCTAssertEqual(recorder.positions, [250], "forward progress fires one checkpoint")

        sut.emitCheckpoint() // same position again
        XCTAssertEqual(recorder.positions, [250], "same position must not re-enqueue (dedup)")

        host.resumePosition = 250.5 // sub-1s advance
        sut.emitCheckpoint()
        XCTAssertEqual(recorder.positions, [250], "a sub-1s advance is below the dedup threshold")
    }

    func testCheckpointSuppressedWhilePausedUnlessForced() async {
        let (sut, host, _, recorder) = makeSUT()
        sut.startCheckpointLoop(seedPosition: 0)
        host.resumePosition = 300
        host.engineIsPaused = true
        sut.emitCheckpoint() // includingPaused defaults false
        XCTAssertEqual(recorder.positions, [], "a paused player must not checkpoint on the timer path")

        sut.checkpointNow() // includingPaused = true
        XCTAssertEqual(recorder.positions, [300], "an explicit checkpoint (background) fires even while paused")
    }

    func testCheckpointNoOpWithoutRequest() async {
        let (sut, host, _, recorder) = makeSUT()
        host.request = nil
        host.resumePosition = 400
        sut.checkpointNow()
        XCTAssertEqual(recorder.positions, [], "no active request → no checkpoint")
    }
}

// MARK: - Spies

@MainActor
private final class SpyReporterHost: WatchProgressReporterHost {
    var engineCurrentTime: TimeInterval = 0
    var engineDuration: TimeInterval = 0
    var engineIsPaused = false
    var controlsDuration: TimeInterval = 0
    var request: PlaybackRequest?
    var resumePosition: TimeInterval = 0

    var reporterEngineCurrentTime: TimeInterval { engineCurrentTime }
    var reporterEngineDuration: TimeInterval { engineDuration }
    var reporterEngineIsPaused: Bool { engineIsPaused }
    var reporterControlsDuration: TimeInterval { controlsDuration }
    var reporterRequest: PlaybackRequest? { request }
    var reporterResumePosition: TimeInterval { resumePosition }
}

private actor RecordingProvider: MediaProvider {
    struct Reported {
        let event: PlaybackEvent
        let position: TimeInterval
        let isPaused: Bool
        let duration: TimeInterval?
        let sessionID: String?
    }
    private(set) var events: [Reported] = []
    private var heldEvent: PlaybackEvent?
    private var continuation: CheckedContinuation<Void, Never>?

    func hold(_ event: PlaybackEvent) { heldEvent = event }
    func waitUntilHeld() async {
        let deadline = ContinuousClock.now + .seconds(2)
        while continuation == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertNotNil(continuation)
    }
    func release() { continuation?.resume(); continuation = nil }

    nonisolated let kind: ProviderKind = .jellyfin
    nonisolated let session = UserSession(
        server: MediaServer(
            id: "s", name: "S",
            baseURL: URL(string: "https://example.test")!, provider: .jellyfin
        ),
        userID: "u", userName: "U", deviceID: "d", accessToken: "t"
    )

    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {
        if heldEvent == event {
            heldEvent = nil
            await withCheckedContinuation { continuation = $0 }
        }
        try Task.checkCancellation()
        events.append(Reported(
            event: event, position: progress.positionSeconds,
            isPaused: progress.isPaused, duration: progress.durationSeconds, sessionID: progress.playSessionID
        ))
    }

    // Unused MediaProvider surface.
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { MediaItem(id: id, title: "", kind: .movie) }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: page.startIndex, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest {
        PlaybackRequest(item: MediaItem(id: itemID, title: "", kind: .movie), streamURL: URL(string: "https://example.test/a.m3u8")!)
    }
    func playbackInfo(for itemID: String, mediaSourceID: String?, forceTranscode: Bool) async throws -> PlaybackRequest {
        try await playbackInfo(for: itemID)
    }
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}

private final class CheckpointRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _positions: [TimeInterval] = []

    var positions: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _positions
    }

    func record(position: TimeInterval, percent: Double) {
        lock.lock(); _positions.append(position); lock.unlock()
    }
}
#endif
