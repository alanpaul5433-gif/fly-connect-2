# Store Readiness Audit — FlyConnect

**Date:** 2026-06-19
**Version audited:** 1.0.0+1
**Platforms:** Android + iOS (+ admin web shell)
**Framework:** Flutter (Dart 3.0+, Provider + GoRouter, real Firebase)
**Auditor:** `store-readiness-audit` skill (senior DevOps + QA pass)

---

## Overall Readiness: **72.3%**

**Submission status:** ⚠️ **CONDITIONAL** — strong foundation, a small set of hard blockers remain.

> FlyConnect is a genuinely well-engineered, submission-aware codebase. The hardest store requirements — **real** in-app account deletion, UGC reporting, user blocking, ToS/Privacy consent gating, locked-down Firestore/Storage rules, and a complete iOS Privacy Manifest — are all implemented and write to the backend (no fakery). The remaining blockers are **configuration and hosting**, not missing features:
>
> 1. The Privacy Policy / Terms URLs are written but **not hosted** (cross-platform blocker).
> 2. iOS Firebase + Google Sign-In are **not finished being wired** (iOS-only blockers).
>
> **Android-only readiness is ~84%** (READY-conditional). **iOS readiness is ~62%** (the iOS config gaps dominate). Estimated effort to clear all Critical + High items: **1.5–2.5 engineering days** plus ~1 external task (host the legal pages).

---

## Per-Category Scores

| Category | Score | Weight | Weighted | Status |
|----------|------:|:------:|---------:|:------:|
| 1. Technical Build | 78% | 15% | 11.7 | 🟡 |
| 2. Platform Manifests | 50% | 10% | 5.0 | 🔴 |
| 3. Policy Compliance | 90% | 15% | 13.5 | 🟢 |
| 4. Store Listing | 80% | 10% | 8.0 | 🟡 |
| 5. Console Setup | 50% | 10% | 5.0 | 🔴 |
| 6. Backend / Firebase | 55% | 10% | 5.5 | 🔴 |
| 7. Feature Completeness | 85% | 15% | 12.75 | 🟢 |
| 8. Quality / Tests | 72% | 15% | 10.8 | 🟡 |
| **TOTAL** | — | 100% | **72.3** | ⚠️ |

*Status:* 🟢 ≥ 85%  🟡 60–84%  🔴 < 60%
*Cap rule applied:* categories 2, 5, 6 each carry a Critical finding → capped at 50–55% regardless of other wins.

---

## 🔴 Critical Blockers (3)

### 1. Privacy Policy & Terms of Service URLs are not live (BOTH stores)

**Where:** `lib/features/auth/signup_screen.dart:391` & `:403` (in-app links), `docs/store-listing.md:137,143` (console URLs)

**Why it blocks:** `https://flyconnect.app/privacy` and `https://flyconnect.app/terms` return **ECONNREFUSED** — the domain is not serving these pages. Google Play (App Content → Privacy Policy) and Apple (Guideline 5.1.1) both fetch this URL during review; a dead link is an automated rejection. The in-app consent links also open to nothing.

**Fix:** Host the already-written `docs/privacy-policy.md` and `docs/terms-of-service.md` at those exact paths (GitHub Pages / Firebase Hosting / any static host with a custom domain), then re-verify both resolve over HTTPS with real content. The copy is done — this is pure hosting.

**Effort:** Half day (incl. DNS) · **External** (ops/domain)

**References:** Play Privacy Policy policy; App Store Review 5.1.1.

---

### 2. iOS Google Sign-In URL scheme is still a placeholder

**Where:** `ios/Runner/Info.plist:44` → `<string>com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID</string>`

**Why it blocks:** The login and signup screens offer "Sign in with Google" (`login_screen.dart:176`, `signup_screen.dart:89`). On iOS, Google Sign-In hands control to this URL scheme; with the placeholder unreplaced the OAuth callback cannot return — the flow hangs or crashes. A reviewer tapping the button hits a broken core flow (Guideline 2.1).

