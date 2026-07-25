# React Native Nitro Share Intent

A powerful React Native library for handling native share intents on iOS and Android, built with [Nitro Modules](https://nitro.margelo.com/) for optimal performance and developer experience.

![React Native](https://img.shields.io/badge/React%20Native-0.81+-blue.svg)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Version](https://img.shields.io/badge/version-0.7.0-blue.svg)

## ✨ Features

- **🔗 Native Share Intent Handling** - Seamlessly handle share intents from other apps
- **📱 Cross-Platform Support** - Works on both iOS and Android
- **📄 Multiple File Types** - Support for text, single files, and multiple files
- **🎯 TypeScript Ready** - Full TypeScript support with comprehensive type definitions
- **⚡ Nitro Modules Powered** - High-performance native module architecture
- **🔄 Real-time Listening** - Listen for share intents in real-time
- **📊 Rich Metadata** - Extract file metadata (dimensions, duration, size, etc.)
- **🎨 Utility Functions** - Helper utilities for common share intent operations
- **📤 Native iOS Share Sheet** - The Share Extension target is generated and embedded during `pod install`; no Xcode target, no native code, no `Podfile` changes

## 📦 Installation

```bash
npm install react-native-nitro-share-intent react-native-nitro-modules
```

> **Note**: `react-native-nitro-modules` is required as this library relies on [Nitro Modules](https://nitro.margelo.com/).

## 🚨 Migrating to 0.6.0

**v0.6.0 removes the need for any custom native code in your app.** Full details
in [CHANGELOG.md](./CHANGELOG.md); the short version:

- **iOS**: the `AppDelegate.swift` snippets from older versions (the
  `AppDidFinishLaunching` and `ShareIntentReceived` notification posts) are no
  longer required. You can delete them - keeping them is also safe, since
  duplicate deliveries of the same URL are now de-duplicated.
- **Android**: the `onNewIntent` override in `MainActivity` is no longer
  required and can be deleted (keep `super.onNewIntent(intent)` if you override
  it for other reasons). The `AndroidManifest.xml` intent filters and
  `launchMode="singleTask"` are still needed - that's configuration, not code.
- **Behavior change (iOS)**: re-sharing the *same* URL or link later in the same
  app session now delivers a new event each time. Previously, a non-file URL was
  silently swallowed forever after its first delivery. Only identical URLs
  arriving within a 3-second window are collapsed into one event.
- **New opt-out (iOS)**: set `NitroShareIntentAppDelegateProxyEnabled` to `NO`
  in `Info.plist` to disable the automatic `AppDelegate` hook and keep wiring
  the notification manually.

### iOS Setup

> ✅ **No AppDelegate changes required** (since v0.6.0). The library hooks into the
> app lifecycle on its own:
>
> - At launch it installs an `application(_:open:options:)` handler on your app
>   delegate at runtime - **only if your app doesn't implement one itself**. If
>   your `AppDelegate` (or a superclass like Expo's delegate wrapper) already
>   implements that method, the library never touches it.
> - If your app forwards URL opens to React Native's Linking module
>   (`RCTLinkingManager` - i.e. you already have deep linking set up), the
>   library picks those URLs up automatically via `RCTOpenURLNotification`.
> - "Open In..." file hand-offs are detected by monitoring your app's
>   `Documents/Inbox` directory - no delegate code involved.
>
> The same URL arriving through more than one of these paths is de-duplicated,
> so it's also safe to keep the old manual snippet from pre-0.6.0 setups.
>
> **Opting out**: set `NitroShareIntentAppDelegateProxyEnabled` to `NO` (Boolean)
> in your `Info.plist` if you don't want the runtime hook. In that case wire the
> notification manually - see [Manual AppDelegate setup](#manual-appdelegate-setup-optional)
> below.

1. **Configure URL Schemes in Info.plist** (only needed if you receive shares
   through a custom URL scheme, e.g. from a Share Extension redirect):
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleTypeRole</key>
       <string>Editor</string>
       <key>CFBundleURLName</key>
       <string>com.yourcompany.yourapp</string>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>yourapp</string>
       </array>
     </dict>
   </array>
   ```

2. **The native iOS Share Sheet works out of the box** (since v0.7.0).

   On iOS, an app can only appear in the Share Sheet's app row if it ships a
   **Share Extension** - a second, separately signed target. There is no
   Info.plist key or entitlement that registers a plain app there, so this is
   not something a library can avoid. What it *can* do is create that target
   for you: `pod install` generates it, embeds it in your app, and wires up the
   App Group both sides need.

   You do not add a target, write native code, or touch your `Podfile`. On the
   next `pod install` you'll see:

   ```
   ✨ NitroShareIntent — thanks for installing! Made with 💛 by Yogesh Solanki
      Created Share Extension target 'NitroShareExtension' and embedded it in your app.
      App Group: group.<your.bundle.id>.nitroshareintent
   ```

   Shared items are written into the App Group container and picked up by your
   app on launch and whenever it becomes active - a Share Extension runs in its
   own sandbox and cannot write into your app's `Documents/Inbox`, which is what
   the "Open In..." path uses.

   **One manual step remains:** enable the *App Groups* capability for both
   targets under *Signing & Capabilities*. Provisioning profiles can't be
   generated by a script - automatic signing usually handles this on the first
   build, but manual signing and CI may need the group added in the Apple
   developer portal.

   **Configuration** is optional and lives in your app's `package.json`, so
   nothing under `ios/` needs editing:

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

   | Key | Default | Description |
   | --- | --- | --- |
   | `enabled` | `true` | Set to `false` to skip generating the extension entirely. |
   | `appGroup` | `group.<bundleId>.nitroshareintent` | App Group shared by the app and the extension. |
   | `extensionName` | `NitroShareExtension` | Target name, and the folder generated next to your `Podfile`. |
   | `openHostApp` | `true` | Foreground your app right after a share. See the caveat below. |
   | `activation` | see above | What the Share Sheet offers your app for. |

   > **`openHostApp` caveat**: extensions have no `UIApplication` of their own,
   > so this reaches `openURL:` through the responder chain. It's what
   > comparable libraries do, but it's a grey area for App Store review. Set it
   > to `false` to skip it - the share is still collected the next time your app
   > becomes active.

   The generated target owns nothing of yours: its principal class ships inside
   the pod, so upgrading the package upgrades the extension too.

#### Manual AppDelegate setup (optional)

Only needed if you disabled the runtime hook with
`NitroShareIntentAppDelegateProxyEnabled = NO`, or your build strips the hook
(the hook relies on the `-ObjC` linker flag, which React Native templates set
by default). Add this to `AppDelegate.swift`:

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
  NotificationCenter.default.post(
    name: NSNotification.Name("ShareIntentReceived"),
    object: nil,
    userInfo: ["url": url]
  )
  return true
}
```

The pre-0.6.0 `AppDidFinishLaunching` post in
`didFinishLaunchingWithOptions` is **no longer needed at all** - inbox
monitoring now starts on its own. Leaving it in place is harmless.

### Android Setup
**Configure Intent Filters in AndroidManifest.xml**:

   ```xml
   <activity
     android:name=".MainActivity"
     android:exported="true"
     android:launchMode="singleTask">

     <!-- Handle text sharing -->
     <intent-filter>
       <action android:name="android.intent.action.SEND" />
       <category android:name="android.intent.category.DEFAULT" />
       <data android:mimeType="text/plain" />
     </intent-filter>

     <!-- Handle file sharing -->
     <intent-filter>
       <action android:name="android.intent.action.SEND" />
       <category android:name="android.intent.category.DEFAULT" />
       <data android:mimeType="*/*" />
     </intent-filter>

     <!-- Handle multiple file sharing -->
     <intent-filter>
       <action android:name="android.intent.action.SEND_MULTIPLE" />
       <category android:name="android.intent.category.DEFAULT" />
       <data android:mimeType="*/*" />
     </intent-filter>
   </activity>
   ```

> ✅ **No `MainActivity` changes required** (since v0.6.0). `ReactActivity`
> already forwards `onNewIntent` through React Native's `ActivityEventListener`
> mechanism, which `NitroShareIntent` registers against - so re-shares to an
> already-running app reach JavaScript with zero custom code. (`launchMode="singleTask"`
> in the manifest, as shown above, is still needed so re-shares don't spawn a
> duplicate Activity.)
>
> The only way to break this is overriding `onNewIntent` yourself (or via
> another library) **without calling `super.onNewIntent(intent)`** - if you do
> override it, keep the `super` call, or shares will silently stop working.

## 🚀 Quick Start

### Basic Usage

```typescript
import React, { useState } from 'react';
import { View, Text, ScrollView } from 'react-native';
import { useShareIntent, SharePayload, ShareIntentUtils } from 'react-native-nitro-share-intent';

const App = () => {
  const [shares, setShares] = useState<SharePayload[]>([]);

  // Listen for share intents
  useShareIntent((payload: SharePayload) => {
    console.log('Received share:', payload);
    setShares(prev => [...prev, payload]);
  });

  return (
    <View style={{ flex: 1, padding: 16 }}>
      <Text style={{ fontSize: 24, fontWeight: 'bold', marginBottom: 16 }}>
        Share Intent Demo
      </Text>

      <ScrollView>
        {shares.map((share, index) => (
          <View key={index} style={{ padding: 12, marginBottom: 8, backgroundColor: '#f5f5f5' }}>
            <Text style={{ fontWeight: 'bold' }}>
              Type: {share.type.toUpperCase()}
            </Text>

            {ShareIntentUtils.isTextShare(share) && (
              <Text>Text: {share.text}</Text>
            )}

            {ShareIntentUtils.isFileShare(share) && (
              <Text>Files: {share.files?.join(', ')}</Text>
            )}

            {share.extras && Object.keys(share.extras).length > 0 && (
              <Text style={{ fontSize: 12, color: '#666' }}>
                Extras: {JSON.stringify(share.extras)}
              </Text>
            )}
          </View>
        ))}
      </ScrollView>
    </View>
  );
};

export default App;
```

### Get Initial Share

```typescript
import { getInitialShare, SharePayload } from 'react-native-nitro-share-intent';

// Get the initial share when the app opens
const handleAppStart = async () => {
  const initialShare = await getInitialShare();
  if (initialShare) {
    console.log('Initial share:', initialShare);
    // Handle the initial share
  }
};
```

## 📚 API Reference

### Hooks

#### `useShareIntent(callback: (payload: SharePayload) => void, onError?: (message: string) => void)`

A React hook that listens for incoming share intents. Multiple components can each call
`useShareIntent` independently - every mounted instance gets its own listener and is cleaned
up automatically when the component unmounts.

The optional second argument is called if the native side fails to read/parse an incoming
share (e.g. couldn't copy a shared file) - distinct from there simply being nothing shared.

```typescript
useShareIntent(
  (payload) => {
    // Handle the received share
    console.log('Share received:', payload);
  },
  (message) => {
    console.warn('Failed to read a shared item:', message);
  }
);
```

### Functions

#### `getInitialShare(): Promise<SharePayload | null>`

Retrieves the initial share intent when the app is opened via a share action. Resolves with
`null` when there is nothing to report (never hangs). Rejects if the native side failed to
read/parse the pending share.

```typescript
const initialShare = await getInitialShare();
if (initialShare) {
  // Handle the initial share
}
```

#### `clearShareIntent(): void`

Clears any pending/cached share intent, so a subsequent `getInitialShare()` call resolves
with `null` until a new share arrives. Useful once you've consumed/handled the initial share
and don't want it re-delivered (e.g. to a newly mounted `useShareIntent` listener).

```typescript
import { clearShareIntent } from 'react-native-nitro-share-intent';

clearShareIntent();
```

### Types

#### `SharePayload`

```typescript
type SharePayload = {
  type: ShareType; // 'text' | 'file' | 'multiple'
  text?: string; // Shared text content
  files?: string[]; // Array of file URIs
  extras?: Record<string, string>; // Additional metadata
};
```

#### `ShareType`

```typescript
type ShareType = 'text' | 'file' | 'multiple';
```

### Utility Functions

#### `ShareIntentUtils`

A collection of helper functions for working with share payloads:

```typescript
import { ShareIntentUtils } from 'react-native-nitro-share-intent';

// Check share type
ShareIntentUtils.isTextShare(payload); // Returns boolean
ShareIntentUtils.isFileShare(payload); // Returns boolean
ShareIntentUtils.isMultipleFileShare(payload); // Returns boolean

// Extract metadata
ShareIntentUtils.getSubject(payload); // Returns string | undefined
ShareIntentUtils.getAdditionalText(payload); // Returns string | undefined

// File type detection
ShareIntentUtils.isImageFile(fileUri); // Returns boolean
ShareIntentUtils.isVideoFile(fileUri); // Returns boolean
ShareIntentUtils.getFileExtension(fileUri); // Returns string | undefined

// Display formatting
ShareIntentUtils.formatForDisplay(payload); // Returns formatted string
```

### Testing / Mocking

`react-native-nitro-share-intent/mock` exports a lightweight, in-memory `MockShareIntentModule`
so consumer apps can simulate shares in Jest tests without a real device or the native module:

```typescript
import { MockShareIntentModule } from 'react-native-nitro-share-intent/mock';

const mockModule = new MockShareIntentModule();

const listenerId = mockModule.onIntentListener((payload) => {
  // assert on `payload` in your test
});

mockModule.simulateShare({ type: 'text', text: 'Hello from a test' });
mockModule.simulateError('Something went wrong reading the share');

mockModule.removeListener(listenerId);
```

### Web Support

Importing `react-native-nitro-share-intent` on `react-native-web` (or any bundler that
resolves `.web.ts`/`.web.js` files, e.g. Webpack/Metro-for-web) automatically uses a no-op
stub instead of crashing: `useShareIntent` becomes a no-op, `getInitialShare()` always
resolves `null`, and `clearShareIntent()` does nothing. `ShareIntentUtils` works identically
everywhere since it's pure JS.

## 🔧 Advanced Usage

### Handling Different Share Types

```typescript
import {
  useShareIntent,
  ShareIntentUtils,
  SharePayload,
} from 'react-native-nitro-share-intent';

const ShareHandler = () => {
  useShareIntent((payload: SharePayload) => {
    if (ShareIntentUtils.isTextShare(payload)) {
      console.log('Text shared:', payload.text);
    } else if (ShareIntentUtils.isFileShare(payload)) {
      if (ShareIntentUtils.isMultipleFileShare(payload)) {
        console.log('Multiple files shared:', payload.files?.length);
      } else {
        console.log('Single file shared:', payload.files?.[0]);
        const fileUri = payload.files?.[0];
        if (fileUri && ShareIntentUtils.isImageFile(fileUri)) {
          console.log("It's an image file!");
        }
      }
    }
  });

  return null;
};
```

### Working with File Metadata

```typescript
useShareIntent((payload: SharePayload) => {
  if (payload.files && payload.files.length > 0) {
    payload.files.forEach((fileUri, index) => {
      console.log(`File ${index + 1}:`, {
        uri: fileUri,
        extension: ShareIntentUtils.getFileExtension(fileUri),
        isImage: ShareIntentUtils.isImageFile(fileUri),
        isVideo: ShareIntentUtils.isVideoFile(fileUri),
      });
    });
  }

  if (payload.extras) {
    console.log('File metadata:', {
      fileName: payload.extras.fileName,
      fileSize: payload.extras.fileSize,
      mimeType: payload.extras.mimeType,
      dimensions:
        payload.extras.width && payload.extras.height
          ? `${payload.extras.width}x${payload.extras.height}`
          : 'N/A',
      duration: payload.extras.duration,
    });
  }
});
```

## 🎯 Use Cases

### Social Media Apps

- Share content from other apps to your social media platform
- Handle image/video sharing from gallery apps
- Process text sharing from browsers or messaging apps

### Content Creation Apps

- Import images/videos from other apps
- Handle file sharing for editing purposes
- Process multiple file selections

### Utility Apps

- File management and organization
- Content processing and conversion
- Cross-app workflow automation

## 🔍 Troubleshooting

### Common Issues

1. **Share intent not working on Android**
   - Ensure proper intent filters in `AndroidManifest.xml`
   - Check that your app is set as the default handler for the share types

2. **Files not accessible on iOS**
   - Verify app has proper permissions for file access
   - Check that file types are supported in your app's configuration

3. **Initial share not detected**
   - Use `getInitialShare()` to capture shares when the app is opened via share intent
   - Ensure your app is properly configured to handle the share types

### Debugging

```typescript
useShareIntent((payload) => {
  console.log('Share Intent Debug:', {
    type: payload.type,
    text: payload.text,
    files: payload.files,
    extras: payload.extras,
  });
});
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a pull request

### Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Nitro Modules](https://nitro.margelo.com/) for superior performance
- Inspired by the React Native community's need for robust share intent handling
- Thanks to all contributors who help improve this library

---

**Made with ❤️ by [Yogesh Solanki](https://github.com/SolankiYogesh)**

If you find this library helpful, please consider giving it a ⭐ on GitHub!
