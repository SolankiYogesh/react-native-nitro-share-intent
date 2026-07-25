# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2026-07-26

### Added

- **iOS: the Share Extension is now created for you during `pod install`.** The
  app finally appears in the system Share Sheet with no Xcode target to add, no
  native code to write, and no `Podfile` changes
  (`ios/NitroShareIntentSetup.rb`). The generated target is embedded in the host
  app, and its principal class ships inside the pod
  (`ios/ShareExtension/NitroShareViewController.swift`), so the target contains
  no app-authored source at all.
- **iOS: App Group hand-off.** A Share Extension runs in its own sandbox and
  cannot write into the host app's `Documents/Inbox`, so shared items are
  written into the App Group container and collected by the host on launch and
  on `didBecomeActive`. The App Group is added to both targets automatically.
- **Configuration through the app's `package.json`** (no `ios/` edits), all
  optional:

  ```json
  {
    "nitroShareIntent": {
      "ios": {
        "enabled": true,
        "appGroup": "group.com.acme.app",
        "extensionName": "NitroShareExtension",
        "openHostApp": true,
        "activation": { "images": 10, "movies": 10, "files": 10, "text": true, "urls": 1 }
      }
    }
  }
  ```

  Set `enabled` to `false` to opt out of the generated target entirely.

### Fixed

- **iOS: the app crashed on every incoming share.** Any app declaring
  `LSSupportsOpeningDocumentsInPlace` (i.e. any app that accepts shares) was
  terminated at launch with
  `NSInternalInconsistencyException: Application has LSSupportsOpeningDocumentsInPlace key, but doesn't implement application:openURL:options:`.

  The runtime hook installed that method from a
  `UIApplicationDidFinishLaunchingNotification` observer registered with
  `queue: [NSOperationQueue mainQueue]`, which *enqueues* the block - it ran a
  runloop turn after UIKit had already inspected the delegate and aborted. The
  hook now swizzles `-[UIApplication setDelegate:]` and installs the method
  **before** calling through to the original implementation: `setDelegate:`
  caches which optional delegate methods exist in an internal bitmask, and UIKit
  consults that cache rather than `respondsToSelector:`, so installing after the
  original call is still too late.
- **iOS: data race on the listener maps.** `intentListeners`, `errorListeners`
  and `pendingIntent` were mutated from the JS thread while being read from the
  main thread and a background queue. Concurrent access to a Swift `Dictionary`
  is a crash, not merely a lost update. All access is now serialised, with
  callbacks invoked outside the lock so a listener that calls `removeListener`
  cannot deadlock.
- **iOS: `getInitialShare()` scanned the Inbox on the JS thread**, racing with
  URLs arriving on the main thread through the AppDelegate hook. The scan is now
  confined to the main thread with the rest of the monitoring state.
- **Android: a cold-start share could be dropped permanently.** When
  `getInitialShare()` ran before the activity was attached to the React context,
  it cached "nothing shared" forever, so the launch intent was never delivered.
  The negative result is no longer cached when there is no activity to inspect.
- **Android: the module did not compile.** An unused
  `com.margelo.nitro.core.NullType` import failed to resolve.

### Changed

- Example app: `react-native-nitro-modules` moved to `^0.31.3`. It was pinned to
  `^0.29.8`, so yarn nested an incompatible copy under `example/node_modules`
  and the Android build failed on a missing `NitroModules/JNICallable.hpp`.
- Example app: the `Podfile`'s Xcode 26 `fmt`/`consteval` patch is applied in
  Ruby instead of through `sed`. The shell escaping did not survive, so the
  patch silently no-op'd and only surfaced on a device build, where
  `hermes-engine` and `fmt` compile from source as C++20.

### Known limitations

- **Provisioning cannot be automated.** The App Groups capability must exist on
  both App IDs. Automatic signing usually creates it on the first build;
  manual signing and CI may need it added in the developer portal.
- **`openHostApp` reaches `openURL:` through the responder chain**, which is how
  comparable libraries foreground the app from an extension, but it is a grey
  area for App Store review. Set `"openHostApp": false` to skip it - the share is
  still collected the next time the app becomes active.

## [0.6.0] - 2026-07-21

### 🚨 Breaking / migration notes

Nothing breaks at compile time, but setup requirements changed:

- **iOS: no `AppDelegate.swift` code needed anymore.** The previously required
  snippets - posting `AppDidFinishLaunching` from
  `didFinishLaunchingWithOptions` and posting `ShareIntentReceived` from
  `application(_:open:options:)` - are obsolete. Delete them, or leave them;
  both notifications are still observed for backwards compatibility and
  duplicate deliveries of the same URL are de-duplicated (3-second window).
- **Android: no `MainActivity` code needed anymore.** The documented
  `onNewIntent` override is unnecessary: React Native's `ReactActivity` already
  forwards `onNewIntent` through the `ActivityEventListener` mechanism the
  module registers against. If you override `onNewIntent` for other reasons,
  keep calling `super.onNewIntent(intent)`. Manifest configuration (intent
  filters, `launchMode="singleTask"`) is unchanged and still required.
- **iOS behavior change:** re-sharing the *same* non-file URL later in the same
  session now fires a new event each time. Previously it was delivered once and
  then silently swallowed for the rest of the session.

### Added

- **iOS: automatic AppDelegate integration**
  (`ios/NitroShareIntentAppDelegateHook.m`). At launch the library installs an
  `application(_:open:options:)` handler on the app delegate at runtime - only
  when the app doesn't implement that method itself (own implementations, deep
  linking setups, and Expo's delegate wrapper are left untouched). URLs opened
  before the JS module initializes (cold-start scheme opens, including the
  launch-options URL) are buffered and replayed once the module is ready.
- **iOS: `RCTOpenURLNotification` support.** Apps that already forward URL
  opens to `RCTLinkingManager` (deep linking) are picked up automatically with
  no extra code.
- **iOS: `NitroShareIntentAppDelegateProxyEnabled` Info.plist key** (Boolean,
  default `YES`) to opt out of the runtime hook and keep manual wiring.
- `CHANGELOG.md` (this file).

### Changed

- **iOS:** all URL sources (runtime hook, `RCTOpenURLNotification`, legacy
  `ShareIntentReceived` notification) funnel through one entry point with
  cross-source de-duplication, so mixed setups can't double-fire events.
- **iOS:** inbox monitoring no longer depends on the `AppDidFinishLaunching`
  notification - it is triggered by `getInitialShare()` and the app's
  `didBecomeActive` lifecycle event.
- Example app updated to run with zero custom native code on both platforms.
- README setup sections rewritten accordingly.

## [0.5.0] and earlier

No changelog was kept before 0.6.0 - see the git history for details.
