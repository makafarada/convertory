# Convertory Release Package

Prepared in `C:\Users\emrsa\OneDrive\Desktop\APP DEV\ConvertFlow`.

Open first:

- `START_HERE.html`
- `open-ms-store-preview.cmd`

## Android

Existing artifacts:

- `ConvertFlow.apk`
- `ConvertFlow.aab`

The source zip also contains the same APK/AAB. I could not rebuild a fresh artifact in this workspace because the Gradle wrapper executable and wrapper jar are missing from the source archive, and no system Gradle executable is installed. The Android SDK and Android Studio JDK are present.

Before Play Console upload, verify the AAB is release-signed with the upload key. A prior observed blocker for this project was Play Console rejecting a debug-signed Android artifact.

## iOS

Added iOS native source scaffold:

- `ios/ConvertFlow/Sources/ConvertFlow/ConvertFlowApp.swift`
- `ios/ConvertFlow/Sources/ConvertFlow/Models.swift`
- `ios/ConvertFlow/Sources/ConvertFlow/ConvertFlowViewModel.swift`
- `ios/ConvertFlow/Sources/ConvertFlow/RootView.swift`
- `ios/ConvertFlow/Sources/ConvertFlow/Views.swift`
- `ios/ConvertFlow/ConvertFlow.xcodeproj`

This is a SwiftUI/MVVM port scaffold. A signed `.ipa` cannot be produced on this Windows machine because iOS archive/upload requires macOS, Xcode, and Apple Developer signing.

## Microsoft Store

Added Store-compatible PWA package:

- `ms-store/index.html`
- `ms-store/styles.css`
- `ms-store/app.js`
- `ms-store/manifest.webmanifest`
- `preview-server.mjs`
- `convert-pdf-to-docx.py` and `vendor/pdf2docx/`

For a quick Windows preview, run `open-ms-store-preview.cmd`. It starts the current files at `http://127.0.0.1:4760/` with caching disabled. PDF to Word uses the local loopback server and produces editable DOCX files with reconstructed text, images, tables, and page layout. It does not upload a selected document to the internet.

A static hosted PWA cannot run this local DOCX engine. A Partner Center release therefore needs an MSIX desktop host that bundles the conversion runtime as a local companion process. The Android APK/AAB is not a normal Microsoft Store desktop package.
