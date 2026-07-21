# FlyConnect — Device QA Report

**Date:** 2026-07-21
**Device:** OnePlus Nord N200 5G (DE2118), Android, serial `cdc8bb52`
**Builds tested:** `flutter build apk --debug` (real Firebase) and `-t lib/main_mock.dart` (mock)
**Baseline:** `flutter analyze` → *No issues found*. Every defect below is a runtime/logic defect the analyzer cannot see.

Legend: **[LIVE]** = reproduced on the device with a screenshot. **[CODE]** = verified by reading the source, not executed.

---

## Blockers — must fix before release

### B1. Direct Messages tab crashes completely — ✅ FIXED 2026-07-21
`lib/features/chat/chat_screen.dart:281`

```dart
final names = (chat as dynamic).participantNames;
```

`ChatModel` (`lib/shared/models/models.dart:224`) has no `participantNames` field, no `noSuchMethod`, and `getOrCreateDm` never writes one.

**Observed:** opening Messages → **Direct** renders a full-screen red `NoSuchMethodError: Class 'ChatModel' has no instance getter 'participantNames'`. In a release build this is a grey box. **Every 1:1 conversation is unreachable from the chat list.** The Groups tab works.

**Fix applied:**
- `ChatModel` gained a typed `participantNames: Map<String,String>` field (`fromFirestore` / `toFirestore` round-trip it; legacy docs parse to an empty map).
- Name resolution moved to `ChatModel.displayNameFor(uid)`; the `as dynamic` escape hatch is gone. No `as dynamic` remains anywhere in `lib/`.
- `ChatModel.namesMap(...)` builds the map at DM creation and is used by all three `getOrCreateDm` implementations (real provider, mock provider, repository). Blank names are omitted rather than stored as `''`. The real provider's name lookup is wrapped in try/catch — a failed read degrades the title to "User" instead of blocking chat creation.
- `firestore.rules` needed no change: the `chats` create rule doesn't whitelist fields.

**Second defect found while verifying the fix.** With the crash gone, both DM rows rendered **"Alex Johnson"** — the signed-in user's own name. Cause: `participants.firstWhere((p) => p != uid)` returns `participants.first` when `uid` isn't in the list, and the mock signed-in user's uid was `mock_alex` while every fixture used `user_001`. Two fixes:
- `displayNameFor` now returns `'User'` when the viewer isn't a participant, instead of guessing.
- The mock identities were aligned with the fixtures (`mock_alex`→`user_001`, `mock_sarah`→`user_007`, `mock_biz1`→`biz_001`, `mock_biz2`→`biz_002`). The pre-existing `uid == 'mock_alex' || uid == 'user_001'` checks in `fetchUser` were the tell that this split identity was already known. As a side effect the unread badge now renders, because `unreadCount` is keyed by `user_001`.

**Coverage:** `test/models/chat_model_test.dart`, 10 tests — round-trip, legacy docs, `namesMap` keying, DM/group/non-participant resolution. **Not covered:** the Firestore `set()` plumbing in `getOrCreateDm`. `ChatProvider` and `ChatRepository` both hard-code `FirebaseFirestore.instance`, so they can't be unit-tested without a DI refactor. That write path was verified on-device, not by test. (`ChatRepository` is also dead code — nothing references it.)

**Verified:** `flutter analyze` clean, 368/368 tests pass, and on the OnePlus the Direct tab lists "Maria Chen" and "Priya Patel" with a working unread badge, and the conversation opens correctly.

### B2. Post audience / "Only me" is not enforced **[CODE]**
`real_providers.dart:1325`, feed query at `:880`, `firestore.rules:94`

`createPost` stores `audience` (`Everyone | Connections | Only me`) and `groupId`, but the feed query applies no `where` clause and the rule is `allow read: if isAuth()`. A post marked **Only me** or targeted at a private group appears in every signed-in user's feed. This is a privacy incident, not a cosmetic bug.

### B3. Account deletion is non-atomic and incomplete **[CODE]**
`real_providers.dart:303-361`

- Firestore profile is deleted **before** `user.delete()`. Firebase throws `requires-recent-login` in the common case → profile gone, Auth account alive, user stranded with no recoverable state.
- It wipes `users/{uid}/trips`, but trips live in the **top-level** `trips` collection (`:2043`). Trips, `safeChecks` (with lat/lng), `notifications`, event RSVPs and group memberships all survive deletion.

Both Play and App Store audit deletion completeness, and the in-app dialog promises more than the code does.

---

## High — user-visible breakage

