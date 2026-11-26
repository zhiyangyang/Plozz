import Foundation

public struct MediaOwnershipPresentation: Equatable, Sendable {
    public let canPlay: Bool
    public let showsProviderManagement: Bool
    public let showsPlaybackDetails: Bool

    public init(hasValidatedPlayableSource: Bool) {
        canPlay = hasValidatedPlayableSource
        showsProviderManagement = hasValidatedPlayableSource
        showsPlaybackDetails = hasValidatedPlayableSource
    }
}

public extension MediaItem {
    var startsWatching: Bool {
        kind == .episode
            && (seasonNumber ?? 0) > 0
            && episodeNumber == 1
            && locallyValidatedPlayableSource
            && !isPlayed
            && !hasBeenPlayed
            && (resumePosition ?? 0) == 0
            && (playedPercentage ?? 0) == 0
    }

    var playActionTitle: LocalizedStringResource {
        if let source = externalSourceVersion {
            return source.externalLink?.actionTitle ?? LocalizedStringResource("Open Link", comment: "Open an imported external title link whose destination has not loaded yet.")
        }
        return startsWatching
            ? LocalizedStringResource("Start watching", comment: "Play an unstarted first episode. The season and episode numbers follow this label.")
            : "Play"
    }

    /// Whether this item resolves to a real playable library record. Only explicit
    /// local validation or a source supplied by the active identity index counts.
    /// `sourceAccountID`, global provider ids, and synced binding hints do not.
    func hasPlayableLibraryTarget(additionalSources: [MediaSourceRef] = []) -> Bool {
        if locallyValidatedPlayableSource { return true }
        return additionalSources.contains {
            $0.kind == nil || $0.kind == kind
        }
    }

    func ownershipPresentation(
        additionalSources: [MediaSourceRef] = []
    ) -> MediaOwnershipPresentation {
        MediaOwnershipPresentation(
            hasValidatedPlayableSource: hasPlayableLibraryTarget(
                additionalSources: additionalSources
            )
        )
    }
}
