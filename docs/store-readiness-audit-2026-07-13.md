# FlyConnect — Store Readiness Audit

**Date:** 2026-07-13 · **Supersedes:** `docs/audit-report.md` (72.3%, 2026-06-19) and `docs/store-readiness-reaudit-2026-06-19.md` (77.5%, 2026-06-19)
**Version audited:** 1.0.0+4 · **Branch:** `store-readiness-android-prep` @ `757196b`
**Platforms:** Android (live on Play Store) + iOS (not yet submitted) + admin web shell
**Framework:** Flutter (Dart 3.0+, Provider + GoRouter, real Firebase)
**Context:** The app is **already live on Google Play**. This audit covers a large uncommitted-then-committed Phase 1+2 change batch (rebrand, video posting, QR/share-profile, business-only event/group creation, "Crew Deals" rename, admin Nearby map) that is the candidate for the **next** Play Store update and eventual first App Store submission.

---

## Overall Readiness: **69.0%**

**Submission status:** ❌ **NOT READY** — 3 Critical blockers, one of them an active production security issue, not just a submission-review risk.

> Readiness **dropped** from 77.5% (2026-06-19, post-fix) to 69.0% today. This is not a regression in the work done this session — genuine progress landed (targetSdk 35, signing hardened, iOS Firebase/Google/Apple Sign-In fully wired, 151/151 tests passing, dead UI stubs removed, video posting shipped end-to-end, business-only gating now enforced server-side). The score dropped because this audit **verified live production state** instead of trusting file contents, and found two things no prior audit had confirmed directly: **production Firestore has never actually enforced any of the rules in `firestore.rules`** (it's running Firebase's default wide-open test-mode rule), and the new Phase 2 business-management screens (`group_management_screen.dart`, `event_management_screen.dart`) **look fully functional but silently do nothing** for several of their primary actions (Delete Group, Broadcast Message, Remove Member/Attendee, Edit Event). Both are worse, and more discoverable by a reviewer or attacker, than anything the 06-19 audits flagged.

**Android-only readiness:** ~72% (blocked by the two Firebase/rules and fake-screen issues; manifest/build gating is otherwise solid).
**iOS readiness:** ~68% (Firebase/Google/Apple Sign-In config is now genuinely fixed — the 06-19 iOS blockers are closed — but inherits the same three cross-platform Criticals below).

---

## Per-Category Scores

| Category | Score | Weight | Weighted | Status | Trend vs 06-19 |
|----------|------:|:------:|---------:|:------:|:---:|
| 1. Technical Build | 90% | 15% | 13.5 | 🟢 | ▲ from 78% |
| 2. Platform Manifests | 92% | 10% | 9.2 | 🟢 | ▲ from 70% |
| 3. Policy Compliance | 88% | 15% | 13.2 | 🟢 | ▲ from 85% |
| 4. Store Listing | 78% | 10% | 7.8 | 🟡 | ▬ unchanged |
| 5. Console Setup | 45% | 10% | 4.5 | 🔴 | ▼ from 60% (issue confirmed still unresolved after 3+ weeks) |
| 6. Backend / Firebase | 35% | 10% | 3.5 | 🔴 | ▼ from 82% (live state now verified, was never actually this good) |
| 7. Feature Completeness | 50% | 15% | 7.5 | 🔴 (capped) | ▼ from 85% (new fake screens found) |
| 8. Quality / Tests | 65% | 15% | 9.75 | 🟡 | ▲ raw count, ▼ risk-adjusted |
| **TOTAL** | — | 100% | **69.0** | ❌ | ▼ from 77.5% |

*Status:* 🟢 ≥ 85% 🟡 60–84% 🔴 < 60%
*Cap rule applied:* categories 5, 6, 7 each carry a Critical finding → capped regardless of other wins, per the audit skill's scoring rule.

---

## 🔴 Critical Blockers (3)

### 1. Production Firestore has never enforced `firestore.rules` — the live database is fully open

**Where:** Firebase project `flyconnect-ab4f2`, confirmed live via `firebase_get_security_rules(type: firestore)` this session — not inferable from the repo alone, which is presumably why three prior audits (including the 06-19 reaudit, which scored this category 82% and said "rules locked down") missed it.

