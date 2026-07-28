import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint pass for the two things App Review rejected in submission
/// `c284c411-077a-45a9-b6d6-532cdb896768` (build 1.0.0(4), 2026-07-23).
///
/// # Why this test exists
///
/// Both rejections were invisible to `flutter test`, `flutter analyze` and
/// code review, because neither lives in Dart logic a unit test would reach:
/// one was a missing argument on a call that still compiles, the other was a
/// CocoaPods subspec three levels down the dependency graph. The only place
/// they show up is in a review email, three days after upload.
///
/// ## Guideline 2.1(a) — "an error message when we attempted to login using
/// Sign in with Apple"
///
/// `OAuthProvider('apple.com').credential(...)` accepts every argument as
/// optional and named. Omit `accessToken` and the code compiles, analyzes
/// clean, and fails only at runtime on a real device against real Apple
/// servers — with `invalid-credential` / "Invalid OAuth response from
/// apple.com", which reads like a Firebase console misconfiguration and sends
/// you auditing Services IDs instead of reading the call site. Firebase needs
/// Apple's `authorizationCode` there to complete the server-side token
/// exchange; `idToken` + `rawNonce` alone look sufficient and are not.
///
/// The fix was written on 2026-07-24 and then sat uncommitted while build 4 —
/// which did not contain it — went to review. So this guard is aimed at the
/// argument being absent from the file for ANY reason, not just at someone
/// deliberately deleting it.
///
/// ## Guideline 5.1.2(i) — ATT prompt expected but absent
///
/// `firebase_analytics` pulls `Firebase/Analytics`, which pulls
/// `GoogleAppMeasurement/IdentitySupport` (reads the IDFA) and
/// `GoogleAdsOnDeviceConversion` (ads conversion measurement). Nothing in
/// `pubspec.yaml` mentions advertising; the linkage is only visible in
/// `Podfile.lock`. A binary that links those while declaring
/// `NSPrivacyTracking = false` is exactly the contradiction a reviewer flags.
///
/// `ios/Podfile` sets `$FirebaseAnalyticsWithoutAdIdSupport`, which
/// `firebase_analytics.podspec` reads to swap in
/// `Firebase/AnalyticsWithoutAdIdSupport`. That global is one line and no
/// build failure results from deleting it — the ad frameworks simply return
/// on the next `pod install`, silently, and the next submission gets the same
/// rejection.
///
/// These are file-content assertions rather than behavioural tests on purpose:
/// the failure mode being guarded is "the line is not in the shipped file",
/// which is precisely what a content assertion checks and what no amount of
/// mocking would have caught.
void main() {
  group('Guideline 2.1(a) — Sign in with Apple', () {
    test('Apple credential passes authorizationCode as accessToken', () {
      final source =
          File('lib/shared/providers/real_providers.dart').readAsStringSync();

      final call = _appleCredentialCall(source);
      expect(
        call,
        isNotNull,
        reason: "Could not find OAuthProvider('apple.com').credential(...) in "
            'signInWithApple. If the call was refactored, update '
            '_appleCredentialCall below — do not delete this test.',
      );

      expect(
        call,
        contains('accessToken:'),
        reason: 'The Apple credential has no accessToken argument. Firebase '
            "needs Apple's authorizationCode there to complete the token "
            'exchange; without it, sign-in fails at runtime with '
            'invalid-credential / "Invalid OAuth response from apple.com" '
            'while still compiling and analyzing clean. This is what got '
            'build 1.0.0(4) rejected.',
      );
      expect(
        call,
        contains('authorizationCode'),
        reason: 'accessToken must carry Apple\'s authorizationCode, not the '
            'identity token or anything else.',
      );
    });
  });

  group('Guideline 5.1.2(i) — no tracking, no ATT prompt needed', () {
    test('Podfile disables the advertising-identifier Analytics variant', () {
      final podfile = File('ios/Podfile').readAsStringSync();
      expect(
        podfile,
        contains(r'$FirebaseAnalyticsWithoutAdIdSupport = true'),
        reason: 'Removing this re-links GoogleAppMeasurementIdentitySupport '
            '(IDFA) and GoogleAdsOnDeviceConversion on the next pod install, '
            'which contradicts NSPrivacyTracking=false and invites a repeat '
            'of the 5.1.2(i) rejection.',
      );
    });

    test('Podfile.lock links no advertising-identifier pods', () {
      final lock = File('ios/Podfile.lock').readAsStringSync();

      // The resolved graph is the ground truth — the Podfile global only
      // matters if someone actually re-ran pod install after setting it.
      for (final pod in const [
        'GoogleAdsOnDeviceConversion',
        'GoogleAppMeasurement/IdentitySupport',
      ]) {
        expect(
          lock,
          isNot(contains(pod)),
          reason: '$pod is linked into the app binary. Run `pod install` in '
              'ios/ after confirming the Podfile global is set.',
        );
      }

      expect(
        lock,
        contains('GoogleAppMeasurement/WithoutAdIdSupport'),
        reason: 'Podfile.lock is stale — it predates the Podfile global. '
            'Run `pod install` in ios/ and commit the lock.',
      );
    });

    test('privacy manifest declares no tracking, on every data type', () {
      final manifest =
          File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();

      // NSPrivacyTracking must be false and NSPrivacyTrackingDomains empty.
      expect(
        manifest.replaceAll(RegExp(r'\s+'), ''),
        contains('<key>NSPrivacyTracking</key><false/>'),
        reason: 'Flipping this to true requires an ATT prompt and a matching '
            'App Store Connect label, neither of which this app has.',
      );

      // A single data type marked Tracking=true is enough for Apple to
      // require ATT, even with the top-level flag false.
      expect(
        manifest,
        isNot(contains('<key>NSPrivacyCollectedDataTypeTracking</key>\n'
            '\t\t\t<true/>')),
        reason: 'A data type marked as used for tracking requires ATT.',
      );
    });

    test('Info.plist requests no tracking permission', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      // The inverse guard: if someone adds this string, they intend to track,
      // and the privacy manifest plus the ASC label must change with it.
      // Failing here is a prompt to update all three together, not a veto.
      expect(
        plist,
        isNot(contains('NSUserTrackingUsageDescription')),
        reason: 'Adding an ATT prompt means NSPrivacyTracking, the per-type '
            'Tracking flags, and the App Store Connect privacy label all have '
            'to change in the same commit.',
      );
    });

    // Android assertions in an iOS-named file, deliberately: Apple's 5.1.2(i)
    // guidance asks whether the app tracks on OTHER platforms too, and the
    // Review Notes for this submission answer "not on any platform." That
    // sentence is a claim about the Android build, so the Android build is
    // part of what an iOS submission has to keep true.
    test('Android manifest opts out of every advertising signal', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final normalized = manifest.replaceAll(RegExp(r'\s+'), ' ');

      // Two independent mechanisms, and neither implies the other:
      // removing AD_ID stops the SDK READING the advertising ID; the
      // meta-data flags stop Analytics data being SHARED to Google Ads.
      expect(
        normalized,
        contains('android:name="com.google.android.gms.permission.AD_ID" '
            'tools:node="remove"'),
        reason: 'Firebase Analytics re-injects the AD_ID permission '
            'transitively. Without the removal the app can read the Android '
            'advertising ID, which contradicts both the Play Data Safety '
            'declaration and the App Review notes.',
      );

      for (final flag in const [
        'google_analytics_adid_collection_enabled',
        'google_analytics_default_allow_ad_personalization_signals',
        'google_analytics_default_allow_ad_user_data',
      ]) {
        final declaration = RegExp(
          'android:name="$flag" android:value="false"',
        );
        expect(
          normalized,
          matches(RegExp('.*${declaration.pattern}.*')),
          reason: '$flag is not declared false. It defaults to true, which '
              'lets Analytics data feed Google Ads personalization and '
              'audiences — "linking data with third-party data for '
              'advertising" in Apple\'s definition of tracking.',
        );
      }
    });
  });
}

/// Returns the full argument list of the
/// `OAuthProvider('apple.com').credential(...)` call, or null if absent.
///
/// Anchored on `.credential(` rather than on `OAuthProvider('apple.com')`
/// alone, because the web branch of `signInWithApple` builds a provider with
/// `..addScope(...)` and hands it to `signInWithPopup` — that one takes no
/// credential arguments and would otherwise match first.
///
/// Depth-counts parentheses to find the end of the call, so nested calls like
/// `credential(accessToken: foo(bar))` stay intact. A stray unbalanced paren
/// inside a comment or string in the argument list would confuse it; if that
/// ever happens the test fails loudly rather than passing wrongly.
String? _appleCredentialCall(String source) {
  const marker = "OAuthProvider('apple.com').credential(";
  final start = source.indexOf(marker);
  if (start == -1) return null;

  var depth = 0;
  for (var i = start + marker.length - 1; i < source.length; i++) {
    final char = source[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return null; // Unterminated call — treat as missing.
}
