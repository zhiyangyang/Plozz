import Foundation

/// Deterministic JSON encoding for durable local state comparisons.
public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Dates as a stable numeric interval (default) — deterministic across runs.
        return try? encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
