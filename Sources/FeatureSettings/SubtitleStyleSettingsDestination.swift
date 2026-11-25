#if canImport(SwiftUI)
import CoreModels
import Observation
import SwiftUI

/// The app supplies the shared playback editor without making Settings depend on playback.
@MainActor
@Observable
public final class SubtitleStyleSettingsDestination {
    @ObservationIgnored private let makeContent: (Binding<SubtitleStyle>) -> AnyView

    public init(content: @escaping (Binding<SubtitleStyle>) -> AnyView) {
        makeContent = content
    }

    public func content(style: Binding<SubtitleStyle>) -> AnyView {
        makeContent(style)
    }
}
#endif