**Why it blocks:** The rule actually serving traffic right now is Firebase's default: `allow read, write: if request.time < timestamp.date(2026, 12, 12);` — i.e. **any client, authenticated or not, can read or write every document in the entire database** until that date. The repo's `firestore.rules` (role-based, field-whitelisted, and as of this session's `757196b` also gates events/groups creation to business/admin accounts) is well-designed but has **never once been deployed**. `storage.rules`, by contrast, *is* live (confirmed separately) — so this is specifically a Firestore gap, not a general "we don't deploy rules" habit.

**Why this is worse than a submission blocker:** the app is already live with real users. This isn't "will fail review" — it's "is currently exploitable in production." Anyone with the Firebase Web SDK config (which ships inside the APK, by design) can read every user's profile, every private message, every SafeCheck "need_help" alert, and write arbitrary data into any collection, right now.

**Fix:** `firebase deploy --only firestore:rules` (steps already documented in `docs/firestore-rules-deploy.md`). Validated clean this session via `firebase_validate_security_rules`. This is a **10-minute fix with no code changes required** — it was drafted, reviewed, and held back pending your go-ahead earlier this session.

**Effort:** 10 min · **Blocking, do this first regardless of anything else in this report.**

---

### 2. Two new business-management screens perform almost no real backend actions

**Where:** `lib/features/business/group_management_screen.dart` (worst offender) and `lib/features/business/event_management_screen.dart`. Both are reachable in the shipping app by any authenticated business-role user (`app_router.dart:215` and business dashboard nav) — not admin-only, not dev-only.

**Why it blocks:** Apple 4.2 (Minimum Functionality) and Play's deceptive-behavior policy both cover exactly this pattern: a UI that presents itself as functional — real confirmation dialogs, real "success" SnackBars — while doing nothing. Apple's review is manual; "Delete Group" and "Broadcast Message" on a Groups feature are exactly the buttons a human reviewer taps during a routine walkthrough.

Confirmed fake, with no backend effect whatsoever:
- **Delete Group** (`group_management_screen.dart:57-68`) — confirmation dialog just does `Navigator.pop(context)` twice. The group is never deleted.
- **Broadcast Message** (`:25-39, 277-281`) — composer collects text, `onSend` shows "Message sent to all members" — no Firestore write, no FCM send.
- **Chat enable/disable toggle** (`:111-119`) — flips local state only; reverts on screen reopen.
- **Member roster** (`:22`) — `_members = <UserModel>[]` is never populated from Firestore; the Members tab and Pending Requests are permanently empty.
- **"Posts" stat** (`:83`) — hardcoded `'24'`, not read from Firestore.
- **Remove from Group / Make Admin** (`:170-176`) — local list mutation + SnackBar only.
- **Edit Event** (`event_management_screen.dart:131-140`) — "Save Changes" updates local state only; the `events` doc is untouched, so a reload silently reverts it.
- **Remove Attendee** (`:160-185`) — local list mutation only (contrast: `_approve`/`_decline` on the same screen correctly write to `events/{id}/rsvps/{uid}` — so the pattern for doing this right already exists two functions away).
- **"Link copied!"** (`:253-255`) — shown with no `Clipboard.setData` call at all.

Root cause for `group_management_screen.dart` specifically: it has **no `GroupProvider` calls anywhere** — not a wiring bug, the backend capability doesn't exist yet. `GroupProvider` (`real_providers.dart:1297-1368`) currently only supports `getGroup`, `joinGroup`, `leaveGroup`, `createGroup` — there is no `deleteGroup`, `removeMember`, `broadcastMessage`, or member-roster fetch to call.

**Fix — two options, pick based on your release timeline:**
- **(a) Ship-safe fast path:** hide the broken entry points for this release, the same way the 06-19 session correctly hid "Coming soon" stubs elsewhere (that pattern is confirmed still in place and working — see Category 7 notes). Remove/disable Delete Group, Broadcast, Chat toggle, Member management on `group_management_screen.dart`; remove/disable Edit and Remove Attendee on `event_management_screen.dart`; add `Clipboard.setData` to the one-line "Link copied!" fix. **Effort: ~2 hours.**
- **(b) Real fix:** add `GroupProvider.deleteGroup()`, `.removeMember()`, `.broadcastMessage()`, `.fetchMembers()`, `.setChatEnabled()` backed by real Firestore writes (rules already permit owner/admin delete; broadcast would need a new write path — e.g. a `groupBroadcasts` subcollection + FCM topic send — with matching rules), wire the screen to them, add regression tests. **Effort: ~1 day** (this is materially more work than the 06-19 session's block/report rewire, which called *existing* provider methods — here the methods don't exist yet).

**Effort:** 2h (hide) or 1 day (build for real) · Recommend (a) now, (b) as fast-follow.

---

### 3. Legal Policy / Terms pages are hosted but unreachable by automated crawlers — unresolved for 3+ weeks

**Where:** `https://flyconnect.co/privacy-policy/` and `/terms-of-service/` (`lib/core/constants/legal_urls.dart`).

**Why it blocks:** Re-tested today with three separate requests (plain `curl`, a realistic Chrome User-Agent, and a Googlebot User-Agent) — **all three get HTTP 403** with a "Checking your browser before accessing… Just a moment…" interstitial (a Cloudflare-style JS bot-challenge). This is identical to the exact issue the 06-19 reaudit flagged as "Action required before these fixes are live" — it has not been fixed since. Google Play and Apple both fetch the Privacy Policy URL with automated tooling during review; if that tooling can't execute the JS challenge (most policy-URL crawlers can't), it reads as a dead/inaccessible link, which is an automated-rejection trigger on both stores. A human clicking the link in an actual browser likely sees the real page — the risk is specifically automated review tooling.

