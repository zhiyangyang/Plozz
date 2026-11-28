# Per-branch builds (`--branded`)

Install a branch's build on a real device **side-by-side with the canonical app**,
so you can test it without losing the app you actually use.

```sh
tools/deploy-ios.sh --ipad --branded   # iPad
```

That's the whole workflow. The scripts handle project regeneration, signing,
install, launch, and restoring the canonical project state on exit.

## What you get

The app is named and identified from the current git branch:

| branch | app name | bundle id |
| --- | --- | --- |
| `thatcube-localization` | Plozz localization | `com.thatcube.Plozz.localization` |
| `thatcube-new-player` | Plozz new-player | `com.thatcube.Plozz.new-player` |

The `thatcube-` prefix is stripped and the rest is slugified (lowercased,
non-alphanumerics to `-`, capped at 24 characters).

## What a branded build deliberately gives up

A per-branch build uses a **brand-new App ID**, and a new App ID cannot
auto-provision the canonical app's special capabilities. The branded build signs
against `App/PlozziOS/PlozziOS.branded.entitlements`, which is empty.

| Capability | Effect on a branded build |
| --- | --- |
| Push notifications | Unavailable; the canonical app keeps them. |
| Associated Domains | `applinks:plozz.app` still routes to the canonical app. |
| Shared containers | The branded app has its own container and keychain access. |

**The practical consequence: a branded build starts with no servers, downloads,
or settings from your canonical app, so you will sign in again.** That is
intended isolation — the branded app cannot disturb your real setup — not a bug.

## Troubleshooting

### `0xe8008012` — "This provisioning profile cannot be installed on this device"

The profile doesn't include your device's UDID. `tools/deploy-ios.sh` now catches
this **before** installing and prints which UDID is missing, because the raw
error names neither the device nor the profile.

Usual cause is a stale cached profile. In order:

1. Connect and unlock the device, then re-run. The script builds against the
   concrete target device, which is normally enough to make Xcode refresh.
2. `rm -rf ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles`
3. Confirm the device is registered on the developer portal.

Root cause, for the curious: with a *generic* destination (`generic/platform=iOS`)
xcodebuild has no target device to provision for, so `-allowProvisioningUpdates`
could hand back a wildcard profile containing the wrong device set. For the
canonical app id an all-devices profile already existed, so this never showed up;
a fresh per-branch App ID exposed it immediately.

### It builds but doesn't install

`--build-only` skips installing. Both device deployment wrappers use
`install-verified.sh`: up to three 180-second install attempts, bounded version
queries, and short backoff. A stale availability probe never gates installation.
There is no shorter outer timeout truncating the retry budget.

The installer preserves a signed-app check, all command logs, structured replies,
and a receipt under `.build/device-installs/`. It verifies after an error before
retrying: a newly observed target build confirms a completed install, but an
unchanged build number does **not** prove a `--force` replacement. A clean install
completion remains success if a follow-up connection or optional launch fails.
Package/signature rejection remains a failure, not device unavailability.
Recovery never resets shared device services, changes pairing, or deletes caches;
cancellation terminates only the installer’s current owned command.

`PLOZZ_INSTALL_TIMEOUT` (1–600 seconds) and `PLOZZ_INSTALL_ATTEMPTS` (1–5) override
the defaults. `PLOZZ_DEPLOY_INSTALL_DEADLINE`, if explicitly set, is an overall
deadline owned by the installer, not a second independently timed wrapper.

## Cleaning up

Delete the branded app from the device like any other app. Nothing else to undo —
the scripts restore the canonical project and `Info.plist`s on exit (including
after a failure), so `git status` stays clean.
