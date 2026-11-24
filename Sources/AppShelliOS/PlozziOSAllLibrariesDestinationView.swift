#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI

struct PlozziOSAllLibrariesDestinationView: View {
    @Environment(\.locale) private var locale
    let appModel: PlozziOSAppModel

    private var title: String { // l10n:content - locale-scoped resource for the shared grid's String API
        if let name = appModel.settings.navigation.libraryLayout.customNames[NavigationLibraryLayout.allLibrariesKey] {
            return name
        }
        var resource = AllLibrariesBrowse.title
        resource.locale = locale
        return String(localized: resource) // l10n:content - recomputed from the observed locale, never cached
    }

    var body: some View {
        Group {
            if let provider = resolveAllLibrariesBrowse(
                libraries: appModel.visibleNavigationLibraries,
                in: appModel.accountsProviders.homeAccounts,
                identitySources: appModel.identityIndex.identitySourcesProvider,
                identityRevision: appModel.identityIndex.identityRevisionProvider
            ) {
                PlozziOSLibraryGridView(
                    viewModel: LibraryBrowseViewModel(
                        provider: provider,
                        containerID: AllLibrariesBrowse.containerID,
                        containerKind: .unknown,
                        sortKeySuffix: AllLibrariesBrowse.sortKeySuffix,
                        sourceAccountID: nil,
                        settingsNamespace: appModel.profiles.activeNamespace,
                        presentation: appModel.settings.libraryPresentation
                    ),
                    title: title,
                    provider: provider,
                    settings: appModel.settings,
                    scanStatus: appModel.shareScanStatus,
                    isCombinedLibrary: true
                )
            } else {
                PlozzStateView(
                    icon: "square.stack.3d.up.slash",
                    title: AllLibrariesBrowse.emptyTitle,
                    message: AllLibrariesBrowse.emptyMessage
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(PlozzCustomization.isCustomBuild ? .large : .inline)
    }
}
#endif
