#if canImport(SwiftUI)
import SwiftUI
import CoreModels

public struct WetrakrWatchlistLink: View {
    private let url: URL
    @State private var showsCode = false

    public init(url: URL) { self.url = url }

    public var body: some View {
        if RuntimeFeatureFlags.buildDefault.isEnabled(.wetrakr) {
            link
        }
    }

    private var link: some View {
        Link("View on WeTrakr", destination: url)
    }
}
#endif