| # | Where | Defect |
|---|---|---|
| H1 **[LIVE]** | `match_screen.dart:40-51` | **"It's a Match!" fires on every single like**, with no mutual-like check. Confirmed on first tap. |
| H2 **[LIVE]** | `match_screen.dart:104` | The match banner **names the wrong person** — `likeUser` removes the liked candidate first, so `candidates.first` is now the *next* card. Liked Maria Chen → banner said "You and James Wright liked each other". |
| H3 **[LIVE]** | `match_screen.dart` banner | The banner **overflows the right screen edge** — text clipped mid-word and the "Send Message" button runs off-screen. |
| H4 **[LIVE]** | `events_screen.dart:101` | `TabBar` has `onTap: (_) {}`. **All / Upcoming / Featured render byte-identical content** — verified by pixel-diffing the screenshots. |
| H5 **[LIVE]** | `events_screen.dart:143` | `SectionHeader(actionLabel: 'See All')` passes no `onAction`. **"See All →" is a dead control** — tapped, nothing changed but the clock. |
| H6 **[LIVE]** | `post_details_screen.dart:269-270` | Options sheet **"Share"** and **"Copy link"** are `onTap: () => Navigator.pop(context)`. Tapped Copy link — sheet closed, no clipboard write, no feedback. `_sharePost` exists at `:26` but is only wired to the toolbar icon. |
| H7 **[LIVE]** | `profile_screen.dart:745` | Profile header says **"47 Posts"** while the grid below says **"No posts yet"** — the grid filters the newest 25 *global* posts by `authorId` instead of querying the user's posts. |
| H8 **[LIVE]** | `chat_screen.dart:245`, `conversation_screen.dart:273` | **Presence is fake.** A green "online" dot on every tile and a hardcoded `'Online'` in the header — shown even for a *group* chat. No presence data is read anywhere. |
| H9 **[CODE]** | `trips_screen.dart` | `/passport/:userId` passes `userId` in, and `widget.userId` is **never referenced** (grep: 0 hits in 273 lines). Opening someone else's passport shows **your own trips**, titled "My Trips", with a live Add button and per-row Delete. |
| H10 **[CODE]** | `real_providers.dart:1189` | `blockUser` writes `users/{me}/blocked/{uid}`, and **nothing reads it** — not the feed, not match candidates. User sees "You will not see their content"; their posts are still there on the next scroll. |
| H11 **[CODE]** | `conversation_screen.dart:181`, `open_chat.dart:47` | Block falls back to `otherUid ?? chatId`, and `OpenChat.withUser` never passes `otherUid`. Blocking from a match/profile chat writes `blocked/{chatDocId}` — **a document id that is not a user**. Nothing is blocked. Report has the identical bug at `:225`. |
| H12 **[CODE]** | `home_screen.dart:198` | `_PostCard` is stateful with per-post state set once in `initState`, built **with no `key`**. The feed prepends new posts → like/save state and counts shift onto the wrong cards and never correct themselves. |
| H13 **[CODE]** | `real_providers.dart:1101` | `deletePost` batches deletion of all comments + likes, but rules only allow their owners to delete them (`firestore.rules:118,124`). One denial fails the whole commit → **a post anyone else liked or commented on can never be deleted**. |
| H14 **[CODE]** | `real_providers.dart:1851` | `loadCandidates` has no try/catch around two Firestore reads. Offline or `permission-denied` leaves `_loading` stuck true → **Match tab is a permanent spinner** with no error and no retry. |
| H15 **[CODE]** | `real_providers.dart:1870` | Candidate query excludes neither already-matched/passed users nor blocked users. **Passed profiles come straight back**, and `passUser` `add()`s a fresh doc per pass (duplicate rows forever). |
| H16 **[CODE]** | `settings_screen.dart:130-141` | All six push toggles are persisted to `users/{uid}.settings` and **read by nobody** — not by any Dart file, not by `functions/src/pushFanout.ts`. Turning off "Messages" changes nothing. |
| H17 **[CODE]** | `nearby_users_screen.dart:135` | Location privacy reads `AuthProvider.currentUser.settings`, but Settings writes via `UserProvider.updateProfile`. `AuthProvider` never refreshes → **turning off location sharing has no effect until app restart**; coordinates keep uploading. |
| H18 **[CODE]** | `firestore.rules:296` | SafeCheck Visibility (Friends / Verified only) is **client-side only**. `safeChecks` is `allow read: if isAuth()` — any signed-in user can read every check-in's status, message, city and lat/lng. |
| H19 **[CODE]** | `analytics_screen.dart:62`, `dashboard_screen.dart:15` | Business analytics iterate the **global** promotions/events collections, not `myPromotions(uid)`. **Business A sees Business B's** deal titles, views, saves and redemptions. |
| H20 **[CODE]** | `analytics_screen.dart:41`, `business_profile_screen.dart:119` | Growth `+12%`, Reach `8,420`, Engagement `4.2%`, Followers `2,840`, Events `3` are **hardcoded literals** presented as real metrics. Only the bar chart carries a "Demo chart" badge. |
| H21 **[CODE]** | `promotion_detail_screen.dart:120` | "Show this QR code at the venue" is a 6×6 `GridView` coloured by `i % 3 == 0`. **It is not a QR code** and encodes nothing. Redemption counters are never incremented anywhere. |
| H22 **[CODE]** | `group_details_screen.dart:461` | Members tab renders `Text('Member ${i+1}')` with the raw uid as subtitle. **Real names are never fetched**, though `GroupProvider.fetchMembers` exists and the business screen uses it. |
| H23 **[CODE]** | `group_details_screen.dart:470`, `event_management_screen.dart:476` | Member "Message" pushes a **fabricated chat id** (`${uid}_dm`, `evt_{id}_{uid}`), bypassing `getOrCreateDm`. Messages land in a chat the recipient isn't a participant of — they never arrive. |
| H24 **[CODE]** | `real_providers.dart:1390`, `:1484` | `watchMessages` has **no limit and no pagination**; `markMessagesRead` `get()`s every unread message and batches them — >500 unread exceeds the batch limit and throws uncaught from `initState`. |
| H25 **[CODE]** | `conversation_screen.dart:378` | `setTyping` fires on **every keystroke** (one Firestore write per character, no debounce) and is **never cleared** on send or dispose — the other party sees "typing…" forever. |

