import CoreUI
import SwiftUI

struct LiveTVPreviewIntroductionPresentation: ViewModifier {
    let isPresented: Bool
    let choose: (Bool) -> Void
    let onDismiss: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
    }
}
