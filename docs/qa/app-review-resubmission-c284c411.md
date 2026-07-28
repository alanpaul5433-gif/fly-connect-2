# App Review resubmission — submission c284c411-077a-45a9-b6d6-532cdb896768

Rejected 2026-07-23, build 1.0.0 (4), reviewed on iPad Air 11-inch (M3), iPadOS 26.5.2.
Two issues: Guideline 5.1.2(i) (ATT) and Guideline 2.1(a) (Sign in with Apple bug).

---

## 1. Guideline 5.1.2(i) — Data Use and Sharing

### What was actually wrong

The App Store Connect privacy label declared **Device ID, Product Interaction, User ID
and Crash Data as "Data Used to Track You."** FlyConnect does not track. It has no
advertising SDK, no attribution SDK (no AdMob, AppsFlyer, Adjust, Branch, Meta SDK),
does not share data with data brokers, and does not link its data with third-party data
for advertising.

The label contradicted the app's own privacy manifest, which has always declared
`NSPrivacyTracking = false` with every collected data type marked
`NSPrivacyCollectedDataTypeTracking = false`
(`ios/Runner/PrivacyInfo.xcprivacy`). A reviewer sees a binary claiming no tracking, a
label claiming tracking, and no ATT prompt — so the submission fails.

This is Apple's **resolution option 1**: the app does not track, so the label is what
changes.

### Code change made anyway (build 6)

Build 4 did link two advertising-related frameworks, pulled in transitively — nothing in
`pubspec.yaml` requests advertising:

```
firebase_analytics
  └─ Firebase/Analytics
       └─ GoogleAppMeasurement/Default
            ├─ GoogleAppMeasurement/IdentitySupport   ← reads the IDFA
            └─ GoogleAdsOnDeviceConversion            ← ads conversion measurement
```

`ios/Podfile` now sets `$FirebaseAnalyticsWithoutAdIdSupport = true`, which
`firebase_analytics.podspec` reads to substitute
`Firebase/AnalyticsWithoutAdIdSupport`. Verified against the resolved release link line
(`Pods-Runner.release.xcconfig`) — both frameworks are gone. Build 6 has no ability to
read the advertising identifier at all, so "we do not track" is now enforced by the
binary rather than asserted in a plist.

Analytics and Crashlytics still function; only the ad-identity variant was dropped.

### Binary verification (build 6, `flutter build ios --release`, 2026-07-28)

Checked against the compiled `Runner.app`, not the build settings:

| Check | Command | Result |
| --- | --- | --- |
| Ad frameworks linked | `otool -L Runner \| grep -iE 'AdSupport\|AppTrackingTransparency'` | **neither is linked** |
| IDFA / ATT API references | `strings -a Runner \| grep -iE 'ASIdentifierManager\|advertisingIdentifier\|ATTrackingManager'` | **no matches** |
| Analytics still present | `strings -a Runner \| grep -E 'FIRAnalytics\|GoogleAppMeasurement'` | present — Analytics works |
| ATT usage string | `PlistBuddy -c 'Print :NSUserTrackingUsageDescription'` | does not exist |
| Version | `CFBundleShortVersionString` / `CFBundleVersion` | 1.0.0 / 6 |

`AdSupport.framework` is the only way to reach `ASIdentifierManager.advertisingIdentifier`.
A binary that does not link it **cannot** read the IDFA under any runtime condition. This
is the difference between "we promise we don't track" and "the binary is incapable of
tracking," and it is independently checkable by App Review.

Note `FirebaseAnalytics` is a *static* framework, so it does not appear in
`Runner.app/Frameworks/` — it links directly into the `Runner` executable. Its absence
from that directory is not evidence of anything; check the symbols instead.

### Android, because Apple asks about other platforms

Apple's resolution option 2 asks whether the app tracks on platforms other than the
one submitted, so the Review Notes sentence "does not track on any platform" is a claim
about the Android build too. Two independent mechanisms back it, and neither implies
the other:

| Mechanism | Stops | Where |
| --- | --- | --- |
| `AD_ID` permission removed via `tools:node="remove"` | the SDK **reading** the Android advertising ID | `AndroidManifest.xml` |
| `google_analytics_adid_collection_enabled`, `..._allow_ad_personalization_signals`, `..._allow_ad_user_data` = `false` | Analytics data being **shared onward** to Google Ads for personalization and audiences | `AndroidManifest.xml` |

The permission removal was already in place; the three meta-data flags default to `true`
and were added in build 6. Without them the app fed Google Ads personalization signals —
"linking data with third-party data for advertising" in Apple's own definition — while
the notes claimed otherwise.

