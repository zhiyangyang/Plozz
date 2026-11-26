#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct ProfileNameLabel: View {
    private let profile: Profile

    public init(profile: Profile) {
        self.profile = profile
    }

    public var body: some View {
        Text(profile.name)
            .accessibilityLabel(profile.name)
    }
}
#endif
