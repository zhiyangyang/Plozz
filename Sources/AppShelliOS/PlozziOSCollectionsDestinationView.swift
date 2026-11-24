#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI

/// The personal build's top-level Collections destination.
///
/// There is deliberately no library picker: the grid aggregates the collection
/// catalogues of every enabled library that can answer one. Tapping a collection
/// pushes its members through the existing `CollectionBrowseRoute`.
struct PlozziOSCollectionsDestinationView: View {
    @Environment(PlozziOSAppModel.self) private var appModel
    let onShowSettings: () -> Void

    init(onShowSettings: @escaping () -> Void) {
        self.onShowSettings = onShowSettings
    }

    private enum Catalog {
        static let containerID = "plozz.allCollections"
        static let sortKeySuffix = "allCollections"
    }

    private var provider: (any MediaProvider)? {
        resolveAllCollectionsBrowse(
            libraries: appModel.visibleNavigationLibraries,
            in: appModel.accountsProviders.homeAccounts,
            identitySources: appModel.identityIndex.identitySourcesProvider,
            identityRevision: appModel.identityIndex.identityRevisionProvider
        )
    }

    var body: some View {
        Group {
            if let provider {
                PlozziOSLibraryGridView(
                    viewModel: LibraryBrowseViewModel(
                        provider: provider,
                        containerID: Catalog.containerID,
                        containerKind: .collection,
                        sortKeySuffix: Catalog.sortKeySuffix,
                        sourceAccountID: nil,
                        browseScope: .collectionsCatalog,
                        settingsNamespace: appModel.profiles.activeNamespace,
                        presentation: appModel.settings.libraryPresentation
                    ),
                    title: String(localized: "Collections"),  // l10n:content — page title
                    provider: provider,
                    settings: appModel.settings,
                    scanStatus: appModel.shareScanStatus,
                    isCombinedLibrary: true
                )
                .id(allLibrariesSourceSignature(appModel.visibleNavigationLibraries))
            } else {
                PlozzStateView(
                    icon: "rectangle.stack",
                    title: "No collections in this library.",
                    message: AllLibrariesBrowse.emptyMessage
                )
            }
        }
        .navigationTitle(PlozzCustomization.isCustomBuild ? Text(verbatim: "") : Text("Collections"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            PlozziOSSettingsToolbarItem(action: onShowSettings)
        }
    }
}
#endif