At `targetSdk = 35`, Play Services returns a zeroed advertising ID to an app that has not
declared `AD_ID`, so the removal is fully effective rather than advisory.

All of the above is guarded by `test/infrastructure/ios_store_compliance_test.dart`.

### App Store Connect changes required (Account Holder or Admin)

App Store Connect → FlyConnect → App Privacy → Edit.

Move all four data types **out of "Used to Track You."** For each, keep the collection
declaration and set the purpose as below, matching `PrivacyInfo.xcprivacy`:

| Data type           | Used for tracking | Linked to user | Purpose            |
| ------------------- | ----------------- | -------------- | ------------------ |
| Device ID           | **No**            | Yes            | Analytics, App Functionality |
| Product Interaction | **No**            | Yes            | Analytics          |
| User ID             | **No**            | Yes            | App Functionality  |
| Crash Data          | **No**            | **No**         | App Functionality  |

Also confirm the rest of the label still matches the manifest: Email Address, Name,
Photos or Videos and Precise Location are collected, linked to the user, App
Functionality, **not** used for tracking.

When every "Used to Track You" box is cleared, App Store Connect stops requiring an ATT
declaration and the 5.1.2(i) issue is resolved. **Save the label before uploading
build 6.**

---

## 2. Guideline 2.1(a) — Sign in with Apple error

### Root cause

`lib/shared/providers/real_providers.dart`, `signInWithApple()`. The Firebase OAuth
credential was built from Apple's `identityToken` and `rawNonce` only, omitting Apple's
`authorizationCode`. FirebaseAuth needs that code in the `accessToken` slot to complete
the server-side token exchange with Apple; without it, it rejects an otherwise valid
credential with `invalid-credential` — surfaced in the app as
"Invalid OAuth response from apple.com."

Not iPad-specific. It failed on every iOS device; the reviewer's iPad is incidental. It
is also not a Firebase console misconfiguration — the Services ID, key and bundle ID
were all correct, which is why the error message is misleading.

### Fix (build 6)

```dart
final oauthCredential = OAuthProvider('apple.com').credential(
  idToken: appleCredential.identityToken,
  rawNonce: rawNonce,
  accessToken: appleCredential.authorizationCode,  // ← added
);
```

Guarded by `test/infrastructure/ios_store_compliance_test.dart` so it cannot silently
go missing from a shipped build again.

### Note on Hide My Email

Sign in with Apple works with **both** "Share My Email" and "Hide My Email". The signup
email-domain allowlist (`app_config/signup_gate`) is **not enforced** in production —
the config document does not exist, and `firestore.rules` treats a missing document as
off — so a private-relay address is accepted normally. No reviewer-specific
configuration is needed.

---

## Review Notes for the resubmission

Paste into App Store Connect → Version Information → Notes for Review:

> **Guideline 5.1.2(i)**
> FlyConnect does not track users. We have corrected the App Privacy information: Device
> ID, Product Interaction, User ID and Crash Data are no longer declared as "Used to
> Track You." They are collected only for analytics and app functionality via Firebase
> Analytics and Crashlytics. The app contains no advertising SDK, no attribution SDK, and
> shares no data with data brokers. This build also removes the advertising-identifier
> variant of the Firebase Analytics SDK: the binary does not link AdSupport.framework or
> AppTrackingTransparency.framework, so it has no ability to access the IDFA at all.
> The app's privacy manifest has always declared NSPrivacyTracking = false. Behaviour is
> identical in all countries and regions. The Android build likewise removes the
> advertising ID permission and disables all Google Analytics ad-personalization signals,
> so the app does not track on any platform and no App Tracking Transparency prompt is
> present.
>
> **Guideline 2.1(a) — Sign in with Apple**
> Fixed. Apple's authorization code was not being passed to Firebase Authentication when
> constructing the credential, so Firebase rejected a valid Apple sign-in with
> "Invalid OAuth response from apple.com." The credential is now built with the
> authorization code included, and Sign in with Apple has been verified on iPhone and
> iPad, with both "Share My Email" and "Hide My Email."
>
> To test: launch the app, tap "Sign in with Apple" on the login screen (or "Sign up with
> Apple" on the signup screen). Either email option completes successfully and lands on
> the home feed.

---

## Pre-upload checklist

- [ ] App Privacy label updated in App Store Connect and saved
- [ ] `flutter test` green
- [ ] Sign in with Apple manually verified on a physical iPad, both email options
- [ ] Sign in with Apple manually verified on iPhone
- [ ] Build number is 1.0.0 (6)
- [ ] Review Notes pasted into the submission
