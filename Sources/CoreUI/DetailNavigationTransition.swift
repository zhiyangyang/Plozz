import CoreModels
import Foundation
import SwiftUI

public enum DetailEntranceStage: Int, Comparable, Sendable {
    case artwork, logo, metadata, controls, episodes, complete

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct DetailEntranceTiming: Equatable, Sendable {
    public var zoom: TimeInterval = 0.4
    public var artworkPause: TimeInterval = 0.10
    public var stagger: TimeInterval = 0.09
    public var reveal: TimeInterval = 0.45
    public var episodeReveal: TimeInterval = 0.72
    public var reverse: TimeInterval = 0.28

    public init() {}
}

enum DetailEntranceMotion {
    static let pickup = UnitPoint(x: 0.22, y: 0.64)
    static let landing = UnitPoint(x: 0.30, y: 1)
    static let foregroundTravel: CGFloat = 10
    static let episodeTravel: CGFloat = 48

    static func reveal(duration: TimeInterval) -> Animation {
        .timingCurve(0.42, 0, 0.58, 1, duration: duration)
    }

    static func episodeReveal(duration: TimeInterval) -> Animation {
        .timingCurve(0.32, 0, 0.20, 1, duration: duration)
    }
}

@MainActor
public func withCinematicDetailNavigation(for item: MediaItem, _ navigate: () -> Void) {
    navigate()
}

public extension View {
    @ViewBuilder
    func detailNavigationZoom(isEnabled: Bool) -> some View {
        self
    }

    @MainActor
    func cinematicDetailNavigation(path: Binding<NavigationPath>) -> some View {
        environment(\.detailNavigationPop, {
            guard !path.wrappedValue.isEmpty else { return false }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            path.transaction(transaction).wrappedValue.removeLast()
            return true
        })
    }

    @MainActor
    func cinematicDetailNavigation<Path: RangeReplaceableCollection>(
        path: Binding<Path>
    ) -> some View where Path: MutableCollection & RandomAccessCollection, Path.Element: Hashable {
        environment(\.detailNavigationPop, {
            guard !path.wrappedValue.isEmpty else { return false }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            path.transaction(transaction).wrappedValue.removeLast()
            return true
        })
    }

    @ViewBuilder
    func cinematicDetailPage(
        isEnabled: Bool, waitsForBackdrop: Bool = false, revealsEpisodesLast: Bool = false
    ) -> some View {
        self
    }

    @ViewBuilder
    func detailEntranceStage(_ stage: DetailEntranceStage) -> some View {
        self
    }

}

private struct DetailNavigationPopKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Bool)? = nil
}

extension EnvironmentValues {
    var detailNavigationPop: (@MainActor () -> Bool)? {
        get { self[DetailNavigationPopKey.self] }
        set { self[DetailNavigationPopKey.self] = newValue }
    }
}
