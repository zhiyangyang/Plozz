#if os(iOS)
import AppRuntime
import CoreModels
import CoreUI
import FeatureAuth
import SwiftUI

struct PlozziOSPlexPINView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: PlexHomeUsersModel
    let request: PlexHomeUsersModel.PlexPINRequest
    var sequenceStep: PINSequenceStep? = nil
    var dismissOnSuccess = true
    var onCancel: () -> Void = {}
    @State private var lastAvailability: PINEntryAvailability = .checking

    var body: some View {
        let pendingRequest = model.pendingPlexPINRequest
        ZStack {
            if pendingRequest == request, model.plexPINEntryAvailability == .unavailable {
                PlexAccountRecoveryView(
                    name: request.homeUserName,
                    message: model.plexPINError ?? PlexPINCopy.switchFailed,
                    signIn: model.plexReauthentication,
                    onSignIn: { model.beginPlexReauthentication() },
                    onRetry: { model.retryPlexPINRequirement() },
                    onCancel: {
                        onCancel()
                        model.cancelPlexPIN()
                    },
                    onCancelSignIn: { model.cancelPlexReauthentication() }
                )
            } else {
                PINEntryScaffold(
                    title: "Enter your Plex PIN",
                    name: Text(verbatim: request.homeUserName),
                    errorMessage: model.plexPINError,
                    isSubmitting: model.isSubmittingPlexPIN || pendingRequest != request,
                    availability: pendingRequest == request ? model.plexPINEntryAvailability : lastAvailability,
                    onRetry: {
                        guard model.pendingPlexPINRequest == request else { return }
                        model.retryPlexPINRequirement()
                    },
                    sequenceStep: sequenceStep,
                    onSubmit: { pin in
                        guard model.pendingPlexPINRequest == request,
                            model.plexPINEntryAvailability == .available
                        else { return }
                        model.submitPlexPIN(pin)
                    },
                    onCancel: {
                        guard model.pendingPlexPINRequest == request else { return }
                        onCancel()
                        model.cancelPlexPIN()
                        if dismissOnSuccess, model.pendingPlexPINRequest == nil { dismiss() }
                    }
                ) {
                    PINBadge {
                        if let url = request.homeUserAvatarURL.flatMap(URL.init(string:)) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case let .success(image):
                                    image.resizable().scaledToFill()
                                default:
                                    Image(systemName: "person.fill")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .id([request.id, request.accountID, request.homeUserID])
            }
        }
        .interactiveDismissDisabled(pendingRequest != nil)
        .onChange(of: model.plexPINEntryAvailability, initial: true) { _, availability in
            if model.pendingPlexPINRequest == request { lastAvailability = availability }
        }
        .onChange(of: pendingRequest?.id) { _, requestID in
            if requestID == nil, dismissOnSuccess {
                dismiss()
            }
        }
    }
}
#endif
