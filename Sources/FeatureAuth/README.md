# FeatureAuth

Sign-in, credential recovery, and profile authorization for the iPad app.

## Responsibility

- Server sign-in for Emby, Jellyfin, Plex, and Silo, including server-address
  normalization, Plex Home user selection, Plex PIN entry, and Silo pairing.
- Credential storage in Keychain through `CoreSecureStore`; credentials are
  never written to `UserDefaults`, logs, fixtures, or screenshots.
- Account session state, credential revisions, and the active profile gate.
- Recovery flows for rejected sign-ins: sign in again, replace a password or
  token, switch Plex Home user, or remove the account.
- Automatic sign-in preference and its per-device state.
- Offline presentation of saved accounts when the network is unavailable.

## Invariants

- A stored account is usable only while its credential revision and active
  profile authorization still match. Replacing a profile or account invalidates
  pending work from the old identity.
- Keychain writes are the commit point. A failed or cancelled Keychain write
  leaves the previous account intact; never report success before it lands.
- Cancellation is not success. A cancelled sign-in or recovery leaves the
  existing state and surfaces no empty account.
- Plex Home user changes and profile switches must re-check authorization before
  saving or using credentials.
- Silo pairing requires approval on the server. A pending or denied pairing is
  an explicit state, not a generic failure.
- Sign-in copy describes the actual provider action. Do not claim a capability
  the provider does not support (for example, server conversion or music).
- Error messages use the typed `AppError`/provider error path. Do not include
  raw response bodies, tokens, or full server URLs.
- Tests use in-memory secure stores or ad-hoc simulator signing with a working
  Keychain; an unsigned host cannot prove credential persistence.

## Automatic Sign-In

Automatic sign-in keeps the last authorized account on this device when the
preference is enabled. It re-validates the credential before use and falls back
to the sign-in screen with an actionable error when the server rejects it.
Disabling the preference removes only the automatic path, not saved accounts.

## Where to look first

- `SignInView.swift`, `SiloSignInView.swift`, `PlexPINView.swift` — provider flows.
- `PlexHomeUserChooser.swift` — Plex Home user selection.
- `AccountStore` — account/session persistence and credential revisions.
- `AutomaticSignInSettings.swift` — automatic sign-in preference.
- `CoreSecureStore/Keychain.swift` — Keychain access and access groups.
- `AppRuntime`/`PlozziOSAppModel` — active profile and account resolution.
