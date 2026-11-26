#if os(iOS)
import CoreModels
import SwiftUI

struct PlozziOSServerIdentityPresenter: ViewModifier {
    let appModel: PlozziOSAppModel
    let isEnabled: Bool
    @State private var displayed: PlozziOSAppModel.ServerIdentityQuestion.ID?

    func body(content: Content) -> some View {
        let question = isEnabled ? appModel.presentableIdentityQuestion : nil
        return content.plozzSheet(item: Binding(
            get: { question },
            set: { value in
                guard value == nil, let question, displayed == question.id else { return }
                appModel.concludeIdentityPrompt(question)
            }
        )) { presented in
            PlozziOSServerIdentityPromptView(
                appModel: appModel, account: presented.account,
                onFinish: { appModel.concludeIdentityPrompt(presented) },
                onDecline: { appModel.concludeIdentityPrompt(presented, decline: true) }
            )
            .onAppear { displayed = presented.id }
        }
    }
}

struct PlozziOSServerIdentityPromptView: View {
    let appModel: PlozziOSAppModel
    let account: Account
    let onFinish: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            PlozziOSPlexHomeUserSettingsView(
                appModel: appModel, account: account, onDecline: onDecline
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onFinish)
                        .disabled(appModel.inlinePlexPINRequest != nil)
                }
            }
        }
    }
}
#endif