**Fix:** Add the iOS app in Firebase Console, download `GoogleService-Info.plist`, copy its `REVERSED_CLIENT_ID` into `Info.plist:44`. (Pairs with blocker #3.)

**Effort:** 30 min · **External** (Firebase Console) — iOS only.

**References:** App Store Review 2.1; Google Sign-In iOS setup.

---

### 3. iOS native Firebase is not configured (no GoogleService-Info.plist, empty iosAppId)

**Where:** `lib/core/config/firebase_config.dart:22` → `static const String iosAppId = '';` and missing `ios/Runner/GoogleService-Info.plist` (gitignored at `.gitignore:48` and absent locally).

**Why it blocks:** On iOS the app falls back to the **web** app id (`firebase_config.dart:70`), which the code itself warns "will misbehave." Native Crashlytics, Analytics, and **FCM push token registration** target the wrong/absent app — push notifications, a headline feature, won't deliver on iOS, and crash reporting is unreliable. Android is unaffected (its `google-services.json` is present).

**Fix:** Register the iOS bundle `com.appcurb.flyconnect` in Firebase Console, add `GoogleService-Info.plist` to the Runner target in Xcode, and set `iosAppId` from its `GOOGLE_APP_ID`. Then enable the **Apple** auth provider in Firebase (for Sign in with Apple).

**Effort:** 1 hour · **External** (Firebase Console + Xcode) — iOS only.

**References:** Apple Push entitlement; Firebase iOS setup; blockers-critical §G.

---

## 🟠 High Priority (3)

### 1. `targetSdk = 34` is below the current Google Play requirement (API 35)

**Where:** `android/app/build.gradle.kts:36` (comment even says "Google Play 2026 requirement")

**Why:** Since Aug 31 2025, Google Play requires **new apps and updates to target API 35 (Android 15)**. An AAB at `targetSdk 34` is rejected at upload. `compileSdk` is already 36, so the bump is trivial.

**Fix:** `targetSdk = 35`. Build, smoke-test (Android 15 enforces stricter foreground-service & predictive-back behavior). **Effort:** 30 min + smoke test.

### 2. Local release builds silently fall back to the **debug** keystore

**Where:** `android/app/build.gradle.kts:56-60` (release `signingConfig` → debug when `key.properties` is absent; `key.properties` is not present locally)

**Why:** A locally-run `flutter build appbundle --release` produces a **debug-signed** AAB, which Play rejects ("uploaded a debug-signed bundle"). Production signing currently works **only** through CI (`.github/workflows/ci.yml` decodes the keystore secret and writes `key.properties`).

**Fix:** Either (a) make CI the only release path (document it) and/or (b) follow `docs/keystore-setup.md` to place a real `key.properties` locally. Add a guard that **fails** a release build rather than falling back to debug. **Effort:** 30 min.

### 3. Sign in with Apple — verify capability, entitlement & Firebase provider are live

**Where:** UI wired at `login_screen.dart:191` / `signup_screen.dart:110`; entitlement/provider not verifiable from source. `ios/Runner.xcodeproj/project.pbxproj` has **130 uncommitted lines** (capability work in progress).

**Why:** Apple Guideline 4.8 **requires** Sign in with Apple because Google sign-in is offered — and it's a good-faith requirement that it actually works. Code is present, but the Xcode "Sign in with Apple" capability, the App ID entitlement, and the Firebase Apple provider must all be enabled or the button fails review.

**Fix:** In Xcode → Signing & Capabilities add **Sign in with Apple**; enable the capability on the App ID; enable Apple provider in Firebase Auth. Test on a **real device** (SIWA can't be tested in the simulator). Commit the `project.pbxproj` changes. **Effort:** 1 hour · External (Apple portal + device).

---

## 🟡 Medium (6)

- **[`lib/features/settings/settings_screen.dart:69,71`]** — "Update Phone" / "Update Email" show a *"Coming soon"* sheet. Also *Mute notifications* (`conversation_screen.dart:68`), *Image messages* (`conversation_screen.dart:171`), *Group events* (`groups/group_details_screen.dart:132,479`), *Edit Group* (`business/group_management_screen.dart:89`). These are **honest** stubs (no fake success → not "deceptive"), but Apple sometimes flags visible unfinished features (2.1/4.2). **Recommend hiding these entry points for v1.0.**
- **[`lib/features/settings/settings_screen.dart:114,116`]** — Settings "Terms"/"Privacy" tiles only show a text sheet ("View at flyconnect.app/privacy") instead of launching the URL, while signup launches it properly. Make them `launchUrl` the live page (consistency + an in-app path to the policy, which Apple likes).
- **[`android/app/build.gradle.kts:61-62`]** — `isMinifyEnabled = false`, `isShrinkResources = false`. Not a blocker for Flutter (Dart is AOT-compiled), but enabling R8 shrinks/obfuscates the Java/Kotlin layer and reduces AAB size. Enable with a tested `proguard-rules.pro` (Firebase/Play keep rules already present).
- **[`firebase_config.dart:32` vs `AndroidManifest.xml:56`]** — Deep-link host mismatch: manifest verifies `flyconnect.app`, config's `deepLinkHost = app.flyconnect.com`. iOS has **no Associated Domains** entry, so Universal Links won't work on iOS. Pick one host, align both, and add the iOS Associated Domains capability if web deep-linking is intended.
- **[`test/`]** — Provider unit coverage is **3/12** (Auth, Post, Promotion only). Major feature screens have ~no widget tests; both `integration_test/*` files are `skip: true`. See the generated `docs/store-readiness-test-plan.md`.
- **[`android/app/build.gradle.kts:35`]** — `minSdk = flutter.minSdkVersion`. Confirm this resolves to **≥ 23** (Firebase Auth requirement, per the inline comment); the Flutter default has historically been 21. Pin `minSdk = 23` explicitly to be safe.

---

## 🔵 Low (6)

- **[`web/index.html:21,32`]** — `<title>flyconnect</title>` (lowercase) and `<meta description="A new Flutter project.">`. Admin-web only (not consumer-store), but fix branding.
- **[`web/manifest.json:2,3,8`]** — `name`/`short_name` lowercase, `description: "A new Flutter project."`.
- **[`lib/features/admin/admin_reports_page.dart:517,571`, `admin_audit_page.dart:197`, `admin_business_verification_page.dart:438`]** — Empty `onPressed: () {}` (View Target / Ban Reporter / Export CSV / verification). **Admin web build only — not in the consumer store binary**, so non-blocking. Wire or hide before the admin tool ships.
- **[`lib/features/settings/settings_screen.dart:120`]** — App-version tile has a no-op `onTap: () {}`. Remove the handler (it's display-only) so it doesn't show a tap ripple implying action.
- **[no `firebase_app_check` in `pubspec.yaml`]** — App Check isn't wired. Rules are the real guard (good), but App Check meaningfully reduces backend abuse for a social app. Consider adding before scale.
- **[`.github/workflows/ci.yml`]** — `dart format` runs with `continue-on-error: true`, so formatting drift can't block merge. Minor hygiene.

---

## Category Notes

**1 · Technical Build (78%)** — Production bundle id `com.appcurb.flyconnect` ✓, `compileSdk 36` ✓, versioning ✓, `flutter_launcher_icons`/`flutter_native_splash` configured with a 1024² source ✓. Dinged for targetSdk 34, the debug-signing fallback, and minify-off.

**2 · Platform Manifests (50%, capped)** — Android manifest is exemplary: scoped permissions, `READ_EXTERNAL_STORAGE` maxSdk-gated, camera `required=false`, full `<queries>` block, FCM channel, deep links. iOS Info.plist is excellent (ATS strict, `ITSAppUsesNonExemptEncryption=false`, descriptive usage strings, background modes). Capped solely by the **REVERSED_CLIENT_ID placeholder** (Critical #2).

**3 · Policy Compliance (90%)** — The strongest category. Real account deletion (`real_providers.dart:245-303` — deletes user doc, subcollections, anonymizes posts, calls `user.delete()`, writes a GDPR audit trail), real reporting to a `reports` collection (`:794-832`) gated to admins in `firestore.rules:191-198`, real blocking (`:835-857`), enforced ToS/Privacy consent on signup (`signup_screen.dart:84`), and a complete, accurate `PrivacyInfo.xcprivacy`. The privacy-URL hosting gap is scored under Console Setup.

**4 · Store Listing (80%)** — `docs/store-listing.md` has compliant name/short/full descriptions and category. Icon source present. Screenshots & 1024×500 feature graphic must still be produced/uploaded (`docs/app-assets-guide.md` covers this) — external.

**5 · Console Setup (50%, capped)** — Excellent prep docs (`play-console-setup.md`, `data-safety-form.md`, `keystore-setup.md`, `pre-launch-report-guide.md`). Capped by the **unhosted privacy/terms URLs** (Critical #1) and unverifiable console state (Data Safety submission, SHA-1/256 registration, content rating) — all external.

**6 · Backend / Firebase (55%, capped)** — Firestore rules are tight and field-level defensive (`changedOnly`), Storage rules default-deny, indexes are lint-tested (`test/infrastructure/`), Crashlytics + Analytics + FCM all wired in `main.dart`, Google + Apple auth implemented. Capped by **iOS Firebase not configured** (Critical #3). Android backend wiring is ~90%.

**7 · Feature Completeness (85%)** — No deceptive patterns found across a deep scan: share uses real `Clipboard.setData`, media uploads to Storage (`create_post_screen.dart:34-75`), pull-to-refresh calls real listeners, OTP uses Firebase email verification. Dinged only for the honest "coming soon" stubs (Medium #1).

**8 · Quality / Tests (72%)** — 21 test files / ~125 cases, including a clever Firestore-index lint test and rate-limiter/JSON-normalization unit tests. CI analyzes, tests, and gates release builds behind green tests. Dinged for the provider/screen coverage gaps and skipped integration tests.

---

## Remediation Roadmap

| # | Task | Blocker? | Effort | Depends on | External? |
|:-:|------|:--------:|:------:|------------|:---------:|
| 1 | Host `privacy-policy.md` + `terms-of-service.md` at `flyconnect.app/privacy` & `/terms`; verify HTTPS 200 | 🔴 | half day | — | DNS/host |
| 2 | Register iOS app in Firebase → add `GoogleService-Info.plist` to Runner; set `iosAppId` | 🔴 | 1h | — | Firebase |
| 3 | Replace `REVERSED_CLIENT_ID` in `Info.plist:44` from the plist | 🔴 | 15min | #2 | — |
| 4 | Enable Apple provider in Firebase + SIWA capability/entitlement; test on device | 🟠 | 1h | #2 | Apple/Firebase |
| 5 | Bump `targetSdk = 35`; smoke-test on Android 15 | 🟠 | 30min | — | — |
| 6 | Make release builds fail (not debug-fallback) without `key.properties`; document CI-only signing | 🟠 | 30min | — | — |
| 7 | Hide "Coming soon" entry points (phone/email update, mute, image msgs, group events, edit group) for v1.0 | 🟡 | 1h | — | — |
| 8 | Make Settings legal tiles `launchUrl` the live pages | 🟡 | 15min | #1 | — |
| 9 | Align deep-link host; add iOS Associated Domains (if web links wanted) | 🟡 | 1h | — | — |
| 10 | Add unit tests for the 9 untested providers; un-skip integration tests in CI | 🟡 | 1–2d | — | — |
| 11 | Fix web `index.html`/`manifest.json` branding; wire/hide admin dead buttons | 🔵 | 30min | — | — |

**Total estimated effort:** ~1.5–2.5 engineering days + 1 external hosting task + Firebase/Apple console steps.

---

## Submission Decision Tree (current state)

```
Any 🔴 Critical open?  → YES (3)  → DO NOT submit yet.
  • Android-only path: only Critical #1 (privacy URL) blocks Android.
    Fix #1, #5, #6 → Android is submission-ready (~84%). Ship to Internal track.
  • iOS path: Criticals #1, #2, #3 + High #4 all block iOS.
    Fix #1–#4 → iOS submission-ready (~85%).
```

**Recommended play:** Host the legal pages (#1) + Android target/signing (#5,#6) → submit **Android to the Internal track first**. Finish the iOS Firebase/Apple wiring (#2–#4) in parallel and submit iOS to TestFlight once green.

---

## Test Coverage Gap Analysis

| Test type | Current | Target | Gap |
|-----------|:-------:|:------:|:---:|
| Unit tests (providers) | 3/12 providers | 12/12 | 9 providers |
| Widget tests (screens) | ~2/54 screens | core flows | Home, Chat, Match, Profile, Settings |
| Integration tests | 2 files, skipped | running in CI | un-skip + emulator service |
| CI/CD pipeline | Yes (analyze+test+gated build) | + coverage gate | threshold not enforced |
| Manual smoke test | Yes (`docs/manual-smoke-test.md`) | — | — |

See `docs/store-readiness-test-plan.md` for the full plan and drop-in stubs.

---

_Generated by the `store-readiness-audit` Claude skill. Re-run after fixes to re-score._
