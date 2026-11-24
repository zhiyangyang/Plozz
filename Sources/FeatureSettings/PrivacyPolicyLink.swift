#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct PrivacyPolicyLink: View {

    public init() {}

    public var body: some View {
        Group {
            Link(destination: AppLinks.privacyPolicy) {
                policyLabel
            }
        }
        .accessibilityIdentifier("privacy-policy-link")
    }

    private var policyLabel: some View {
        Label("Privacy Policy", systemImage: "hand.raised")
    }
}

#endif
