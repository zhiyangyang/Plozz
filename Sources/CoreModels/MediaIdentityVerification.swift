import Foundation

/// Live identity proof for a title resolved from more than one server.
public enum MediaIdentityVerification {
    public static func matches(_ expected: MediaItem, _ record: MediaItem) -> Bool {
        guard expected.kind == record.kind else { return false }
        let expectedIDs = strongIDs(expected)
        let actualIDs = strongIDs(record)
        let shared = Set(expectedIDs.keys).intersection(actualIDs.keys)
        // Index membership alone cannot bless a sparse or title-only record.
        return !shared.isEmpty && shared.allSatisfy { expectedIDs[$0] == actualIDs[$0] }
    }

    public static func hasConflictingStrongIdentity(_ first: MediaItem, _ second: MediaItem) -> Bool {
        let firstIDs = strongIDs(first)
        let secondIDs = strongIDs(second)
        return firstIDs.contains { key, value in
            secondIDs[key].map { $0 != value } ?? false
        }
    }

    private static func strongIDs(_ item: MediaItem) -> [String: String] {
        Dictionary(MediaItemIdentity.identities(for: item).compactMap { identity in
            guard case let .external(source, value) = identity else { return nil }
            return (source, value)
        }, uniquingKeysWith: { first, _ in first })
    }
}
