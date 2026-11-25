#if os(iOS)
import CoreModels
import CoreUI
import SwiftUI

/// iOS/iPadOS first-run onboarding: the branded Plozz logo + "Free forever and
/// open source." tagline and a direct provider chooser.
@MainActor
struct PlozziOSOnboardingView: View {
    @Environment(\.themePalette) private var palette
    let appModel: PlozziOSAppModel
    @State private var addProvider: OnboardingProvider?
    @State private var showAddShare = false

    var body: some View {
        ZStack {
            AppBackground(palette: palette)
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: geo.size.height * (AppReleaseChannel.current.isBeta ? 0.02 : 0.08))
                        header
                        providerList
                        Spacer(minLength: 32)
                    }
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .plozzFullScreenCover(item: $addProvider) { wrapped in
            AddServerView(appModel: appModel, initialProvider: wrapped.kind)
        }
        .plozzFullScreenCover(isPresented: $showAddShare) {
            PlozziOSUnifiedAddShareView(appModel: appModel)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("PlozzLogo")
                .resizable().scaledToFit()
                .frame(width: 88, height: 88)
            Image("PlozzWordmark")
                .resizable().scaledToFit()
                .frame(height: 38)
                .foregroundStyle(palette.primaryText)
            Text("Free forever and open source.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var providerList: some View {
        ServerProviderChoices { provider in
            if provider == .mediaShare {
                showAddShare = true
            } else {
                addProvider = OnboardingProvider(kind: provider)
            }
        }
    }

}

/// Identifiable wrapper so a chosen provider can drive `.fullScreenCover(item:)`.
private struct OnboardingProvider: Identifiable {
    let kind: ProviderKind
    var id: String { kind.rawValue }
}
#endif
