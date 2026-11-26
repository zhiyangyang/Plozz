#if os(iOS)
import CoreUI
import SwiftUI

extension EnvironmentValues {
    @Entry var hasVisibleSettingsNavigationEntry = false

    var plozziOSUsesVerticalToolbar: Bool {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return toolbarVerticalEdge != nil
        }
        #endif
        return false
    }
}

struct PlozziOSSettingsToolbarItem<LeadingActions: View>: ToolbarContent {
    @Environment(\.plozziOSUsesVerticalToolbar) private var usesVerticalToolbar
    let horizontalPlacement: ToolbarItemPlacement
    let leadingActions: LeadingActions
    let action: () -> Void

    init(
        horizontalPlacement: ToolbarItemPlacement = .topBarTrailing,
        @ViewBuilder leadingActions: () -> LeadingActions = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.horizontalPlacement = horizontalPlacement
        self.leadingActions = leadingActions()
        self.action = action
    }

    var body: some ToolbarContent {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            item.axisBehavior(usesVerticalToolbar ? .verticalPreferred : .automatic)
        } else {
            item
        }
        #else
        item
        #endif
    }

    @ToolbarContentBuilder
    private var item: some ToolbarContent {
        if #available(iOS 26.0, *) {
            settingsItem.sharedBackgroundVisibility(.hidden)
        } else {
            settingsItem
        }
    }

    private var settingsItem: some ToolbarContent {
        ToolbarItem(placement: placement) {
            HStack(spacing: PlozziOSPageHeaderLayout.actionSpacing) {
                leadingActions
                PlozziOSSettingsAvatarButton(
                    diameter: usesVerticalToolbar ? 48 : PlozziOSPageHeaderLayout.actionDiameter,
                    action: action
                )
            }
            .fixedSize()
        }
    }

    private var placement: ToolbarItemPlacement {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *), usesVerticalToolbar {
            return .topBarPinnedTrailing
        }
        #endif
        return horizontalPlacement
    }
}

/// The settings entry point shown across the iOS app.
struct PlozziOSSettingsAvatarButton: View {
    var diameter: CGFloat = PlozziOSPageHeaderLayout.actionDiameter
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Settings", systemImage: "gearshape")
        }
        .plozziOSPageAction(diameter: diameter)
        .accessibilityLabel(Text("Settings"))
    }
}
#endif
