# CoreNetworking

The shared HTTP transport and logging primitives. Lives between `CoreModels`
and every provider/feature that talks to a remote server.

## Responsibility

- `HTTPClient` protocol + `URLSessionHTTPClient` default conformer:
  - serializes an `Endpoint` against a `baseURL`,
  - returns `(Data, HTTPURLResponse)` or throws `AppError`,
  - exposes a typed `decode(_:from:baseURL:)` convenience.
- Ordinary and foreground HTTP clients reuse separate process-wide session pools.
  Discovery keeps per-client ephemeral sessions, including isolated cookie stores.
  Overlapping bodyless GETs share a transfer only when URL, effective request
  headers, session identity and redirect policy match **and the endpoint opts in**.
  `allowsRequestCoalescing` defaults to false. Enable it at an audited read
  definition, never for every GET in a provider or transport wrapper. Unreviewed
  integrations remain independent; missing an opt-in costs a duplicate read,
  not a suppressed action. This policy is independent of address retry.
  Mutations, requests that disable address retry, and requests requiring their
  own delivery evidence are never shared. This includes Plex write/session GETs
  and Last.fm/Simkl challenge creation and consumption. Each caller retains its
  own error mapping and diagnostics.
  Reads used to authorize writes also need their own transfer: Jellyfin/Emby
  item detail and Plex metadata stay independent so stale-reset checks cannot
  join a response captured before newer playback. A bodyless GET is not enough
  to establish sharing safety, even when completed responses are never cached.
  `SharedAsyncRequests` provides the same independent-reader cancellation used
  by Jellyfin discovery: the last cancelled reader retires the transfer, late
  completions cannot overwrite replacements, and finished values are not cached.
- `Endpoint`: a transport-agnostic request description (method, path, query,
  headers, body) — providers build these, not raw `URLRequest`s.
- `HTTPResponseDiagnostics`: opt-in task-local decode and paging evidence for library
  failures. It preserves the existing thrown `AppError` and fallback contracts,
  discards evidence when the enclosing operation succeeds, and retains at most
  four responses and four paging failures per failed operation. Paging records
  contain only closed-vocabulary stages/reasons and numeric offsets/counts.
  Only status, byte count, payload shape,
  failure kind, expected value type and allowlisted coding-path fields survive.
  Providers label known routes with closed-vocabulary values; the transport
  never copies URLs, query parameters, raw keys, payloads or decoder descriptions
  into the report. No additional requests or successful-response parsing is added.
- `PlaybackPreparationDiagnostics` captures failed version preparation into the
  existing recent-activity log (`format=plozz-preparation-1`). Each attempt records
  its provider/operation, up to four request timings with configured timeout
  budgets, status, byte count, response-format category and numeric URL error,
  plus bounded decode and inventory-validation evidence. Address-discovery probes
  are distinguished from item-detail and source-inventory requests. Successful attempts
  discard their evidence; cancellation is not reported as a failure. There are
  no additional requests, retries, timeout changes or raw response retention.
  The record contains no server address, credentials, item/account ID or title.
  Users can reproduce once and use **Help & Diagnostics → Send Recent Activity
  to Developer** with their existing crash-reporting consent. This is an explicit
  user-submitted attachment, not a new automatic Sentry event or upload permission.
  Failures also retain up to 32 typed records in memory for 48 hours, so the
  privacy-filtered sender keeps request/decode/validation evidence without
  parsing the free-form log. Attempt identifiers become fresh report-local aliases.
- `ServerURLNormalizer`: turns user-typed addresses (with/without scheme,
  trailing slash, port) into a well-formed `URL` for both Jellyfin and Plex.
  Manual media-server discovery uses its separate candidate builder; legacy
  normalization of persisted/service URLs is unchanged. Discovery opts into
  typed TLS trust failures so an invalid certificate cannot select HTTP instead.
  Generic TLS negotiation failures remain transport errors: probing an HTTP-only
  port with HTTPS does not imply a rejected certificate. Manual Jellyfin/Emby
  discovery handles those and ordinary connectivity errors before trying its
  remaining credential-free candidates; explicit HTTPS never tries HTTP.
- `ProviderIconLoader`: best-effort, origin-only `/favicon.ico` requests for
  provider marks. It strips user information, paths, query strings and fragments,
  uses no credential/cookie storage, rejects redirects and authentication,
  and bounds response bytes/time with a memory-only HTTP cache.
- `OfflineNetworkSession`: app-owned HTTP sessions share the explicit device
  offline policy. Foreground sessions reject new HTTP(S) work while it is
  enabled; mode transitions cancel existing requests. Background download
  sessions are paused by their download owner rather than a URL protocol.
  This is not an internet-reachability heuristic: normal mode still permits
  saved LAN routes when the public internet is unavailable.
- `SubtitleFileLoader`: bounded, uncached text-subtitle delivery with redirect,
  byte-limit, cancellation, and network-policy safeguards. Ordinary sidecars use
  a 30-second request / 60-second resource budget. Embedded-track extraction opts
  into a separate 120-second request/resource budget for a server's initial scan;
  it does not add automatic retries or extend ordinary sidecar requests.
- `PlozzLog` (and the `PlozzLogger` category facade): the **single** logging
  entry point. Backed by `OSLog` on Apple platforms, no-op on non-Apple
  hosts. Must never log tokens, Quick Connect secrets, or full
  `Authorization` headers.

## Invariants

- **Approved address routing is bounded and demand-driven.**
  `ServerAddressResolver` shares concurrent credential-free probe sweeps and gives
  local routes a 300 ms head start. Providers use the short discovery timeout;
  successful choices are reused for 30 seconds, then reconsidered on demand.
  Failed connections invalidate the choice immediately. No network monitoring or
  background polling is added. Retry sweeps exclude the failed address even if
  another caller is resolving concurrently.
  Route edits update the existing resolver and fence superseded probe results.
  Ordinary successful traffic confirms reachability without extending the
  selection's lifetime indefinitely; returning to LAN remains discoverable.
  `ServerAddressHTTPClient` blocks cross-origin redirects and retries a failed
  GET once on another approved route, never an uncertain mutation. Probe-capable
  GETs opt out with `Endpoint.allowsAutomaticAddressRetry = false`: a timeout
  cannot establish that the first server operation stopped. Authentication
  failures are not connection failures. A preflight resolution failure preserves
  proof that a one-time exchange was not transmitted.
  `AlternateAddressHTTPIntegrationTests` uses loopback TCP listeners and the
  production URLSession transport for outages, redirects, cancellation,
  transmitted mutations, proxy paths, and retained-client address edits across
  all four managed providers. These controlled protocol fixtures are not live
  upstream-server interoperability tests.
- **Secret-safe by default.** `Authorization`, Quick Connect codes, Plex
  tokens, etc. must not reach `PlozzLog` — pass redacted strings or omit.
- **Provider-agnostic.** No Jellyfin/Plex specifics here. Provider modules
  layer their own headers/DTOs on top.
- **Throws `AppError`, not transport errors.** Non-2xx responses map onto
  `AppError` so feature code only ever speaks one error currency.
- **Platform-portable.** Compiles on Linux for `swift test` — Foundation
  only, no UIKit/SwiftUI.

## Where to look first

- `HTTPClient.swift` — the transport seam every provider depends on.
- `Endpoint.swift` — request shape & query/body helpers.
- `PlozzLog.swift` — how to log without leaking secrets.
- `ServerURLNormalizer.swift` — how user-typed server addresses are accepted.

