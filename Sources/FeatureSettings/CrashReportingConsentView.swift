#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct CrashReportingConsentView: View {
    @Environment(\.themePalette) private var palette

    private let onChoice: (Bool) -> Void

    public init(onChoice: @escaping (Bool) -> Void) {
        self.onChoice = onChoice
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    SettingsPanel(contentPadding: cardPadding) {
                        CrashReportingConsentPrompt(onChoice: onChoice)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("diagnostics-consent-card")
                    .overlay(alignment: .topTrailing) {
                        DiagnosticsInfoButton()
                            .padding(12)
                    }
                    Spacer(minLength: 72)
                    CrashReportingConsentFooter()
                }
                .frame(maxWidth: contentWidth)
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollClipDisabled()
        }
        .background { AppBackground(palette: palette) }
        .tint(palette.accent)
        .accessibilityIdentifier("diagnostics-consent")
    }

    private var contentWidth: CGFloat {
        480
    }

    private var cardPadding: EdgeInsets {
        return .settingsPanelDefault
    }
}

private struct CrashReportingConsentPrompt: View {
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image("PlozzLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                OnboardingHeader(Text("Help improve Plozz?"))
                Text("Send diagnostics when something goes wrong to help improve reliability and performance.")
                    .font(.body)
            }
            .plozzForeground(.primary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            CrashReportingConsentChoices(onChoice: onChoice)
        }
    }
}

private struct CrashReportingConsentChoices: View {
    let onChoice: (Bool) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                shareButton
                declineButton
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 16) {
                shareButton
                declineButton
            }
        }
        .controlSize(.large)
    }

    private var shareButton: some View {
        Button { onChoice(true) } label: { Text(SettingsCopy.shareDiagnostics) }
            .fixedSize(horizontal: false, vertical: true)
            .plozzActionButton(role: .primary)
            .accessibilityIdentifier("diagnostics-consent-share")
    }

    private var declineButton: some View {
        Button("Don't Share") { onChoice(false) }
            .fixedSize(horizontal: false, vertical: true)
            .plozzActionButton(role: .secondary)
            .accessibilityIdentifier("diagnostics-consent-decline")
    }
}

private struct CrashReportingConsentFooter: View {
    @ScaledMetric(relativeTo: .body) private var iconSize = 20

    var body: some View {
        Group {
            Link(destination: AppLinks.repository) {
                repositoryLabel
            }
        }
        .plozzActionButton(role: .secondary)
        .controlSize(.small)
        #if os(iOS)
        .modifier(DiagnosticsControlSize())
        #endif
        .accessibilityIdentifier("diagnostics-consent-repository")
    }

    private var repositoryLabel: some View {
        Label {
            Text("GitHub repo")
                #if os(iOS)
                .padding(.trailing, 6)
                #endif
        } icon: {
            Image("GitHubMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
        }
        .modifier(DiagnosticsControlLabelSize())
    }
}

#endif
