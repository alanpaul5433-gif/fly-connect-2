# FlyConnect — Store Readiness Re-Audit & Fix Log

**Date:** 2026-06-19 · **Supersedes the scores in:** `docs/audit-report.md` (72.3%)
**Targets:** Google Play (near-term) + App Store (later)

> This is a **re-audit + fix log**. The prior `docs/audit-report.md` is preserved.
> A deeper pass corrected two over-generous prior scores (Policy 90%, Features 85%)
> and several fixes were applied this session.

---

## Readiness after this session

| | Prior audit | This re-audit (pre-fix) | **After this session's fixes** |
|---|:--:|:--:|:--:|
| **Overall** | 72.3% | 68.5% | **~77.5%** |
| **Android-only track** | ~84% | ~75% | **~85%** |

_Update: legal pages went live at `flyconnect.co` and the app was repointed (see below) — but they sit behind a Hostinger bot-challenge that 403s crawlers, so C1 is **mitigated, not closed**._

### Per-category (current)

| # | Category | Wt | Score | Note |
|---|----------|:--:|:--:|------|
| 1 | Technical Build | 15% | 78% | targetSdk 35 ✓; minify off; pin minSdk≥23 (M6) |
| 2 | Platform Manifests | 10% | 70% | iOS URL scheme ✓; **iOS entitlements file missing** (H4) |
| 3 | Policy Compliance | 15% | **85%** | deletion/age/consent ✓; **block + report user now wired** |
| 4 | Store Listing | 10% | 78% | copy ready; visual assets not generated (M8) |
| 5 | Console Setup | 10% | 60% | URLs live at flyconnect.co + app repointed; **verify store crawlers aren't 403'd** by Hostinger bot-challenge (C1) |
| 6 | Backend / Firebase | 10% | 82% | rules locked down; **matchPrefs rule pending deploy** |
| 7 | Feature Completeness | 15% | **85%** | match prefs persist+filter; dead affordances removed |
| 8 | Quality / Tests | 15% | **75%** | strong provider coverage (post/chat/match/promotion/auth + 2 new); integration test inert; no screen widget tests |

---

## ✅ Fixed this session

| Audit ID | Fix | Files |
|---|---|---|
| **H1** | "Block user" now calls `PostProvider.blockUser` behind a confirm dialog, flips `_blockedRelationship`, and leaves the screen | `lib/features/profile/profile_screen.dart` |
| **H2** | "Report user" now opens a reason picker → `PostProvider.reportContent(targetType:'user')` → confirmation toast | `lib/features/profile/profile_screen.dart` |
| **H3** | Match Preferences now **load on open** and **persist on Save** to `users/{uid}.matchPrefs`; `MatchProvider.loadCandidates` filters the feed by airline / position / verified. (Age + distance are saved but not yet filtered — `UserModel` has no DOB/geo; noted in code.) | `firestore.rules`, `lib/shared/providers/real_providers.dart` (`UserProvider.get/saveMatchPrefs`, `MatchProvider.loadCandidates`), `lib/features/match/match_preferences_screen.dart` |
| **M1/M2** | Removed the dead "Tag crew members" row and "+ Add tag" chip (and the now-unused `_TagChip.outlined`) | `lib/features/home/create_post_screen.dart` |
| **M3** | Removed the non-functional "Add Cover Photo" placeholder | `lib/features/events/create_group_screen.dart` |
| Tests | Added regression tests for block/report shapes and match-prefs persistence + filter predicate | `test/features/profile_moderation_test.dart`, `test/features/match_preferences_test.dart` |
| CI | Removed an unused import that would fail the CI `flutter analyze` step (warnings are fatal) | `test/providers/auth_provider_test.dart` |

**Verification:** `flutter analyze` clean on all changed files; `flutter test` → all pass (incl. 2 new files).

---

## 🚨 Action required before these fixes are live

1. **Deploy Firestore rules.** H3 added `matchPrefs` to the user-update allow-list in `firestore.rules`. Until deployed, Save will be **denied** in production:
   ```bash
   firebase deploy --only firestore:rules
   ```
3. **Make the legal pages crawler-reachable.** `flyconnect.co/privacy-policy/` and `/terms-of-service/` are **live but behind a Hostinger bot-challenge** — a `curl`/Googlebot request gets `HTTP 403` + a "Just a moment… Checking your browser" interstitial. Google Play & Apple fetch the privacy URL with bots during review; if they're challenged too, it reads as a dead link → rejection. **Disable "Under Attack"/bot-fight for these pages, allowlist Googlebot + Apple's crawler, OR move the two pages to Firebase Hosting (`flyconnect-ab4f2.web.app`), which has no challenge.** Verify with an incognito browser AND a plain `curl` returning HTTP 200 with the policy text.

---

## Remaining blockers / follow-ups

| Sev | ID | Item | Owner |
|---|---|---|---|
| 🟠 | C1 | Legal pages live at `flyconnect.co` + app repointed (`lib/core/constants/legal_urls.dart`), BUT behind a bot-challenge that 403s crawlers — fix crawler access or move host (see Action #3) | external/infra |
| 🟠 | H4 | iOS: add `Runner.entitlements` (`applesignin` + `aps-environment`), enable in Xcode (Apple 4.8) | iOS |
| 🟡 | M6 | Pin `minSdk = 23` explicitly (don't rely on `flutter.minSdkVersion`) | Android |
| 🟡 | M8 | Generate feature graphic + screenshots (`docs/app-assets-guide.md`) | design |
| 🟡 | — | Un-skip `integration_test/post_create_flow_test.dart`; have CI run it against the emulator | QA |
| 🔵 | — | Pre-existing `curly_braces` infos in `event_management_screen.dart` (CI-tolerant) | cleanup |

**Bottom line:** With the UGC block/report and match-preferences stubs now functional and the
app pointed at the live `flyconnect.co` legal pages, the remaining Android launch path is
**(1) make the legal pages crawler-reachable (not 403), (2) deploy the Firestore rules**, then
generate store art. iOS additionally needs the entitlements file.
