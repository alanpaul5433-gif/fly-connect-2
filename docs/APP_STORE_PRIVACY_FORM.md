# FlyConnect — Apple App Privacy ("Nutrition Label") form (code-grounded draft)

**App:** `com.urbansyncinnovations.flyconnect` · **Generated:** 2026-07-17 · **Backend:** Firebase (`flyconnect-ab4f2`)
**Companion to:** `docs/DATA_SAFETY_FORM.md` (the Google Play equivalent — same underlying facts, different taxonomy/questions). Cross-check both before submitting either store.
**Method:** derived from the actual code — every row cites where the collection happens. Transcribe into App Store Connect → App Privacy.

> **Golden rule used throughout:** Firebase (Firestore/Storage/Auth/Analytics/Crashlytics/FCM) is FlyConnect's own backend service provider, not a "third party" in Apple's tracking sense. `pubspec.yaml` has **no ad SDK, no attribution SDK, no data-broker integration** — confirmed by dependency audit. So for every row below: **Used to Track You = No**. "Linked to your identity" = **Yes** almost everywhere, because virtually all data is written under the signed-in user's Firebase Auth `uid` (the one exception called out below).

---

## 1. How to answer Apple's 3 questions per data type

For each type you select as collected, Apple asks:
1. **Is this data collected?** → per the table below
2. **Is this data linked to the user's identity?** → **Yes**, unless noted
3. **Is this data used to track the user?** → **No** for everything (no cross-app/cross-site tracking, no data broker, no ad network)

Purpose (Apple's picklist: *App Functionality / Analytics / Product Personalization / Developer's Advertising or Marketing / Third-Party Advertising / Other Purposes*) is listed per row. **Never select an advertising purpose — there is none.**

---

## 2. Data types to select — YES

### Contact Info
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **Name** | Yes | App Functionality | `users/{uid}.name`, `models.dart:8` — set at signup/Google Sign-In, shown on every profile/post. |
| **Email Address** | Yes | App Functionality | `private/data.email` (owner-only subdoc) — used for auth/login. |
| **Phone Number** | Yes (optional) | App Functionality | `private/data.phone` — optional profile field. |

**Not collected:** Physical Address (no street/mailing address field — `city`/`state` are coarse profile text, not a Contact-Info address), Other User Contact Info.

### Location
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **Precise Location** | Yes (optional) | App Functionality | `geolocator`, `location_service.dart` — only when the user opens Nearby/SafeCheck **and** the `shareLocation` setting is on (H-4); un-fuzzed when `approxLocationOnly` is off. |
| **Coarse Location** | Yes (optional) | App Functionality | Same path, fuzzed to ~1.1 km when `approxLocationOnly` is on. |

### User Content
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **Emails or Text Messages** | Yes | App Functionality | In-app chat: `MessageModel.text`, `models.dart:281` — `chats/{id}/messages`. Only if the user chats; not read/scanned for any other purpose. |
| **Photos or Videos** | Yes (optional) | App Functionality | Posts (`mediaUrls`), stories, avatar, event cover images, chat image attachments — `user_uploads/{uid}/{posts,stories,events,chat}/…`. User-initiated only. |
| **Other User Content** | Yes (optional) | App Functionality | Bio, hobbies, passport stamps, travel history, group/event descriptions, comments, report reasons — all user-authored profile/UGC fields. |

**Not collected:** Audio Data (video posts may carry an audio track, but there is no standalone voice-recording feature — declare under Photos/Videos only, same call as the Play form), Gameplay Content, Browsing History, Search History (search queries run against Firestore live and are **not persisted** — nothing to declare unless that changes), Customer Support (reports are user-generated content, not a ticketing system — covered under Other User Content above).

### Identifiers
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **User ID** | Yes | App Functionality | Firebase Auth UID — primary key for every collection. |
| **Device ID** | Yes | App Functionality | FCM registration token, `private/data.fcmToken` (`notification_service.dart:158`) — delivers push for likes/comments/follows/matches/RSVPs/messages/business content. Owner-only subdoc; not an advertising ID (no `AD_ID` permission — removed per M-9). |

