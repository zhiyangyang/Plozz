import CoreUI
import CoreModels
import FeatureLiveTVCore
import SwiftUI

struct PrototypeBrowseSidebar: View {
    @Bindable var model: LiveTVPrototypeModel
    let configuration: LiveTVSourcesConfiguration
    @Binding var active: Bool
    @Binding var lastFocusedControl: Control?
    let focusRequest: Int
    var isSearching = false
    var categoryFocusRequest = 0
    var restoresCategoryFocus = false
    var isRevealing = false
    let search: () -> Void
    let enterGuide: () -> Void
    let selectSource: (String?) -> Void
    let addSource: () -> Void
    var selectCategory: ((String?) -> Void)?
    var multiviews: (() -> Void)?
    var manageChannels: (() -> Void)?
    @FocusState private var focused: Control?
    @State private var categoryFade = PrototypeScrollFade()
    @State private var completedCategoryFocusRequest = 0
    @State private var hasFocusedControl = false
    @ScaledMetric(relativeTo: .subheadline) private var fontSize = PrototypeLayout.guideFontSize
    @Environment(\.layoutDirection) private var layoutDirection

    enum Control: Hashable {
        case source
        case search
        case multiviews
        case manageChannels
        case category(String?)
    }

    private var isRestoringFocus: Bool {
        restoresCategoryFocus && categoryFocusRequest > completedCategoryFocusRequest
    }

    private var entryTarget: Control {
        switch lastFocusedControl {
        case .source:
            return .source
        case .search:
            return .search
        case .multiviews where multiviews != nil:
            return .multiviews
        case .manageChannels where manageChannels != nil:
            return .manageChannels
        case .category(let category) where category == nil || model.browsingCategories.contains(where: { $0.name == category }):
            return .category(category)
        default:
            return .category(model.category)
        }
    }

    private func isFocusDisabled(_ control: Control) -> Bool {
        isRestoringFocus && control != entryTarget
    }

    private var readyCategoryFocusRequest: Int? {
        return restoresCategoryFocus && !isRevealing ? categoryFocusRequest : nil
    }

    @ViewBuilder private func nativeFocusRequest(for control: Control) -> some View {
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.gap) {
            sidebarActions

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: PrototypeLayout.smallGap) {
                        ForEach([nil] + model.browsingCategories.map { Optional($0.name) }, id: \.self) { category in
                            Button {
                                if let selectCategory { selectCategory(category) }
                                else { model.category = category }
                            } label: {
                                HStack(spacing: PrototypeLayout.smallGap) {
                                    if let category { Text(category) } else { Text("All categories") }
                                    Spacer(minLength: 0)
                                    Text(model.categoryChannelCount(category), format: .number)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .opacity(model.category == category ? 1 : 0)
                                        .accessibilityHidden(true)
                                }
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                            .focused($focused, equals: .category(category))
                            .background { nativeFocusRequest(for: .category(category)) }
                            .prototypeFocusGate(isFocusDisabled(.category(category)))
                            .id(Control.category(category))
                            .accessibilityAddTraits(model.category == category ? .isSelected : [])
                            .accessibilityLabel(category.map { Text(verbatim: $0) } ?? Text("All categories"))
                            .accessibilityValue(Text("\(model.categoryChannelCount(category)) channels"))
                            .accessibilityIdentifier("live-tv-sidebar-category-\(category ?? "all")")
                        }
                    }
                    .padding(.vertical, PrototypeLayout.smallGap)
                }
                .scrollIndicators(.hidden)
                .verticalEdgeFadeMask(
                    fadeHeight: PrototypeLayout.verticalFade,
                    topStrength: categoryFade.leading,
                    bottomStrength: categoryFade.trailing
                )
                .onScrollGeometryChange(for: PrototypeScrollFade.self) { geometry in
                    PrototypeScrollFade(
                        before: geometry.contentOffset.y + geometry.contentInsets.top,
                        after: geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                    )
                } action: { _, fade in
                    categoryFade = fade
                }
                .accessibilityIdentifier("live-tv-category-list")
                .onChange(of: readyCategoryFocusRequest, initial: true) { _, request in
                    guard request != nil else { return }
                    let target = entryTarget
                    if case .category = target, !hasFocusedControl || target != lastFocusedControl {
                        proxy.scrollTo(target)
                    }
                    focused = target
                }
            }
        }
        .lineLimit(1)
        .onChange(of: focused) { _, target in
            guard let target else { return }
            hasFocusedControl = true
            if target == entryTarget {
                completedCategoryFocusRequest = categoryFocusRequest
            }
            lastFocusedControl = target
            active = true
        }
        .onChange(of: focusRequest, initial: true) { _, request in
            guard request > 0, active, !restoresCategoryFocus else { return }
            completedCategoryFocusRequest = categoryFocusRequest
            focused = .search
        }
    }

    @ViewBuilder private var sidebarActions: some View {
        if let multiviews {
            Button(action: multiviews) {
                Label("Multiviews", systemImage: "rectangle.split.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .focused($focused, equals: .multiviews)
            .background { nativeFocusRequest(for: .multiviews) }
            .prototypeFocusGate(isFocusDisabled(.multiviews))
            .accessibilityIdentifier("live-tv-multiview-favorites")
        }
        if let manageChannels {
            Button(action: manageChannels) {
                Label("Manage channels", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .focused($focused, equals: .manageChannels)
            .background { nativeFocusRequest(for: .manageChannels) }
            .prototypeFocusGate(isFocusDisabled(.manageChannels))
            .accessibilityIdentifier("live-tv-manage-channels")
        }
    }

}

extension View {
    /// Navigation can exclude a control without telling its native style that its action is unavailable.
    @ViewBuilder func prototypeFocusGate(_ blocked: Bool) -> some View {
        disabled(blocked)
    }
}
