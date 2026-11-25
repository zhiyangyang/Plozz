import Foundation

/// A local, user-shared report. Only closed-vocabulary facts are exported.
public enum PlaybackDiagnosticReport: Equatable, Sendable {
    public enum Stage: String, Codable, Sendable { case preparation, opening, playback }

    case library(LibraryLoadDiagnostic)
    case onDemand(
        error: StreamingQualityError, provider: ProviderKind, engine: PlaybackEngineKind?,
        stage: Stage, negotiatedCodec: DirectPlayVideoCodec? = nil,
        retryCodec: DirectPlayVideoCodec? = nil
    )

    public var message: LocalizedStringResource? {
        switch self {
        case .library: return nil
        case .onDemand(let error, _, _, _, _, _): return error.userMessage
        }
    }

    // l10n:content — stable, credential-free support protocol fields, not UI labels
    public var supportText: String {
        if case .library(let diagnostic) = self { return diagnostic.supportText }
        var fields = ["format=plozz-playback-1"]
        func field(_ key: String, _ value: String?) {
            if let value { fields.append("\(key)=\(value)") }
        }
        func number(_ key: String, _ value: Int?) { field(key, value.map(String.init)) }
        switch self {
        case .library:
            break
        case .onDemand(let error, let provider, let engine, let stage, let codec, let retryCodec):
            field("operation", "playback")
            field("content", "onDemand")
            field("provider", provider.rawValue)
            field("engine", engine?.rawValue)
            field("stage", stage.rawValue)
            field("failure", error.diagnosticCode)
            field("negotiated_codec", codec?.rawValue)
            field("retried_codec", retryCodec?.rawValue)
            if case .playback(let failure) = error {
                field("reason", failure.kind.rawValue)
                field("engine_failure", failure.engineFailure?.rawValue)
                field("provider_reason", failure.providerReason?.rawValue)
                field("domain", failure.domain?.rawValue)
                number("code", failure.code)
                number("http_status", failure.httpStatus)
                for (index, error) in failure.underlyingErrors.enumerated() {
                    field("underlying_error_\(index)", "\(error.domain.rawValue):\(error.code)")
                }
            }
        }
        return fields.joined(separator: "\n")
    }
}
