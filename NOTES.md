# NOTES: Bundling a real iOS Share Extension

## Why this exists

`ios/NitroShareIntent.swift` already contains an "Inbox monitoring" mechanism
(`startInboxMonitoring`, `checkForPendingDocuments`, `cleanupInboxFile`) that polls
`Documents/Inbox` in the host app's sandbox. That directory is where iOS places files that
were handed to your app by **another app's Share Sheet action targeting a real iOS Share
Extension**, or via a `UIDocumentInteractionController` "Open In..." hand-off.

Right now, this package ships:

- The main app-side plumbing (`AppDelegate` notifications, `NitroShareIntent`'s
  Inbox-polling/timer logic) that *reacts* to files showing up.
- **No actual Share Extension target.** Without one, your app never appears as a
  destination in the system Share Sheet - the polling logic has nothing to poll for beyond
  "Open In..." / custom URL scheme hand-offs, which are already covered by the
  `AppDelegate` hooks documented in the README.

Adding a bundled Share Extension means creating a **second Xcode target** (an app
extension) inside the consumer's `.xcodeproj`/`.xcworkspace`. Xcode project files
(`project.pbxproj`) are a fragile, mostly-binary-adjacent plist format with fragile internal
UUID cross-references; scripting new target creation blind (without Xcode itself resolving
build phases, signing, and target membership) is highly likely to silently corrupt the
project file or produce a target Xcode can't open. That's why this wasn't attempted as part
of the automated fix pass - it's flagged here instead for a maintainer to do by hand in
Xcode's GUI.

## Manual steps for a maintainer/consumer to add a Share Extension

These steps describe adding a Share Extension to the **example app**
(`example/ios/NitroShareIntentExample.xcworkspace`), but the same steps apply to any
consumer app.

1. **Open the workspace in Xcode** (not just the `.xcodeproj` - CocoaPods/autolinking
   requires the `.xcworkspace`).

2. **File → New → Target… → Share Extension** (under the iOS tab). Give it a name, e.g.
   `ShareExtension`. Xcode will scaffold a new target with its own `Info.plist`,
   `ShareViewController.swift`, and an entry in the main app's `Embed Foundation Extensions`
   build phase.

3. **Configure an App Group** so the extension (which runs in its own sandboxed process,
   separate from the host app) can hand data to the main app:
   - Select the **main app target** → *Signing & Capabilities* → **+ Capability** → *App
     Groups* → add a group id, e.g. `group.com.yourcompany.yourapp.shared`.
   - Select the **new extension target** → *Signing & Capabilities* → **+ Capability** →
     *App Groups* → check the same group id.
   - Both targets need this same App Group id in their entitlements files.

4. **Declare what the extension accepts**, in the extension's `Info.plist`, under
   `NSExtension` → `NSExtensionAttributes` → `NSExtensionActivationRule`. For example, to
   accept images, videos, and plain text/URLs, use an `NSExtensionActivationRule` predicate
   (Xcode's default template ships a permissive example) or the dictionary form:
   ```xml
   <key>NSExtensionAttributes</key>
   <dict>
     <key>NSExtensionActivationRule</key>
     <dict>
       <key>NSExtensionActivationSupportsImageWithMaxCount</key><integer>10</integer>
       <key>NSExtensionActivationSupportsMovieWithMaxCount</key><integer>10</integer>
       <key>NSExtensionActivationSupportsText</key><true/>
       <key>NSExtensionActivationSupportsWebURLWithMaxCount</key><integer>1</integer>
     </dict>
   </dict>
   ```

5. **Implement `ShareViewController`** (replacing Xcode's template) to read the incoming
   `NSExtensionItem`/`NSItemProvider` attachments and write them somewhere the host app can
   read:
   - **Preferred for this package**: copy shared files into the host app's
     `Documents/Inbox` directory *via the shared App Group container* -
     `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` gives you a
     writable directory both the extension and host app can see. You'll need to either (a)
     write directly into a location the host app's sandbox can see (not always possible -
     the classic `Documents/Inbox` folder is normally populated by the OS itself for
     `UIDocumentPickerViewController`/`UIActivityViewController` "Copy to <App>" flows, not
     by an extension you write yourself), or (b) write to the App Group container and change
     `checkForPendingDocuments()` in `ios/NitroShareIntent.swift` to *also* scan the App
     Group container directory, not just `Documents/Inbox`.
   - Alternatively, use `NotificationCenter` **cannot** cross the process boundary between
     an extension and the host app directly - you must persist data (e.g. to the shared App
     Group `UserDefaults(suiteName:)` or a file in the shared container) and have the host
     app pick it up, e.g. from `applicationDidBecomeActive`/`AppDidFinishLaunching` (which
     `NitroShareIntent` already listens for) by checking the App Group container.
   - Call `self.extensionContext?.completeRequest(returningItems: nil)` when done so the
     system dismisses the Share Sheet.

6. **Update `NitroShareIntent.swift`** (native library code, not example-only) once the
   App Group container path is decided, so `checkForPendingDocuments()` scans that shared
   container in addition to `Documents/Inbox`. This is a small, mechanical change once the
   App Group identifier and file layout are fixed - deliberately not guessed at here since
   it depends on the App Group id a real consumer app chooses.

7. **Build and run the extension's scheme** at least once directly from Xcode (Product →
   Scheme → select the extension scheme) to confirm it's signed and embeds correctly before
   relying on `Embed Foundation Extensions` alone.

## Why this is out of scope for the automated fix pass

- Target creation, entitlements, and `Info.plist` `NSExtension` keys must be resolved by
  Xcode itself (UUIDs, build phases, provisioning) - hand-editing `project.pbxproj` blind
  risks corrupting the project for both the example app and any consumer copying its
  pattern.
- The App Group identifier is inherently consumer-specific (must match their bundle id /
  Apple Developer account team), so there's no single "correct" value to hardcode into the
  example.
