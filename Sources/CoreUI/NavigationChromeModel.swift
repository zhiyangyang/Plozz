#if canImport(SwiftUI)
import SwiftUI
import Observation

/// Tracks how deep the on-screen destination's navigation stack is, so the custom
/// navigation rail can step aside the moment a title page opens.
///
/// A tiny observable rather than a binding threaded through every destination:
/// the stacks that know their own depth (`HomeTab`, `SearchTab`) are several
/// layers below the shell that draws the chrome, and only the chrome reads this —
/// so a push invalidates the rail and nothing else.
///
/// Used by both custom navigation layouts. Absent under the native sidebar,
/// which manages its own visibility.
///
/// Lives in `CoreUI` rather than beside the rail in `AppShell` because the stacks
/// that know their own depth are spread across feature modules (`FeatureMusic`,
/// `FeatureSettings`), and a Feature cannot import the shell.
@MainActor
@Observable
public final class NavigationChromeModel {
    /// Number of pages pushed on top of the current destination's root.
    public private(set) var stackDepth = 0
    public private(set) var transitionSuppressesFocus = false
    private var transitionHidesRail = false
    private var detailPresentations: Set<UUID> = []

    /// Whether the rail should be off screen. A pushed page is a *detail* page —
    /// a title, a person, an episode list — and those are full-bleed by design.
    public var isChromeHidden: Bool {
        stackDepth > 0 || transitionHidesRail || !detailPresentations.isEmpty
    }

    public init() {}

    public func setStackDepth(_ depth: Int) {
        guard stackDepth != depth else { return }
        stackDepth = depth
    }

    func updateTransitionInput(suppressesFocus: Bool, hidesRail: Bool) {
        if transitionSuppressesFocus != suppressesFocus { transitionSuppressesFocus = suppressesFocus }
        if transitionHidesRail != hidesRail { transitionHidesRail = hidesRail }
    }

    func detailAppeared(_ token: UUID) {
        guard !detailPresentations.contains(token) else { return }
        detailPresentations.insert(token)
    }

    func detailDisappeared(_ token: UUID) {
        guard detailPresentations.contains(token) else { return }
        detailPresentations.remove(token)
    }

    /// Called when the shell swaps destinations: the outgoing stack is torn down
    /// without reporting, so the rail would otherwise stay hidden.
    public func resetForDestinationChange() {
        detailPresentations.removeAll()
        setStackDepth(0)
    }
}

public extension View {
    /// Reports this navigation stack's depth to the shell's chrome model, so the
    /// custom chrome hides while a detail page is on top. A no-op under the native
    /// sidebar, which doesn't install a chrome model.
    func reportsNavigationDepth(_ depth: Int, to chrome: NavigationChromeModel?) -> some View {
        onChange(of: depth, initial: true) { _, newDepth in
            chrome?.setStackDepth(newDepth)
        }
    }
}

#endif
