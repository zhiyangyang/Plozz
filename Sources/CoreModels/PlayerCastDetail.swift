import Foundation

/// What the in-player Cast tab can say about one person beyond their face.
///
/// In CoreModels rather than beside the pane that shows it, because two features
/// need it and features may not depend on one another: `FeaturePlayback` renders
/// it, `FeatureHomeCore` builds it. A plain value with no UI in it belongs at the
/// layer below both.
///
/// Deliberately a plain value loaded by a closure the app supplies, rather than
/// anything the player resolves itself. Person credits need signed-in accounts,
/// provider sessions and a name-matching ladder across servers — all of which
/// live above `FeaturePlayback`. The player states what it needs and stays
/// ignorant of where it comes from.
public struct PlayerCastDetail: Sendable, Equatable {
    /// Titles in the viewer's OWN library featuring this person, current one
    /// excluded.
    ///
    /// The whole answer to "where else do I know them from", and the reason this
    /// feature needs no third party at all: every entry is a real library item.
    public var credits: [MediaItem]
    /// Who they are, when some source can say. Secondary — at three metres a
    /// viewer reads a couple of lines of this at most, which is why the credits
    /// take the space whenever there are any.
    public var biography: String?
    /// A short factual line — birth year and birthplace — when a source can say.
    ///
    /// Separate from the biography because the two fail independently: a source
    /// routinely knows where someone was born without being able to describe
    /// them, and that line is still worth the space when nothing else lands.
    public var lifeSummary: String?
    /// Whether every source has now answered.
    ///
    /// The difference between "nothing yet" and "nothing at all", which the pane
    /// must not confuse: an empty state shown mid-load tells the viewer there is
    /// nothing about someone who is about to be described.
    public var isComplete: Bool = false

    public init(
        credits: [MediaItem] = [],
        biography: String? = nil,
        lifeSummary: String? = nil,
        isComplete: Bool = false
    ) {
        self.credits = credits
        self.biography = biography
        self.lifeSummary = lifeSummary
        self.isComplete = isComplete
    }

    /// Nothing found. Distinct from "not asked yet", which is `nil` at the call
    /// site — the pane must not show an empty state while a request is in flight.
    public var isEmpty: Bool {
        credits.isEmpty && (biography?.isEmpty ?? true) && (lifeSummary?.isEmpty ?? true)
    }
}

/// Supplied by the app when it builds a player. `nil` simply means the pane
/// shows a name and a face, which is what it did before any of this existed.
///
/// A STREAM, not a single value. The answer is assembled from several servers
/// in sequence and awaiting one final result made the pane wait for the slowest
/// of them before showing anything at all. The person's own server usually
/// answers in milliseconds; another signed-in server may not.
public typealias PlayerCastDetailLoading =
    @MainActor @Sendable (MediaPerson) -> AsyncStream<PlayerCastDetail>