---

## Missing components

| # | What | Evidence |
|---|---|---|
| M1 **[LIVE]** | **Inter font is never bundled.** `app_text_styles.dart` sets `fontFamily: 'Inter'`; the `fonts:` block in `pubspec.yaml` is commented out and `assets/fonts/` contains only a README. The whole app silently renders in Roboto — visible in every screenshot. | `assets/fonts/README.md` |
| M2 **[CODE]** | **Email verification is entirely non-functional.** `/otp` is registered but **no code ever navigates to it** (grep: only the route constant + the `GoRoute`); `sendEmailVerification()` is called only inside that unreachable screen. `signup()` goes straight to `/home`. 100% of accounts are permanently unverified. | `otp_screen.dart`, `app_router.dart:137` |
| M3 **[LIVE]** | **No Chat entry in the bottom nav.** `main_shell.dart:44` maps `/chat` to index 3, but the bar has only 0,1,2,4 and the drawer has no Messages item. On Messages, no tab is highlighted; Chat is reachable only via a small top-bar icon. | `main_shell.dart:19` |
| M4 **[CODE]** | **Match preferences do nothing.** Max Distance and Age Range sliders are saved and never applied by `loadCandidates` (acknowledged in a comment at `:1857`). The Buddy/Dating/Solo tabs all return the identical list — `matchType` is never passed to the query. | `match_preferences_screen.dart:112` |
| M5 **[CODE]** | **Group broadcasts go nowhere.** Writes to `groups/{id}/broadcasts`, which nothing reads. UI claims "members will see it in the group". | `group_management_screen.dart:113` |
| M6 **[CODE]** | **Group chat toggle does nothing.** `chatEnabled` is written and read nowhere else; members keep posting after the owner disables chat. | `group_management_screen.dart:205` |
| M7 **[CODE]** | **RSVP approval workflow has no effect.** RSVP docs carry no `status`, so every attendee shows "pending"; Approve/Decline writes a `status` nothing reads — a declined attendee still sees "Cancel RSVP" and still counts toward `rsvpCount`. | `event_management_screen.dart:229` |
| M8 **[CODE]** | **Stories are mine-only and never expire.** No other user's story is fetched anywhere and there is no 24h expiry, though `StoryViewerScreen` supports multi-user. | `real_providers.dart:711` |
| M9 **[LIVE]** | **Post comment list is absent.** Post detail shows "23" comments and renders none, with no empty state and no `connectionState`/`hasError` handling on the `StreamBuilder`. | `post_details_screen.dart:176` |
| M10 **[CODE]** | `_describeAppleAuthError` is a `// TODO: implement` stub returning `null` — Apple sign-in failures surface Firebase's raw "An internal error has occurred." | `real_providers.dart:646` |
| M11 **[CODE]** | "Resend email" on the reset screen only resets local state; it does not resend. "Help & Support" in the business drawer is `onTap: () => Navigator.pop(context)`. | `forgot_password_screen.dart:217`, `business_shell.dart:182` |
| M12 **[LIVE]** | **Onboarding backgrounds are hotlinked Unsplash URLs.** Slide 3 failed to load on a real network and fell back to a bare gradient; `loadingBuilder` renders a solid dark rectangle with no spinner. 39 remote stock-image URLs ship in `lib/`, including `picsum.photos` on the business profile cover. | `onboarding_screen.dart:22-32` |

