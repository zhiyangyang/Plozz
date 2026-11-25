import CoreModels
import CryptoKit
import Foundation

/// Immutable imported-playlist bytes handed from the importer to the cache.
public struct LiveTVImportedPlaylistTransfer: Sendable {
    public let chunks: [Data]
    public let baseURL: URL?
    public let digest: Data

    public init(chunks: [Data], baseURL: URL?) throws {
        guard !chunks.isEmpty, chunks.count <= 8_192,
              chunks.allSatisfy({ !$0.isEmpty && $0.count <= LiveTVImportedPlaylistArchive.chunkBytes }),
              chunks.reduce(0, { $0 + $1.count }) <= LiveTVPlaylistParser.maximumBytes,
              baseURL.map(LiveTVPlaylistSource.isSupportedURL) ?? true else {
            throw LiveTVImportedPlaylistTransferError.invalidRecord
        }
        self.chunks = chunks
        self.baseURL = baseURL
        var hash = SHA256()
        for chunk in chunks { hash.update(data: chunk) }
        digest = Data(hash.finalize())
    }

    public var byteCount: Int { chunks.reduce(0) { $0 + $1.count } }
}

enum LiveTVImportedPlaylistTransferError: Error {
    case invalidRecord
}
