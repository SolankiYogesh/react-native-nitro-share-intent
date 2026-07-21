# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
