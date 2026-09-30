# ConvertFlow iOS

Native SwiftUI port scaffold for ConvertFlow.

This project mirrors the Android product surface: local-first document conversion, sample workflows, batch queue, history, privacy controls, and a Pro upgrade surface. It is source-ready for Xcode, but this Windows machine cannot produce a signed `.ipa` because App Store builds require macOS with Xcode and an Apple Developer signing identity.

## Build on macOS

1. On macOS, open `ios/ConvertFlow/ConvertFlow.xcodeproj` in Xcode.
2. Select the `ConvertFlow` target.
3. Set your Apple Developer Team under Signing & Capabilities.
4. Keep bundle identifier `com.convertflow.ios` or replace it with your App Store Connect bundle id.
5. Archive with `Product > Archive`, then upload through Organizer or export an `.ipa`.

## Current Scope

- SwiftUI app shell
- MVVM state model
- Local sample conversion flows
- Loading, empty, error, offline, success states
- History and batch screens
- Privacy and Pro sheets

Real PDF/DOCX/XLSX conversion engines still need native iOS implementations or a shared service layer before store submission.
