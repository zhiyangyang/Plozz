import CryptoKit
import Foundation

/// A salted verifier for the Plex Home-user PIN, used only to restore a cached
/// offline sign-in without contacting Plex. The PIN itself is never stored.
struct PlexPINVerifier: Codable, Hashable, Sendable {
    var salt: String
    var verifier: String
    var iterations: Int

    static let pinLength = 4

    static func isValidPIN(_ pin: String) -> Bool {
        pin.count == pinLength && pin.allSatisfy(\.isASCII) && pin.allSatisfy(\.isNumber)
    }

    static func make(pin: String, iterations: Int = 120_000) -> PlexPINVerifier? {
        guard isValidPIN(pin) else { return nil }
        var saltBytes = Data(count: 16)
        for i in saltBytes.indices { saltBytes[i] = UInt8.random(in: .min ... .max) }
        let salt = saltBytes.base64EncodedString()
        return PlexPINVerifier(
            salt: salt,
            verifier: derive(pin: pin, salt: salt, iterations: iterations),
            iterations: iterations
        )
    }

    func matches(pin: String) -> Bool {
        guard Self.isValidPIN(pin) else { return false }
        let candidate = Self.derive(pin: pin, salt: salt, iterations: iterations)
        return Self.constantTimeEquals(candidate, verifier)
    }

    func matchesOffMainActor(pin: String) async -> Bool {
        let verification = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return false }
            return matches(pin: pin) && !Task.isCancelled
        }
        return await withTaskCancellationHandler {
            await verification.value
        } onCancel: {
            verification.cancel()
        } && !Task.isCancelled
    }

    private static func derive(pin: String, salt: String, iterations: Int) -> String {
        var digest = SHA256.hash(data: Data((salt + pin).utf8))
        for _ in 1 ..< max(1, iterations) {
            digest = SHA256.hash(data: Data(digest))
        }
        return Data(digest).base64EncodedString()
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
