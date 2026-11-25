import CoreModels

public enum DefaultAccountStoreFactory {
    public static func make() throws -> AccountStore {
        #if canImport(Security)
        let secureStore = KeychainStore()
        let localStateStore = try DurableLocalStateStoreFactory.userIndependent()
        let store = AccountStore(
            secureStore: secureStore,
            mediaCredentialVault: MediaCredentialVault(secureStore: secureStore),
            credentialJournal: try CredentialMutationJournal(store: localStateStore)
        )
        return store
        #else
        return AccountStore(secureStore: InMemorySecureStore())
        #endif
    }

    public static func makeCredentialOnlyFallback() -> AccountStore {
        #if canImport(Security)
        let store = AccountStore(secureStore: KeychainStore())
        return store
        #else
        AccountStore(secureStore: InMemorySecureStore())
        #endif
    }


}
