import Foundation

/// The single, shared answer to "does the viewer own this title?".
///
/// Detail pages, poster corner marks and the action coordinator all read the
/// same predicate so a card and the page it opens cannot disagree about
/// ownership.
///
/// ``TitleClassifier/isNotOwnedForBadge(_:)`` is deliberately index-free: poster
/// cards run hundreds of times per wave and must never do index work per card,
/// so it judges the item alone. Callers that have already looked the title up in
/// the identity index pass those sources to ``TitleClassifier/classify`` instead.
public struct TitleClassification: Hashable, Sendable {
    /// The universal Plozz identity for the title.
    public let identity: TitleIdentity
    /// Whether a real, locally-validated (or index-supplied) library record exists.
    public let hasPlayableLibraryTarget: Bool
    public init(
        identity: TitleIdentity,
        hasPlayableLibraryTarget: Bool
    ) {
        self.identity = identity
        self.hasPlayableLibraryTarget = hasPlayableLibraryTarget
    }

    public var ownershipPresentation: MediaOwnershipPresentation {
        MediaOwnershipPresentation(hasValidatedPlayableSource: hasPlayableLibraryTarget)
    }

}

public enum TitleClassifier {
    /// Classify `item` against the live per-device evidence.
    ///
    /// - Parameters:
    ///   - identitySources: cross-server copies the identity index knows about. Pass
    ///     `[]` on card paths, which must judge the item alone.
    ///   - resolver: the universal identity resolver. Pass ``TitleIdentityResolver/empty``
    ///     where only the ownership answer is needed.
    public static func classify(
        _ item: MediaItem,
        identitySources: [MediaSourceRef] = [],
        resolver: TitleIdentityResolver = .empty
    ) -> TitleClassification {
        TitleClassification(
            identity: resolver.identity(for: item),
            hasPlayableLibraryTarget: item.hasPlayableLibraryTarget(
                additionalSources: identitySources
            )
        )
    }

    /// Index-free badge predicate — poster corner marks and card indicator state.
    ///
    /// ``MediaItem/locallyValidatedPlayableSource`` defaults to `true`, so a
    /// badge resting on it alone would fail *open* — every future producer that
    /// forgot to set it false would silently claim ownership, and claiming owned
    /// for something that dead-ends is the worse of the two errors on a card.
    ///
    /// Index-free by signature, and that is load-bearing: marks cannot flicker as
    /// the index warms, because warming cannot reach this function.
    public static func isNotOwnedForBadge(_ item: MediaItem) -> Bool {
        !item.hasPlayableLibraryTarget()
    }
}
