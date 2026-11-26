import CoreModels

/// The local metadata workers for one account/store/session generation.
/// Grouped so the coordinator receives both from a single factory call and owns
/// only their lifecycle, not the concrete enricher construction policy.
struct ShareMetadataPipeline: Sendable {
    let local: ShareLocalMetadataEnricher
    let artwork: ShareLocalArtworkProbeWorker
}

/// Constructs a ``ShareMetadataPipeline`` for a share. Injected into the coordinator
/// so worker construction lives behind a seam that tests can replace with a fake
/// pipeline (no concrete classes required).
protocol ShareMetadataPipelineFactory: Sendable {
    func makePipeline(
        store: ShareCatalogStore,
        accountKey: String,
        credentialRevision: CredentialRevision,
        reporter: ShareScanReporter,
        sessionFactory: @escaping ShareTransportSessionFactory
    ) -> ShareMetadataPipeline
}

/// The default factory: local NFO/sidecar enricher plus local artwork probing.
struct DefaultShareMetadataPipelineFactory: ShareMetadataPipelineFactory {
    func makePipeline(
        store: ShareCatalogStore,
        accountKey: String,
        credentialRevision: CredentialRevision,
        reporter: ShareScanReporter,
        sessionFactory: @escaping ShareTransportSessionFactory
    ) -> ShareMetadataPipeline {
        let browser = ShareTransportBrowser(role: .metadata, sessionFactory: sessionFactory)
        return ShareMetadataPipeline(
            local: ShareLocalMetadataEnricher(store: store, browser: browser),
            artwork: ShareLocalArtworkProbeWorker(
                store: store,
                browser: browser,
                accountID: accountKey,
                credentialRevision: credentialRevision
            )
        )
    }
}