---

## Medium / polish

- **Nearby is not nearby** — `nearby_users_screen.dart:176` queries `users limit(20)` with **no geo constraint** and labels the results with a computed distance. Users on other continents appear as nearby.
- **Router guard fails open** — `app_router.dart:125` wraps the entire auth + role check in `catch (_) { }` returning `null` (= allow). Any provider hiccup silently disables all route protection, including `/admin/*`, with no log.
- **Login succeeds but reports failure** — `real_providers.dart:181`: a Firestore error *after* `signInWithEmailAndPassword` succeeded is caught as "Login failed", leaving the user authenticated but stuck on the login screen. Same shape in the Google and Apple paths.
- **Business signup has no step-2 validation** — the name field is only rendered for `role == 'user'`, so a business account can be created with `name: ''` and no category (`signup_screen.dart:466`).
- **RSVP / join counters drift** — `toggleRsvp` and `joinGroup` do read-then-write with no transaction; a double-tap double-increments (`real_providers.dart:1604`, `:1731`).
- **StreamBuilders rebuild their streams** — `conversation_screen.dart:291`, `post_details_screen.dart:174`, `saved_posts_screen.dart:28` construct a fresh stream in `build`, so every `setState` tears down the Firestore listener, blanks the list and re-charges a full read.
- **Message text is cleared before the send is awaited** (`conversation_screen.dart:43`) — a failed send loses the typed text with no retry and no failed-message bubble.
- **Posts and comments never store `authorPhotoUrl`** (`real_providers.dart:1292`) — every post and comment shows a grey initial instead of the author's avatar; OAuth users with a null `displayName` are labelled "User".
- **Pull-to-refresh is fire-and-forget** and resets `_feedLimit` to 25 — the spinner vanishes instantly and a user who tapped "Load more" three times is thrown back to the top.
- **Undisposed controllers** in bottom sheets: `event_management_screen.dart:96` (×3), `nearby_users_screen.dart:447`, `trips_screen.dart:179`. One leak per sheet open. The codebase already fixed this elsewhere by extracting stateful sheets.
- **`setState` after `await` with no `mounted` guard**: `home_screen.dart:278`, `signup_screen.dart:44`, `edit_profile_screen.dart:70`, `create_promotion_screen.dart:35`, `create_event_screen.dart:56`, `edit_profile_details_screen.dart:41`.
- **`/events/create` is unreachable** — shadowed by `/events/:eventId` declared earlier (`app_router.dart:271`), and it maps to the list screen anyway. The same ordering fix was correctly applied to `/promotions/create`.
- **Google sign-in button uses a plain blue "G" glyph**, not the official Google logo — this violates Google's Sign-In branding guidelines and is a known review flag. The Apple button is also shown on Android.
- **Nav icon set is inconsistent** — Match is a full-colour pink PNG next to grey monochrome line icons, and it does not desaturate when inactive.
- **Video upload has no progress or cancel** — `create_post_screen.dart:133` reads the whole file into RAM (`readAsBytes`) then `putData`s it behind a 16px spinner. Large videos look frozen and can OOM on low-end devices.
- **Attendee list is N+1** — `event_management_screen.dart:52` fetches every RSVP then one `users/{uid}` read each. A 500-RSVP event = 501 reads per screen open, unpaginated.

---

## Verified working

Login form validation, password reset screen, group chat send/receive, passport country grid, block/unblock and report *writes*, GDPR "Request My Data", location-permission gating with denied / denied-forever / service-disabled states, Delete Account confirm-typing gate, Terms and Privacy Policy links (both return HTTP 200 at `flyconnect.co`), the Android manifest (deliberate `AD_ID` removal, no legacy storage permissions, correct `queries` block).

---

## Recommended order

1. **B1** — one-line class of bug, kills the entire DM feature.
2. **B2, B3, H18, H10/H11** — privacy and data-deletion correctness; these are store-review and GDPR exposure, not polish.
3. **H1–H3, H4–H7, H22** — the most visible "this app is unfinished" defects; all are small, local fixes.
4. **M1, M2** — bundle Inter; wire up or remove the OTP screen.
5. Everything else.

The recurring root cause worth a team conversation: several features write to Firestore and are read by nothing (`blocked`, `broadcasts`, `chatEnabled`, push settings, RSVP `status`, `audience`). The write half shipped with a success snackbar; the read half never did. A "does anything consume this field?" grep should be part of the definition of done.
