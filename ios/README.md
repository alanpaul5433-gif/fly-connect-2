# iOS Setup — Manual Steps (Requires Mac)

The iOS project was scaffolded on Windows. The following steps must be completed on macOS before the first App Store submission.

## 1. Open the project in Xcode

```bash
open ios/Runner.xcworkspace
```

Always use the **workspace**, not the `.xcodeproj` — CocoaPods needs the workspace.

## 2. Configure the Runner target

- **Bundle Identifier:** `com.urbansyncinnovations.flyconnect` (must match `android/app/build.gradle.kts`, `google-services.json`, and `lib/core/config/firebase_config.dart`)
- **Team:** assign your Apple Developer team
- **Deployment Target:** iOS 13.0 or higher (Firebase Auth requires 13+)
- **Display Name:** FlyConnect

## 3. Add required capabilities

In Xcode → Signing & Capabilities, add:

- ✅ **Push Notifications** — required for FCM
- ✅ **Sign in with Apple** — required by App Store Guideline 4.8 because we offer Google Sign-In
- ✅ **Background Modes** → enable "Remote notifications" and "Background fetch"

## 4. Download and add GoogleService-Info.plist

1. Firebase Console → Project Settings → Add app → iOS
2. Register with bundle ID `com.urbansyncinnovations.flyconnect`
3. Download `GoogleService-Info.plist`
4. Drag it into `ios/Runner/` in Xcode (enable "Copy items if needed", add to Runner target)

## 5. Update the Google Sign-In URL scheme

In `ios/Runner/Info.plist`, find the placeholder:

```xml
<string>com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID</string>
```

Replace with the `REVERSED_CLIENT_ID` value from `GoogleService-Info.plist`.

## 6. Install CocoaPods

```bash
cd ios
pod install --repo-update
cd ..
```

## 7. First build

```bash
flutter run -d ios
```

If you hit signing errors, confirm your Team is set in Xcode and that provisioning profiles are downloaded.

## 8. Store submission checklist

- [ ] App icon asset set in `Assets.xcassets/AppIcon` (all required sizes)
- [ ] Launch screen polished (update `Assets.xcassets/LaunchImage` and `LaunchScreen.storyboard`)
- [ ] Marketing version bumped in `pubspec.yaml` (`version:`) flows into `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)`
- [ ] Archive via Xcode → Product → Archive → Distribute to App Store Connect
- [ ] Complete "App Privacy" nutrition label in App Store Connect (matches `PrivacyInfo.xcprivacy`)
- [ ] Upload dSYMs to Firebase Crashlytics for release builds (Run Script phase or manual)

## Files already configured

- `ios/Runner/Info.plist` — permission strings, URL schemes, ATS, background modes
- `ios/Runner/PrivacyInfo.xcprivacy` — required by Apple since May 1, 2024
