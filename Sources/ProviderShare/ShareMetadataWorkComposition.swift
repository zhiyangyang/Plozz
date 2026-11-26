import Foundation
import CoreModels

/// Local NFO/explicit-id metadata capability the work composition drives first.
protocol ShareLocalMetadataRunning: Sendable {
    func resolvePendingSlice(maxItems: Int, maxDuration: Duration) async -> ShareEnrichmentSliceResult
    func resolveOne(itemID: String) async -> ShareLocalMetadataOutcome
}

/// Scheduler-only local artwork inspection. Unlike NFO work this intentionally
/// has no opened-item fast path, so Home/grid/detail reads never open artwork.
protocol ShareLocalArtworkProbing: Sendable {
    func resolvePendingSlice(maxItems: Int, maxDuration: Duration) async -> ShareEnrichmentSliceResult
}

extension ShareLocalMetadataEnricher: ShareLocalMetadataRunning {}
extension ShareLocalArtworkProbeWorker: ShareLocalArtworkProbing {}

/// Composes local NFO/explicit-id work and local artwork probing for one account,
/// fencing cancellation at every boundary.
enum ShareMetadataWorkComposition {
    static func runSlice(
        accountKey: String,
        budget: ShareMetadataBudget,
        local: some ShareLocalMetadataRunning,
        artwork: some ShareLocalArtworkProbing,
        sharePermits: @Sendable @escaping () async -> Bool = { true },
        isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) async -> ShareEnrichmentSliceResult {
        ShareBackgroundActivity.enrichStarted()
        defer { ShareBackgroundActivity.enrichFinished() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget.sliceDuration)
        var attempted = 0
        var hasMore = false
        var retryAfter: Duration?
        var measured: Duration = .zero
        var saturated = false
        var ranAnyPass = false

        while !isCancelled(), clock.now < deadline {
            // A scan owns share I/O; yielding to it is the point of the permit.
            guard await sharePermits() else { break }
            let passStart = clock.now
            let localResult = await local.resolvePendingSlice(
                maxItems: budget.itemsPerSlice,
                maxDuration: budget.sliceDuration
            )
            if isCancelled() { hasMore = true; break }
            let elapsed = passStart.duration(to: clock.now)
            let remaining = budget.sliceDuration > elapsed ? budget.sliceDuration - elapsed : .zero
            let remainingItems = max(0, budget.itemsPerSlice - localResult.attempted)
            var artworkResult = ShareEnrichmentSliceResult(attempted: 0, hasMore: false)
            if remaining > .zero, remainingItems > 0 {
                artworkResult = await artwork.resolvePendingSlice(
                    maxItems: remainingItems,
                    maxDuration: remaining
                )
            }
            let passItems = localResult.attempted + artworkResult.attempted
            ranAnyPass = true
            attempted += passItems
            measured = passStart.duration(to: clock.now)
            saturated = passItems >= budget.itemsPerSlice
            retryAfter = artworkResult.retryAfter ?? retryAfter
            hasMore = localResult.hasMore || artworkResult.hasMore
            BrowseDiagnostics.event(
                "device-lane \(accountKey) items=\(passItems) more=\(hasMore)"
            )
            // Out of work, or told to back off: stop rather than spin.
            if !hasMore || passItems == 0 { break }
            if isCancelled() { break }
            try? await Task.sleep(for: budget.delayBetweenSlices)
        }

        return ShareEnrichmentSliceResult(
            attempted: attempted,
            hasMore: hasMore || isCancelled(),
            retryAfter: retryAfter,
            // Only a real pass is evidence about this device. No pass — because a
            // scan holds the share, or the queue is empty — must not be read as
            // either slowness or headroom.
            capacity: ranAnyPass
                ? ShareMetadataCapacitySample(elapsed: measured, saturated: saturated)
                : nil
        )
    }

    static func runItem(
        accountKey: String,
        itemID: String,
        local: some ShareLocalMetadataRunning,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) async {
        ShareBackgroundActivity.enrichStarted()
        defer { ShareBackgroundActivity.enrichFinished() }
        guard !isCancelled() else { return }
        BrowseDiagnostics.event("local-item+ \(accountKey)")
        _ = await local.resolveOne(itemID: itemID)
        BrowseDiagnostics.event("local-item- \(accountKey)")
    }
}