**Fix:** Disable "Under Attack"/bot-fight mode (or add a WAF bypass rule) for `/privacy-policy/` and `/terms-of-service/` specifically, or move just those two static pages to a host with no challenge (e.g. Firebase Hosting, `flyconnect-ab4f2.web.app`, already provisioned in this repo for the admin panel). Verify with a plain `curl -I` returning `200` before resubmitting.

**Effort:** 30 min–1h · **External** (hosting/Cloudflare dashboard, not code).

---

## 🟠 High Priority (5)

### 1. Group member removal is fake **and** unguarded
**Where:** `lib/features/groups/group_details_screen.dart:384-404`. `setState(() => _members.remove(uid))` — local only, no Firestore write, claims "Member removed." Also: the remove-member affordance is shown to **every viewer**, not gated to the group's owner/admin — a bug in its own right beyond the fakery (any member could see, if not successfully use, an admin-only control).
**Fix:** Add `GroupProvider.removeMember()` (see Critical #2) and gate the icon behind `g.admins.contains(currentUid)`. **Effort:** rolls into Critical #2's fix.

### 2. `isMinifyEnabled` / `isShrinkResources` still `false`
**Where:** `android/app/build.gradle.kts:79-80`. ProGuard rules are present and unused. Not a rejection risk for a Flutter app (Dart is AOT-compiled independent of R8), but it means the Kotlin/Java plugin layer ships unobfuscated and the AAB is larger than necessary.
**Fix:** Enable both, smoke-test a release build (Firebase/Play keep-rules already exist in the referenced proguard file). **Effort:** 1h + smoke test.

### 3. Email-verification "continue" gate is decorative
**Where:** `lib/features/auth/otp_screen.dart:64-79`. The screen's own comment says `// Allow entry regardless of verification status` — `user.reload()` runs (real), but the button routes to home unconditionally regardless of the result. The email actually gets sent (real), just never checked.
**Fix:** Gate navigation on `user.emailVerified` after reload, with a "still not verified — resend" fallback. **Effort:** 30 min.

### 4. Zero automated test coverage on all five Phase 1+2 feature surfaces
**Where:** video posting (`create_post_screen.dart`, `feed_video.dart`), QR/share-profile (`profile_screen.dart`), business-only event/group gating (`events_screen.dart`, `groups_screen.dart`), "Crew Deals" rename, and — now confirmed — the two fake management screens above. None have a single test. Notably, the existing test suite's dominant pattern (contract-style tests against `fake_cloud_firestore` that *mirror* intended provider behavior, e.g. `test/features/profile_moderation_test.dart`) is structurally unable to catch Critical #2 — it tests what a provider *should* write, not whether the widget actually calls it. That blind spot is very likely part of why the fake screens shipped undetected.
**Fix:** Add widget-level tests that pump the actual screen and assert on provider-call side effects (via `Provider` overrides + a spy/mock), not just Firestore-shape mirrors. Prioritize the two management screens once Critical #2 lands. **Effort:** see updated `docs/store-readiness-test-plan.md`.

### 5. `aps-environment` entitlement still set to `development`
**Where:** `ios/Runner/Runner.entitlements`. Xcode typically flips this automatically for an Archive build using a distribution provisioning profile, but it's worth explicitly confirming at archive time — a mismatch here can cause push-notification validation failures on TestFlight/App Store builds.
**Fix:** Verify post-archive, or set explicitly per build configuration. **Effort:** 15 min verification.

---

## 🟡 Medium (5)

- **[`lib/core/config/firebase_config.dart:32`]** — `deepLinkHost = 'app.flyconnect.com'` is confirmed dead code: it matches neither the removed `flyconnect.app` App Links host nor the current `flyconnect.co` share domain. Delete or update.
- **[`android/app/build.gradle.kts`]** — `minSdk = flutter.minSdkVersion` resolves to 24 today (comment explains why it's intentionally not pinned as a literal) — functionally fine (≥23 requirement met) but worth a comment audit if the Flutter SDK's default ever changes.
- **[`SECURITY.md:15`]** — `security@flyconnect.co` is still explicitly marked `(placeholder — replace with your real inbox before launch)`.
- **[`.github/workflows/ci.yml`]** — `dart format --set-exit-if-changed` still `continue-on-error: true`; no coverage-threshold gate exists (coverage is uploaded as an artifact but never checked).
- **[`integration_test/auth_flow_test.dart`, `integration_test/post_create_flow_test.dart`]** — still 100% `skip: true`, unchanged since 06-19. Zero integration tests execute anywhere.

---

## 🔵 Low (5)

- **[`lib/features/admin/admin_audit_page.dart:197`, `admin_business_verification_page.dart:438`, `admin_reports_page.dart:517,571`]** — 4 empty `onPressed: () {}` admin buttons (Export CSV, Request More Info, View Target, Ban Reporter). Admin-web-only in intent, but not confirmed hidden from the mobile bundle's route table — worth a quick check that these routes aren't reachable from the consumer app.
- **[`lib/shared/providers/real_providers.dart:583-595`]** — `_describeAppleAuthError` always returns `null`; falls back to Firebase's generic error copy. Cosmetic.
- **[`lib/features/business/event_management_screen.dart:173-174`]** — 2 `flutter analyze` info-level lints (missing curly braces), zero errors/warnings otherwise.
- **[repo root]** — `test/tutorial.dart` (untracked, not valid test code — a stray JSON-literal scratch file) and `admin-login.png` (stray screenshot) remain untracked in the working tree; harmless but worth deleting.
- **[Play Store SHA-1/256, Data Safety submission, Content Rating]** — prep docs (`play-console-setup.md`, `data-safety-form.md`) are accurate and ready to paste in, but actual Console-side submission state can't be verified from the repo — confirm directly in Play Console / App Store Connect before submitting.

---

## Category Notes

**1 · Technical Build (90%)** — `targetSdk 35`/`compileSdk 36` ✓ (was 34), release signing now **fails loudly** instead of silently falling back to the debug keystore (`build.gradle.kts:59-78` — arguably a better fix than the original ask), version `1.0.0+4`, bundle ID `com.urbansyncinnovations.flyconnect` consistent everywhere. Dinged only for minify/shrink still off.

**2 · Platform Manifests (92%)** — The 06-19 blocker (`REVERSED_CLIENT_ID` placeholder) is fixed and cross-verified against `GoogleService-Info.plist`. Sign in with Apple entitlements are present and wired into `project.pbxproj` across all 3 build configs. AndroidManifest and iOS Info.plist both remain exemplary (scoped permissions with justification comments, ATS strict, no cleartext, `<queries>` block present, FCM channel). Only open item is confirming `aps-environment` flips to `production` at archive time.

**3 · Policy Compliance (88%)** — Account deletion, UGC reporting, and user blocking are all still real and confirmed unchanged (`real_providers.dart`). ToS/Privacy consent gate on signup intact. Note: the fake-action findings in Category 7 (Delete Group, Broadcast, Edit Event) are scored there per this skill's category definitions, but they materially raise *this* category's real-world risk too, since Apple's 4.2/2.1 guidelines and Play's deceptive-behavior policy are exactly what those findings violate — treat Critical #2 as a compliance issue, not just a UX one.

**4 · Store Listing (78%)** — Copy is complete and store-ready (`docs/store-listing.md`). No screenshots or 1024×500 feature graphic exist in the repo yet — unchanged external task, `docs/app-assets-guide.md` covers exact specs.

**5 · Console Setup (45%, capped)** — The legal-URL hosting gap that blocked category 5 in prior audits is *narrower* now (the domain itself resolves and serves real content — this isn't a dead domain anymore) but the crawler-reachability sub-issue is exactly as broken as it was on 06-19, three weeks ago, despite being flagged as the single most actionable item in that report. Scored slightly lower than 06-19's 60% specifically because "flagged three weeks ago and still open" is a worse signal than "just discovered."

**6 · Backend / Firebase (35%, capped)** — This is the biggest score swing in this report. Prior audits scored this 55-82% based on reading the `firestore.rules` *file*, which is genuinely excellent (role-based, field-whitelisted, and as of `757196b` also blocks non-business users from creating events/groups). This audit is the first to check **live deployment state** via the Firebase MCP tools, and found the file has never been pushed — production Firestore has zero enforcement. Storage rules, Auth provider config (Google/Apple/Email all correctly wired for both platforms now), Crashlytics/Analytics/FCM are otherwise solid, which is why this isn't scored even lower.

**7 · Feature Completeness (50%, capped)** — Genuine, verified improvements since 06-19: the previously-flagged visible "Coming soon" stubs are now correctly *hidden* rather than shown-but-fake (phone/email update, mute, image messages, group events — all gated behind `// hidden for v1.0` comments, a good pattern). Account deletion, reporting, blocking, profile share, and post-media upload all remain genuinely real. The score is capped because of Critical #2 — two brand-new business-management screens shipped in this same feature wave are the most extensive fake-UI finding in this project's audit history (5+ distinct fake actions on one screen).

**8 · Quality / Tests (65%)** — Raw numbers improved: 151/151 tests pass (verified via live `flutter test` run, not just trusted), 26 test files (up from 21), provider coverage 5/12 (up from 3/12: Chat and Match gained coverage), `flutter analyze` clean (2 info-lints only). Risk-adjusted down because (a) all new Phase 1+2 surface area has zero coverage, and (b) the dominant test pattern in this repo (contract-style Firestore-shape mirrors) is structurally blind to the exact bug class found in Critical #2 — more tests of the same shape would not have caught it.

---

## Remediation Roadmap

| # | Task | Blocker? | Effort | Depends on | External? |
|:-:|------|:--------:|:------:|------------|:---------:|
| 1 | `firebase deploy --only firestore:rules` | 🔴 | 10 min | — | Firebase CLI auth |
| 2 | Hide broken entry points on `group_management_screen.dart` / `event_management_screen.dart` (Delete Group, Broadcast, Chat toggle, Member mgmt, Edit Event, Remove Attendee); fix "Link copied!" to actually copy | 🔴 | 2h | — | — |
| 3 | Fix crawler access to `/privacy-policy/` and `/terms-of-service/` (disable bot-challenge or move to Firebase Hosting) | 🔴 | 30min–1h | — | Cloudflare/hosting dashboard |
| 4 | Gate `group_details_screen.dart` member-removal icon to admins only | 🟠 | 15 min | — | — |
| 5 | Enable `isMinifyEnabled`/`isShrinkResources`; smoke-test release build | 🟠 | 1h | — | — |
| 6 | Fix OTP screen to actually gate on `emailVerified` | 🟠 | 30 min | — | — |
| 7 | Confirm `aps-environment` flips to `production` on Archive build | 🟠 | 15 min | — | Xcode/Apple portal |
| 8 | Build real `GroupProvider`/event-management backend methods (deleteGroup, removeMember, broadcastMessage, fetchMembers, setChatEnabled) + matching rules + tests | 🟡 (post-launch real fix for #2) | 1 day | #2 | — |
| 9 | Delete dead `deepLinkHost` constant; replace SECURITY.md placeholder inbox | 🟡 | 15 min | — | — |
| 10 | Add widget-level (pump + verify provider call) tests for the 5 untested Phase 1+2 surfaces, especially the fixed management screens | 🟡 | 1–2 days | #2, #8 | — |
| 11 | Un-skip integration tests against a wired Firebase emulator; add CI coverage threshold; make `dart format` blocking | 🟡 | 1 day | — | — |
| 12 | Generate screenshots + 1024×500 feature graphic | 🟡 | half day | — | design |
| 13 | Verify admin-only dead buttons aren't reachable from the mobile route table; clean up `test/tutorial.dart`, `admin-login.png` | 🔵 | 30 min | — | — |

**Total estimated effort to clear all Critical + High:** ~1 day engineering + 1–2 external/console tasks. Items 1–7 alone (all Critical + High, excluding the real backend build-out in #8) are a **half-day push** that would take this app from 69.0% to an estimated **~87%**.

---

## Submission Decision Tree (current state)

```
Any 🔴 Critical open? → YES (3) → DO NOT submit this release to either store, and treat #1 as a live-incident fix regardless of store timing.
  • #1 (Firestore rules) — fix immediately, independent of any release train. This is a live security gap on a shipping app.
  • #2 (fake management screens) — must be fixed or hidden before this release reaches Play (it's already live) or App Store (first submission).
  • #3 (crawler-blocked legal pages) — must be fixed before either store review, or expect an automated rejection.

Once all 3 Criticals close:
  • Android path: re-run this audit. Expect ~87%+ → proceed to Internal track, promote after a device smoke-test pass (see prior session note: 7 items need real Android+iOS device verification — icon, splash, QR, video posting, mobile Google Maps, share-profile link).
  • iOS path: Firebase/Sign-In config is now genuinely ready (06-19's iOS blockers are closed) — same 3 Criticals apply, plus the device-testing pass, before first TestFlight submission.
```

---

## Test Coverage Gap Analysis

| Test type | Current | Target | Gap |
|-----------|:-------:|:------:|:---:|
| Unit tests (providers) | 5/12 providers | 12/12 | 7 providers (event, group, notification, safe_check, search, trip, user) |
| Widget tests (screens) | 12 shared-widget files + 1 auth screen | core flows + both new management screens | ~50 screens, incl. the 2 fake-action screens |
| Integration tests | 2 files, both 100% skipped | running against emulator in CI | un-skip + wire emulator |
| Test-pattern gap | Contract-style Firestore mirrors only | + widget pump tests with provider-call verification | new pattern needed — see High #4 |
| CI/CD pipeline | Yes (analyze+test gate release builds) | + coverage threshold, blocking format | threshold + format-blocking not enforced |
| Manual smoke test | Yes (`docs/manual-smoke-test.md`) | + device pass for 7 flagged Phase 1+2 items | Android + iOS device testing still pending (separate from this report) |

See `docs/store-readiness-test-plan.md` (updated alongside this report) for the prioritized test list.

---

_Generated by the `store-readiness-audit` Claude skill, this pass cross-verified against live Firebase state (not just repo contents) via the Firebase MCP tools, and used 3 parallel sub-agents for Categories 1-2, 7, and 8. Re-run after the Critical fixes land to re-score._
