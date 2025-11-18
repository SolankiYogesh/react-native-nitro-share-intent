# React Native Nitro Share Intent

A powerful React Native library for handling native share intents on iOS and Android, built with [Nitro Modules](https://nitro.margelo.com/) for optimal performance and developer experience.

![React Native](https://img.shields.io/badge/React%20Native-0.81+-blue.svg)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)

## ✨ Features

- **🔗 Native Share Intent Handling** - Seamlessly handle share intents from other apps
- **📱 Cross-Platform Support** - Works on both iOS and Android
- **📄 Multiple File Types** - Support for text, single files, and multiple files
- **🎯 TypeScript Ready** - Full TypeScript support with comprehensive type definitions
- **⚡ Nitro Modules Powered** - High-performance native module architecture
- **🔄 Real-time Listening** - Listen for share intents in real-time
- **📊 Rich Metadata** - Extract file metadata (dimensions, duration, size, etc.)
- **🎨 Utility Functions** - Helper utilities for common share intent operations

## 📦 Installation

```bash
npm install react-native-nitro-share-intent react-native-nitro-modules
```

> **Note**: `react-native-nitro-modules` is required as this library relies on [Nitro Modules](https://nitro.margelo.com/).

### iOS Setup

1. **Add to AppDelegate.swift**:
   ```swift
   import NitroShareIntent
   
   func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
     // Your existing code...
     
     // Notify NitroShareIntent about app launch
     NotificationCenter.default.post(name: NSNotification.Name("AppDidFinishLaunching"), object: nil)
     
     return true
   }
   
   func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
     // Handle share intent URLs
     NotificationCenter.default.post(
       name: NSNotification.Name("ShareIntentReceived"),
       object: nil,
       userInfo: ["url": url]
     )
     return true
   }
   ```

2. **Configure URL Schemes in Info.plist**:
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

### Android Setup

1. **Add to MainActivity.java/kt**:
   ```kotlin
   import com.margelo.nitro.nitroshareintent.NitroShareIntent
   
   override fun onCreate(savedInstanceState: Bundle?) {
     super.onCreate(savedInstanceState)
     // Your existing code...
     
     // Handle initial share intent
     NitroShareIntent.instance.handleIntent(intent)
   }
   
   override fun onNewIntent(intent: Intent) {
     super.onNewIntent(intent)
     // Handle new share intents
     NitroShareIntent.instance.handleIntent(intent)
   }
   ```

2. **Configure Intent Filters in AndroidManifest.xml**:
   ```xml
   <activity
     android:name=".MainActivity"
     android:exported="true"
     android:launchMode="singleTop">
   
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

#### `useShareIntent(callback: (payload: SharePayload) => void)`

A React hook that listens for incoming share intents.

```typescript
useShareIntent((payload) => {
  // Handle the received share
  console.log('Share received:', payload);
});
```

### Functions

#### `getInitialShare(): Promise<SharePayload | null>`

Retrieves the initial share intent when the app is opened via a share action.

```typescript
const initialShare = await getInitialShare();
if (initialShare) {
  // Handle the initial share
}
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
