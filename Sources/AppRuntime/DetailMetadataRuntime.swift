import CoreModels
import CoreSecureStore
import MetadataKit

public extension DetailMetadataResolver {
    /// Read the same household settings and credential as the share pipeline on each open.
    static let household: DetailMetadataResolver = {
        DetailMetadataResolver(providerConfig: { MetadataProviderConfig.resolved() })
    }()
}