**Not collected:** Purchases (no `in_app_purchase` dependency — confirmed, FlyConnect has no payment/IAP feature).

### Usage Data
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **Product Interaction** | Yes | Analytics | Firebase Analytics `logAppOpen()` only (`main.dart:57`) — no custom events, no user-property mapping. |

**Not collected:** Advertising Data (no ad SDK), Other Usage Data.

### Diagnostics
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **Crash Data** | Yes | App Functionality, Analytics | Firebase Crashlytics, disabled in debug builds (`main.dart:42-50`). |
| **Performance Data** | Yes | Analytics | Crashlytics/Analytics diagnostic metadata accompanying crash reports. No standalone `firebase_performance` dependency — confirmed absent. |

**Not collected:** Other Diagnostic Data.

### Other Data
| Type | Linked? | Purpose | Code |
|---|:--:|---|---|
| **Date of birth** *(bucket under Apple's "Other Data")* | Yes | App Functionality, Fraud/security/compliance | `private/data.dob` + `ageVerifiedAt` — collected once at signup solely to enforce the 18+ age gate (`signup_screen.dart:24-44,159-164`). Owner-only subdoc, never shown to other users. |

---

## 3. Explicitly NOT collected (leave unselected)

- **Health & Fitness** (Health, Fitness) — no HealthKit/Motion&Fitness API, no dependency.
- **Financial Info** (Payment Info, Credit Info, Other Financial Info) — no payment/IAP feature. Business-account `ein`/`licenseNumber`/`verificationDocs` fields exist in the admin verification screen's *read* path (`admin_business_verification_page.dart:367-370`) but **no signup or client flow ever writes them** (confirmed by grep — same gap already flagged in `docs/QA_AUDIT_REPORT.md`'s M-3 entry). Nothing to declare today; **revisit this row if an in-app business-verification submission flow ever ships.**
- **Sensitive Info** — no race/ethnicity, sexual orientation, religion, union membership, political opinion, genetic, or biometric fields anywhere in `models.dart` (confirmed by grep — `matchType` is a content-preference filter ("all"), not an orientation/identity field).
- **Contacts** — no address-book/contacts-picker access.
- **Surroundings** (Environment Scanning) — no AR/ARKit dependency.
- **Body** (Hands, Head) — no motion-capture/AR dependency.
- **Audio Data** — no standalone voice-recording feature (no `record`/audio-capture dependency beyond video's own audio track, declared under Photos/Videos).
- **Advertising Data / Advertising ID** — no ad SDK; `AD_ID` permission already removed.
- **Anything used for tracking** — no cross-app/cross-site data sharing exists anywhere in the codebase.

---

## 4. Cross-checks before you submit

1. **Privacy policy URL** must be live and cover exactly these data types → `https://flyconnect.co/privacy-policy/` (same URL used for the Play submission — re-verify HTTP 200 at submit time).
2. **Account deletion**: Apple requires the same in-app path Play does — `deleteAccount()` (`real_providers.dart:288`) already satisfies this; a web-accessible deletion URL is still an open item (see `docs/QA_AUDIT_REPORT.md` remediation roadmap).
3. **Consistency with the Play Data Safety form** (`docs/DATA_SAFETY_FORM.md`): both forms should agree on what's collected — they were derived from the same code pass. If you change one after this date, update the other.
4. **Permissions ↔ declared-data parity**: Info.plist location/camera/photo-library/notification usage strings should each map to one of the "YES" rows above — no orphan permission strings (the unused `NSUserTrackingUsageDescription` was already removed, M-9).
5. **Age rating**: signup enforces an 18+ DOB gate (`signup_screen.dart`) — keep the App Store age rating questionnaire (UGC, user-to-user communication, unrestricted web access if any) consistent with 17+/adult content settings, matching the Play content-rating answer.
