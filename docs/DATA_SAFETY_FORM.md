# FlyConnect — Google Play Data Safety Form (code-grounded draft)

**App:** `com.urbansyncinnovations.flyconnect` · **Generated:** 2026-07-16 · **Backend:** Firebase (`flyconnect-ab4f2`)
**Method:** derived from the actual code — every row below cites where the collection happens. Transcribe these answers into Play Console → Policy → App content → **Data safety**.

> **Golden rule used throughout:** Firebase (Firestore/Storage/Auth/Analytics/Crashlytics/FCM) is *your own backend service provider (processor)*, not a third party. Per Google's own definition, sending data to a processor is **collection, not sharing**. So every data type below is **Collected = Yes, Shared = No**. There is **no** ad SDK, attribution SDK, or third-party analytics SDK in the app (`pubspec.yaml` audited — none present), and **no data is sold or used for advertising**.

---

## 1. Top-level questions

| Question | Answer | Why (code) |
|---|---|---|
| Does your app collect or share any of the required user data types? | **Yes** | Firestore/Storage/Auth store user profile, UGC, etc. |
| Is all of the user data collected by your app encrypted in transit? | **Yes** | All traffic is Firebase SDK → Google over TLS/HTTPS by default; no plaintext endpoints. |
| Do you provide a way for users to request that their data be deleted? | **Yes** | In-app `deleteAccount()` (`real_providers.dart:288`) wipes the user doc + `private/data` + subcollections and anonymizes posts. Also document the account-deletion URL/steps in the listing. |
| Is your app designed for families / does it target children? | **No — 18+** | Signup enforces an 18+ age gate via DOB (`signup_screen.dart:24-44,159-164`). Set content rating & target audience to adults accordingly. |

---

## 2. Data types — collection matrix

For every row: **Shared = No**, **Processed ephemerally = No** (data is persisted in Firestore/Storage), unless noted. "Optional" = the app works without it / user controls it; "Required" = collected automatically or mandatory at signup.

### Location
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **Approximate location** | Yes | **Optional** | App functionality | `lat`/`lng` written **only** when the `shareLocation` setting is ON; fuzzed to ~1.1 km when `approxLocationOnly` is ON (`nearby_users_screen.dart`, `location_service.dart` — H-4). Powers Nearby + SafeCheck. |
| **Precise location** | Yes | **Optional** | App functionality | Same path, un-fuzzed, when `approxLocationOnly` is OFF. Runtime OS permission required; denial → honest empty state, never a fake coordinate. |

> If you want to simplify review: the app never *requires* location — declare both as optional and user-toggleable.

### Personal info
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **Name** | Yes | Required | App functionality; Account management | `users/{uid}.name` at signup (`real_providers.dart` signup); also from Google/Apple sign-in. Publicly visible (social profile). |
| **Email address** | Yes | Required | App functionality; Account management | `users/{uid}/private/data.email` (owner-only subdoc, H-2). Used for auth/login. |
| **Phone number** | Yes | **Optional** | App functionality; Account management | `private/data.phone` — optional profile field. |
| **User IDs** | Yes | Required | App functionality; Account management | Firebase Auth UID; used as the key for all user data. |
| **Other info (Date of birth)** | Yes | Required | App functionality; Fraud prevention, security & compliance | `private/data.dob` + `ageVerifiedAt` — collected once at signup solely to enforce the 18+ gate (`signup_screen.dart`). Owner-only. |

> **Not collected:** race/ethnicity, political/religious beliefs, sexual orientation, address, financial info, health/fitness data. (Airline/airport/position/city/state/bio/hobbies are optional *profile* fields → declare under **App activity → Other user-generated content**, not as sensitive personal info.)

### Messages
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **In-app messages** | Yes | **Optional** | App functionality | `chats/{id}/messages` (`text` + optional `mediaUrl`), `models.dart:272`. Only if the user chats. Not scanned/used for any other purpose. |

### Photos and videos
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **Photos** | Yes | **Optional** | App functionality | `user_uploads/{uid}/{posts,stories,events}/…`, `profile_photos/{uid}/avatar.png` (`real_providers.dart:687,710,1197,1565`). User-initiated posts/stories/avatar/event covers. |
| **Videos** | Yes | **Optional** | App functionality | `user_uploads/{uid}/posts/*.mp4|mov` (`real_providers.dart:1222`). User-recorded/picked video posts (may contain audio — the iOS mic permission exists solely for in-app video capture; no standalone voice recording). |

### App activity
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **App interactions** | Yes | Required | Analytics | Firebase Analytics `logAppOpen()` only (`main.dart:57`) — no custom events, no user properties, no ID mapping. |
| **Other user-generated content** | Yes | **Optional** | App functionality | Posts, stories, comments, bio, profile fields (airline/airport/position/city/state/hobbies), passport stamps, travel history, follows. All user-created. |

> **In-app search history:** user search queries (`real_providers.dart:2060`) are executed against Firestore but **not stored** as history → do not declare unless you later persist them.

### App info and performance
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **Crash logs** | Yes | Required | Analytics | Firebase Crashlytics (`main.dart:42-50`); disabled in debug (`setCrashlyticsCollectionEnabled(!kDebugMode)`). |
| **Diagnostics** | Yes | Required | Analytics | Crashlytics performance/diagnostic data accompanying crash reports. |

### Device or other IDs
| Data type | Collected | Required? | Purposes | Code / notes |
|---|:--:|---|---|---|
| **Device or other IDs** | Yes | Required | App functionality | FCM registration token stored at `private/data.fcmToken` (`notification_service.dart:158`) to deliver transactional push (likes/comments/follows/matches/RSVPs/messages via the C-3 Cloud Functions). Owner-only. **No advertising ID** — `AD_ID` permission was removed (per release hardening). |

---

## 3. Explicitly NOT collected (leave unchecked)

- Financial info (no payments/IAP in the app)
- Health and fitness
- Contacts (no contacts-book access)
- Calendar
- Web browsing history
- Installed apps / other apps on device
- Audio → **Voice or sound recordings** (video capture only; declare as Videos)
- SMS/call log
- Advertising ID / advertising or marketing use of any data
- Any data **sold** or **shared with third parties**

---

## 4. Per-type answer defaults (apply to every "Yes" row)

When Play Console asks these for each data type, unless the table above overrides:

- **Is this data collected, shared, or both?** → **Collected** (Shared = No everywhere — Firebase is a processor).
- **Is this data processed ephemerally?** → **No** (persisted in Firestore/Storage). *(Exception: none here are ephemeral-only.)*
- **Is this data required or can users choose?** → per the "Required?" column above.
- **Why is this data collected?** → per the "Purposes" column. Never select *Advertising or marketing*.

---

## 5. Cross-checks before you submit

1. **Privacy policy URL** must be live and cover exactly these data types → `https://flyconnect.co/privacy-policy/` (re-verify HTTP 200 at submit time — see launch-plan note on the intermittent Hostinger bot-challenge).
2. **Account deletion**: Play now wants both an in-app path (✅ `deleteAccount()`) *and* a web-accessible deletion request URL/instructions — add one if not present.
3. **Permissions ↔ Data Safety parity**: declared runtime permissions (location, camera/photos, notifications) all map to a declared data type above — no orphan permissions (ATT string already removed, M-9).
4. **Content rating questionnaire** must reflect 18+, UGC, and user communication (chat) — keep it consistent with this form.
