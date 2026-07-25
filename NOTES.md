# NOTES: the iOS Share Extension

Since v0.7.0 the Share Extension is created automatically during `pod install`.
This file records how that works and what it deliberately does not do.

For consumer-facing setup and configuration, see the iOS section of the
[README](./README.md).

## Why an extension is required at all

On iOS, the Share Sheet's app row is populated by LaunchServices from installed
bundles that declare `NSExtensionPointIdentifier = com.apple.share-services`.
There is no Info.plist key, entitlement, or API that registers a plain app
there. Without an extension an app can still receive:

- **"Open In..." / "Copy to <App>"** hand-offs, via `CFBundleDocumentTypes` and
  `LSSupportsOpeningDocumentsInPlace` - these land in `Documents/Inbox`.
- **Custom URL schemes** and Universal Links.

That is the ceiling for a plain app, which is why the target exists.

Note the platform asymmetry: on Android, an `<intent-filter>` for
`ACTION_SEND` in the manifest is enough, and the library ships one - no extra
target, nothing for the consumer to add.

## How the automation works

A `.podspec` is plain Ruby evaluated in-process by CocoaPods, and CocoaPods
already depends on Xcodeproj. So `NitroShareIntent.podspec` calls
`ios/NitroShareIntentSetup.rb`, which opens the consumer's `.xcodeproj` and
creates the target directly. Those edits survive the integration pass that
re-opens and saves the user project afterwards.

Routes that were tried and rejected:

- **A CocoaPods plugin hook.** `HooksManager#hooks_to_run` filters registered
  hooks by `whitelisted_plugins.key?(hook.plugin_name)`, and the installer
  passes the Podfile's `plugin` list. A plugin always costs a `Podfile` line.
- **`script_phase` / `scriptPhases`.** These run at build time, which is too
  late: the target has to exist before the build starts to be compiled and
  embedded.

What the setup script does, idempotently, on every `pod install`:

1. Reads `nitroShareIntent.ios` from the app's `package.json`, and bails out
   entirely if `enabled` is `false`.
2. Creates the `:app_extension` target if it doesn't exist.
3. Generates `Info.plist` (`NSExtension` keys, activation rules, the App Group
   id, the host's URL scheme) and an `.entitlements` file.
4. Adds the pod's `ShareExtension/NitroShareViewController.swift` as the
   target's only source, *by reference* - upgrading the package upgrades the
   extension, with nothing to regenerate.
5. Adds the App Group to the host app's entitlements and writes
   `NitroShareIntentAppGroup` into its Info.plist, which is how
   `NitroShareIntent.swift` finds the container at runtime.
6. Creates the host's `Embed Foundation Extensions` copy-files phase and adds
   the `.appex` to it.

Failures are caught and reported as a warning: a problem here must never take
down a consumer's `pod install`, since the app itself still builds and works
without the extension.

## The hand-off

An extension runs in its own sandbox and **cannot** write into the host app's
`Documents/Inbox`, so everything goes through the App Group container:

```
<appGroup>/NitroShareIntent/<uuid>/
    <copied files...>
    payload.json      <- written LAST
```

`payload.json` is written after the files and acts as the completion marker, so
a drop that is still being filled is never consumed. The host scans for drops in
`startInboxMonitoring()` and on `didBecomeActive`, and deletes each drop after
reading it - including ones it fails to parse, which would otherwise be retried
on every activation for the life of the install.

## What is deliberately not automated

- **Provisioning.** The App Groups capability has to exist on both App IDs.
  Automatic signing usually creates it on the first build; manual signing and CI
  may need it added in the developer portal. A script cannot generate
  provisioning profiles.
- **Foregrounding the app after a share.** `openHostApp` reaches `openURL:`
  through the responder chain, because extensions have no `UIApplication` of
  their own. It is what comparable libraries do and it is on by default, but it
  is a grey area for App Store review - hence the config flag. With it off, the
  share is still collected the next time the app becomes active.

## Gotchas found while building this

- The extension target needs its own `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION`. They only live on the host target, so
  `$(MARKETING_VERSION)` expands to empty, the version keys are dropped from the
  built Info.plist, and installing fails with `Invalid placeholder attributes`.
- Building with `CODE_SIGNING_ALLOWED=NO` skips entitlements entirely, so the
  App Group container is never created and the hand-off silently does nothing.
  Worth knowing when scripting builds.
- The podspec is evaluated more than once per `pod install`, so the setup must
  be idempotent.
