import Foundation
import CoreModels
#if canImport(Security)
import Security
#endif

#if canImport(Security)
/// Device-local Keychain storage for one tracker's OAuth tokens.
///
/// Tokens are never written outside the Keychain or logged.
public final class TrackerTokenBox<Token: Codable & Sendable>: @unchecked Sendable {
    private let baseAccount: String
    private let store: any SecureStoring
    private let lock = NSLock()
    private var namespace: String?

    public convenience init(
        service: String = "com.plozz.app.tokens",
        account: String,
        namespace: String? = nil
    ) {
        self.init(
            store: KeychainStore(service: service, userIndependent: false,
                                 fallbackToPerUser: false),
            baseAccount: account,
            namespace: namespace
        )
    }

    init(store: any SecureStoring, baseAccount: String, namespace: String? = nil) {
        self.store = store
        self.baseAccount = baseAccount
        self.namespace = namespace
    }

    public func setNamespace(_ namespace: String?) {
        lock.lock()
        self.namespace = namespace
        lock.unlock()
    }

    private func currentAccount() -> String {
        lock.lock(); defer { lock.unlock() }
        if let namespace, !namespace.isEmpty {
            return "\(baseAccount).\(namespace)"
        }
        return baseAccount
    }

    public func load() -> Token? {
        store.string(for: currentAccount()).flatMap(decode)
    }

    public func save(_ token: Token) throws {
        let data = try JSONEncoder().encode(token)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw TrackerTokenBoxError.encoding
        }
        try store.setString(raw, for: currentAccount())
    }

    public func clear() throws {
        try store.removeValue(for: currentAccount())
    }

    private func decode(_ raw: String) -> Token? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }
}

public enum TrackerTokenBoxError: Error {
    case encoding
}
#endif
