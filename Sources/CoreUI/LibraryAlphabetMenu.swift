#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// Shared entry point; platforms retain their own grid and scrolling machinery.
public struct LibraryAlphabetMenu: View {
    let entries: [LibraryLetterIndexEntry]
    let isLoading: Bool
    let isJumping: Bool
    let onSelect: (String, UUID?) -> Void
    let onDismiss: (UUID) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    public init(entries: [LibraryLetterIndexEntry], isLoading: Bool, isJumping: Bool,
                onSelect: @escaping (String, UUID?) -> Void, onDismiss: @escaping (UUID) -> Void,
                onCancel: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.entries = entries
        self.isLoading = isLoading
        self.isJumping = isJumping
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    public var body: some View {
        Menu {
            if isJumping {
                Button("Cancel jump", action: onCancel)
                Divider()
            }
            ForEach(entries, id: \.letter) { entry in
                Button(entry.letter) {
                    onSelect(entry.letter, nil)
                }
                .accessibilityLabel("Jump to \(entry.letter)")
            }
            if entries.isEmpty {
                Button("Retry alphabet index", action: onRetry)
            }
        } label: {
            Label("Jump to letter", systemImage: "textformat.abc")
        }
        .disabled(isLoading)
        .accessibilityIdentifier("library-alphabet-menu")
    }
}


/// Uses the root's existing watchlist/status toast, without adding another host
/// or focus target. A completed jump can only dismiss its own status generation.
public struct LibraryAlphabetFeedback: View {
    @Environment(\.transientStatusPresenter) private var presenter
    @State private var presentedGeneration: UInt64?
    let letter: String?
    let message: LocalizedStringResource?

    public init(letter: String?, message: LocalizedStringResource?) {
        self.letter = letter
        self.message = message
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: feedback, initial: true) { _, _ in update() }
            .onDisappear { dismissOwnedStatus() }
    }

    private var feedback: TransientStatusMessage? {
        if let message {
            return .init(icon: "exclamationmark.circle", text: message)
        }
        guard let letter else { return nil }
        return .init(icon: "magnifyingglass", text: "Jumping to \(letter)…", isProgress: true)
    }

    private func update() {
        dismissOwnedStatus()
        guard let feedback else { return }
        let generation = presenter?.present(
            icon: feedback.icon, text: feedback.text, isProgress: feedback.isProgress)
        if feedback.isProgress { presentedGeneration = generation }
    }

    private func dismissOwnedStatus() {
        if let presentedGeneration {
            presenter?.dismiss(expectedGeneration: presentedGeneration)
            self.presentedGeneration = nil
        }
    }
}
#endif
