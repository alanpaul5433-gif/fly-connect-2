# Google Play Data Safety Form — Answers

Complete this in **Play Console → Policy → App content → Data safety**. The answers below map directly to what FlyConnect actually does in code.

---

## Section 1: Data collection and security

### Does your app collect or share any of the required user data types?
✅ **Yes**

### Is all of the user data collected by your app encrypted in transit?
✅ **Yes** — all data flows over HTTPS/TLS via Firebase SDKs. AndroidManifest has no `usesCleartextTraffic`.

### Do you provide a way for users to request that their data be deleted?
✅ **Yes** — via Settings → Delete Account, which purges the user doc, subcollections (savedPosts, blocked, following, followers, trips), soft-deletes authored posts, and removes the Firebase Auth user. See `lib/shared/providers/real_providers.dart → AuthProvider.deleteAccount()`.

---

## Section 2: Data Types Collected

### Personal info

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| Name | ✅ | ❌ | App functionality, Account management | No |
| Email address | ✅ | ❌ | Account management, Communications | No |
| User IDs | ✅ | ❌ | App functionality | No |
| Address | ❌ | — | — | — |
| Phone number | ✅ | ❌ | App functionality (optional profile field), Account recovery | Yes |
| Race and ethnicity | ❌ | — | — | — |
| Political or religious beliefs | ❌ | — | — | — |
| Sexual orientation | ❌ | — | — | — |
| Other info | ✅ | ❌ | App functionality (airline, position, bio) | Yes |

### Financial info

❌ None collected. FlyConnect is free and does not process payments.

### Health and fitness

❌ None collected.

### Messages

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| Emails | ❌ | — | — | — |
| SMS or MMS | ❌ | — | — | — |
| Other in-app messages | ✅ | ❌ | App functionality (DMs and group chats) | No (required for chat) |

### Photos and videos

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| Photos | ✅ | ❌ | App functionality (profile pics, post photos, stories) | Yes |
| Videos | ❌ (not yet implemented) | — | — | — |

### Audio files

❌ None collected.

### Files and docs

❌ None collected.

### Calendar

❌ None collected.

### Contacts

❌ None collected. _(The Info.plist mentions a future Contacts permission — if that ships, update this.)_

### App activity

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| App interactions | ✅ | ❌ | Analytics (Firebase Analytics) | No |
| In-app search history | ❌ | — | — | — |
| Installed apps | ❌ | — | — | — |
| Other user-generated content | ✅ | ❌ | App functionality (posts, comments, reports) | No |
| Other actions | ✅ | ❌ | App functionality (likes, saves, RSVPs) | No |

### Web browsing

❌ None collected.

### App info and performance

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| Crash logs | ✅ | ❌ | Analytics, App functionality (Firebase Crashlytics) | No |
| Diagnostics | ✅ | ❌ | Analytics (Firebase Analytics) | No |
| Other app performance data | ❌ | — | — | — |

### Device or other IDs

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| Device or other IDs | ✅ | ❌ | Analytics, App functionality (FCM push token) | No |

### Location

| Data type | Collected | Shared | Purpose | Optional? |
|-----------|:---------:|:------:|---------|:---------:|
| Approximate location | ✅ | ❌ | App functionality (Nearby Users, SafeCheck) | **Yes — user-granted runtime permission** |
| Precise location | ✅ | ❌ | App functionality (SafeCheck accuracy) | **Yes — user-granted runtime permission** |

---

## Section 3: Purposes — Declarations

For each "Yes" above, the purpose categories declared are:

- **App functionality:** required for core features (auth, posts, chats, matches, SafeCheck)
- **Analytics:** Firebase Analytics app_open events + Firebase Crashlytics crash logs
- **Account management:** signup, login, password reset, account deletion

**Not selected** (none of these apply):
- ❌ Advertising or marketing
- ❌ Fraud prevention, security, and compliance _(we use Firebase's built-in; no custom fraud ingestion)_
- ❌ Personalization
- ❌ Developer communications _(account emails come from Firebase, not us)_

---

## Section 4: Security practices

- ✅ **Data is encrypted in transit** (HTTPS/TLS)
- ✅ **Users can request data deletion** (in-app Delete Account + email request to privacy@flyconnect.co)
- ✅ **Committed to the Play Families Policy** — FlyConnect is targeted at users 16+ only. Signup does not allow age declarations below 16.
- ✅ **Independent security review** — declare only if you actually pay for a third-party audit; otherwise leave unchecked.

---

## Section 5: Family-targeted?

❌ **No.** FlyConnect is designed for aviation professionals (16+).

Select **"No, my app isn't primarily child-directed"** and **"Target age group: 16+"**.

---

## How to complete in Play Console

1. Play Console → your app → **Policy** → **App content** → **Data safety**
2. Click **Start** (or **Manage**)
3. Work through the sections in order
4. Copy the answers above into the matching fields
5. Before submitting: read each purpose declaration aloud to make sure it matches reality. Misdeclarations can trigger a review-team follow-up.

**Tip:** Play Console saves progress. You don't have to finish in one sitting.

---

## Regression checklist (review before every app update)

- Did we add a new SDK that collects data? → update the form
- Did we add a payment flow? → check "Financial info"
- Did we add age gating below 16? → reconsider "Family-targeted"
- Did we add video uploads? → check "Videos"
- Did we change the consent model? → update Section 1
