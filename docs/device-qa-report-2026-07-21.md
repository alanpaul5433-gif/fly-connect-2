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

### B2. Post audience / "Only me" is not enforced — ✅ FIXED 2026-07-21
`real_providers.dart:1325`, feed query at `:880`, `firestore.rules:94`

`createPost` stored `audience` (`Everyone | Connections | Only me`) and `groupId`, but the feed query applied no `where` clause and the rule was `allow read: if isAuth()`. A post marked **Only me** appeared in every signed-in user's feed.

**Proven, not inferred.** A rules test against the Firestore emulator confirmed Bob could read Alice's "Only me" post, and that the shipped unconstrained feed query succeeded.

**Fix applied:**
- `firestore.rules` — posts are readable only when `audience == 'Everyone'`, the reader is the author, or the reader is an admin.
- `PostModel` gained a typed `audience` field (defaults to `'Everyone'`, round-trips); `createPost` writes it through the model instead of bolting `data['audience']` onto the map.
- The feed query now constrains on `audience == 'Everyone'` — **required, not an optimisation**: Firestore fails an entire query when any matched document is denied, so without the `where` the feed returns `permission-denied` rather than over-fetching.
- Saved posts moved from `whereIn(documentId)` to per-document gets. A `whereIn` on ids proves neither condition, so the batched form would have failed wholesale; single-doc gets let a since-privatised post be skipped instead of breaking the screen.
- `Connections` removed from the audience dropdown — it was implemented nowhere and cannot be enforced in rules without a denormalised `visibleTo` array. Better absent than presented as a working privacy control.
- New composite index `posts(audience, createdAt)`, caught by the existing `firestore_indexes_lint_test` registry.

**Deploy order matters.** A post with no `audience` field fails the rule and becomes invisible to everyone but its author. Run the backfill *before* deploying the rules:
```
node scripts/backfill-post-audience.js --dry-run
node scripts/backfill-post-audience.js
firebase deploy --only firestore:rules,firestore:indexes
```
A rules test pins this behaviour so the migration can't be quietly forgotten.

**Coverage:** `functions/test/rules/posts.rules.test.ts`, 11 tests, run via `npm run test:rules` (wraps `firebase emulators:exec`). Needs **JDK 21+** — firebase-tools refuses older runtimes, and the default JDK here is 17; run with `export JAVA_HOME=$(/usr/libexec/java_home -v 21)`.

**Still open, deliberately.** Group posts remain readable by non-members: a post with `groupId` set and `audience: 'Everyone'` is public by this rule. Enforcing group membership needs a `get()` on the group document per read, which is a separate design decision. This fix closes the "Only me" leak, not group privacy.

**Also note:** viewing *another* user's posts by `authorId` is now denied unless the query also constrains `audience == 'Everyone'`. That matters when H7 (the profile grid) is fixed properly — the query must carry both clauses.

### B3. Account deletion — ✅ FIXED 2026-07-21 (and it was worse than reported)
`real_providers.dart:303-361`, `firestore.rules:57`

The original report said deletion was non-atomic and incomplete. Writing rules tests revealed something more serious:

> **Account deletion has never worked at all.** `match /users/{userId}` carried `allow delete: if isAdmin();`, and `deleteAccount()` deleted the user document as its *first* write. Every attempt failed with permission-denied on step one and surfaced as the generic "Could not delete account: …". A second rule gap blocked clearing `users/{uid}/followers/*`, whose write rule required `isOwner(followerId)` — never the profile owner.

Play has required in-app account deletion since May 2024; the App Store requires it too. This is a submission blocker, not a defect.

**Fix applied:**
- `firestore.rules` — `users/{userId}` is now `allow delete: if isOwner(userId) || isAdmin()`. The `followers` rule was split: `create, update` stay follower-only so a follow still can't be forged, while `delete` also permits the profile owner, which account erasure requires.
- Erasure extracted to `lib/shared/utils/account_deletion.dart` (`purgeUserData(db, uid)`), following the existing `admin_gdpr_logic.dart` pattern of taking `db` as a parameter so it can be tested against `fake_cloud_firestore`. The old code was untestable, which is why nobody noticed it deleted a subcollection that does not exist.
- **Wrong path fixed:** it wiped `users/{uid}/trips`; trips are top-level, keyed by `userId`. Now also erases `safeChecks` (which carry lat/lng), `notifications` and the `stories/{uid}` document.
- **Ordering reversed.** `users/{uid}` is deleted **last**, so a mid-flight failure leaves a recoverable account rather than an authenticated user with no profile.
- **Pre-flight freshness gate.** `user.metadata.lastSignInTime` is checked *before* anything is erased; a stale session now returns "Nothing has been deleted" instead of destroying data on a call Firebase was always going to refuse.
- Mirrored follow entries (`users/{followed}/followers/{uid}`) are removed, so a departing user stops being counted as a follower everywhere they followed.

**Coverage:** `test/shared/account_deletion_test.dart` (10 tests — completeness per collection, other users untouched, posts anonymised not destroyed, idempotent re-run) and `functions/test/rules/account-deletion.rules.test.ts` (10 rules tests proving every write the client must make is permitted, and that deleting *someone else's* profile or post still fails).

**Known limitation, not fixed.** `users/{follower}/following/{uid}` — written by people who followed the departing user — is owned by that other user and cannot be deleted from the client under any correct rule. Those entries are orphaned. Cleaning them needs a privileged Cloud Function on user delete. Note that the original code's doc-comment claimed such a function already existed "in production"; **it does not** — there is no user-delete trigger anywhere in `functions/src`.

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
| H9 ✅ **FIXED** | `trips_screen.dart` | `/passport/:userId` passes `userId` in, and `widget.userId` is **never referenced** (grep: 0 hits in 273 lines). Opening someone else's passport shows **your own trips**, titled "My Trips", with a live Add button and per-row Delete. See below. |
| H10 ✅ **FIXED** | `real_providers.dart:1189` | `blockUser` writes `users/{me}/blocked/{uid}`, and **nothing reads it** — not the feed, not match candidates. User sees "You will not see their content"; their posts are still there on the next scroll. See below. |
| H11 ✅ **FIXED** | `conversation_screen.dart:181`, `open_chat.dart:47` | Block falls back to `otherUid ?? chatId`, and `OpenChat.withUser` never passes `otherUid`. Blocking from a match/profile chat writes `blocked/{chatDocId}` — **a document id that is not a user**. Nothing is blocked. Report has the identical bug at `:225`. See below. |
| H12 **[CODE]** | `home_screen.dart:198` | `_PostCard` is stateful with per-post state set once in `initState`, built **with no `key`**. The feed prepends new posts → like/save state and counts shift onto the wrong cards and never correct themselves. |
| H13 ✅ **FIXED** | `real_providers.dart:1101` | `deletePost` batches deletion of all comments + likes, but rules only allow their owners to delete them (`firestore.rules:118,124`). One denial fails the whole commit → **a post anyone else liked or commented on can never be deleted**. See below. |
| H14 ✅ **FIXED** | `real_providers.dart:1851` | `loadCandidates` has no try/catch around two Firestore reads. Offline or `permission-denied` leaves `_loading` stuck true → **Match tab is a permanent spinner** with no error and no retry. See below. |
| H15 ✅ **FIXED** | `real_providers.dart:1870` | Candidate query excludes neither already-matched/passed users nor blocked users. **Passed profiles come straight back**, and `passUser` `add()`s a fresh doc per pass (duplicate rows forever). See below. |
| H16 **[CODE]** | `settings_screen.dart:130-141` | All six push toggles are persisted to `users/{uid}.settings` and **read by nobody** — not by any Dart file, not by `functions/src/pushFanout.ts`. Turning off "Messages" changes nothing. |
| H17 ✅ **FIXED** | `nearby_users_screen.dart:135` | Location privacy reads `AuthProvider.currentUser.settings`, but Settings writes via `UserProvider.updateProfile`. `AuthProvider` never refreshes → **turning off location sharing has no effect until app restart**; coordinates keep uploading. See below. |
| H18 ✅ **FIXED** | `firestore.rules:296` | SafeCheck Visibility (Friends / Verified only) was **client-side only**. `safeChecks` was `allow read: if isAuth()` — any signed-in user could read every check-in's status, message, city and lat/lng. See below. |
| H19 ✅ **FIXED** | `analytics_screen.dart:62`, `dashboard_screen.dart:15` | Business analytics iterate the **global** promotions/events collections, not `myPromotions(uid)`. **Business A sees Business B's** deal titles, views, saves and redemptions. See below. |
| H20 **[CODE]** | `analytics_screen.dart:41`, `business_profile_screen.dart:119` | Growth `+12%`, Reach `8,420`, Engagement `4.2%`, Followers `2,840`, Events `3` are **hardcoded literals** presented as real metrics. Only the bar chart carries a "Demo chart" badge. |
| H21 **[CODE]** | `promotion_detail_screen.dart:120` | "Show this QR code at the venue" is a 6×6 `GridView` coloured by `i % 3 == 0`. **It is not a QR code** and encodes nothing. Redemption counters are never incremented anywhere. |
| H22 **[CODE]** | `group_details_screen.dart:461` | Members tab renders `Text('Member ${i+1}')` with the raw uid as subtitle. **Real names are never fetched**, though `GroupProvider.fetchMembers` exists and the business screen uses it. |
| H23 **[CODE]** | `group_details_screen.dart:470`, `event_management_screen.dart:476` | Member "Message" pushes a **fabricated chat id** (`${uid}_dm`, `evt_{id}_{uid}`), bypassing `getOrCreateDm`. Messages land in a chat the recipient isn't a participant of — they never arrive. |
| H24 ✅ **FIXED** | `real_providers.dart:1390`, `:1484` | `watchMessages` has **no limit and no pagination**; `markMessagesRead` `get()`s every unread message and batches them — >500 unread exceeds the batch limit and throws uncaught from `initState`. See below. |
| H25 **[CODE]** | `conversation_screen.dart:378` | `setTyping` fires on **every keystroke** (one Firestore write per character, no debounce) and is **never cleared** on send or dispose — the other party sees "typing…" forever. |

---

### H18. SafeCheck visibility enforced only in Dart — ✅ FIXED 2026-07-21
`firestore.rules` (safeChecks), `SafeCheckProvider`, `SafeCheckModel`

The setting offered Everyone / Friends Only / Verified Users, but the rule was `allow read: if isAuth() && isNotBanned()` and the filtering happened while rendering. Any signed-in user could read every check-in document directly — status, free-text message, city, and precise lat/lng. On a personal-safety feature, that setting is the entire point. Proven by rules test before fixing.

**Fix applied:**
- Visibility is denormalised onto each check-in (`visibility`, plus `visibleTo` for the Friends case) and enforced in `firestore.rules`. Four branches: `all`, author, `verified` (checked against the **reader's** own `isVerified` via the new `isVerifiedUser()` helper — a property of the caller, so it stays cheap), and `friends` (reader present in `visibleTo`).
- `SafeCheckProvider` replaced its single unconstrained `orderBy(createdAt).limit(100)` scan — now rejected outright — with **one constrained subscription per branch the viewer is entitled to**, merged and deduped client-side. The `verified` branch is only subscribed when the viewer is actually verified; querying it otherwise would be denied and take the stream down with it.
- `visibleTo` is captured from the author's followers at write time. Staleness is bounded by the existing 24h expiry — the reason this denormalisation is acceptable here but was rejected for posts.
- Friends audience **fails closed**: if the follower read fails, `visibleTo` is empty, so the check-in is hidden from everyone but its author.
- Three new composite indexes, all caught by the index lint registry.

**No backfill needed** — unlike B2. Check-ins carry a 24h `expiresAt`, so documents written before `visibility` existed age out on their own. A rules test pins that they're author-only until then.

**Coverage:** `functions/test/rules/safechecks.rules.test.ts` (14 tests) and `test/models/safe_check_model_test.dart` (5 tests). One test records a sharp edge worth knowing: an `array-contains` on `visibleTo` **alone** is denied — the query must pin `visibility == 'friends'` as well, or Firestore can't prove the branch.

**Not covered by test:** the provider's multi-subscription merge. `SafeCheckProvider` hard-codes `FirebaseFirestore.instance`, the same DI limitation as elsewhere. The query *shapes* it issues are covered by the rules tests; the merge/dedupe logic is not.

### H10 / H11. Blocking that didn't block — ✅ FIXED 2026-07-21 (three defects, not one)
`firestore.rules` (blocked), `block_list.dart`, `PostProvider`, `MatchProvider`, `nearby_users_screen.dart`, `open_chat.dart`, `conversation_screen.dart`, `ChatModel`

Blocking wrote a document, showed "You will not see their content", and changed nothing. Investigating it surfaced two further defects underneath the reported one.

**1. Nothing consumed the block list (H10).** The feed and match candidates never read `users/{me}/blocked`. Profile and Nearby did, so this wasn't total — but the feed is where a blocked person is actually seen.

**2. The reverse direction was structurally impossible, not just denied.** Nearby *tried* to hide users who had blocked *me*:

```dart
collectionGroup('blocked').where(FieldPath.documentId, isEqualTo: myUid)   // throws
```

On a collection group query `documentId()` is compared against a **full document path**, so a bare uid raises `FirebaseError: ... 'victim' is not [a valid path] because it has an odd number of segments`. It threw on every call, and `catch (_) {/* fail open */}` turned that into "show everyone". No rules change alone could have fixed it: the blocked uid existed only as the **document id**, and collection group queries cannot filter on ids. The uid had to become a field first.

**3. Block/Report targeted a chat id (H11).** `OpenChat.withUser` had `otherUid` in hand and never put it in the route, so `conversation_screen`'s `otherUid ?? chatId` fallback wrote `blocked/{chatDocId}` and filed reports of `targetType: 'user'` pointing at a non-existent user.

**Fix applied:**
- `blockUser` now denormalises `blockedUid` alongside the document id, which is what makes the reverse lookup expressible at all.
- `firestore.rules` gained a second read clause plus a **`match /{path=**}/blocked/{blockedId}`** block. The wildcard is required: a nested path rule does **not** grant collection group access, so the query failed `No matching allow statements` even though a direct `get()` on the same document succeeded. Reads are admitted only for a doc that names you; the rest of the list stays private and **writes stay owner-only**, so being blocked grants no power to unblock yourself.
- New `lib/shared/utils/block_list.dart` — `fetchBlockedUids` (union of both directions, self-block removed) and `withoutBlocked`. Takes `db` as a parameter, the `account_deletion.dart` pattern, because the providers hard-code `FirebaseFirestore.instance`.
- Feed filters on every snapshot; `blockUser` also filters in place and notifies, since blocking mutates no post document and the live listener would otherwise not re-emit until a cold start. `_feedHasMore` is now measured on the **raw** page, not the filtered list, or pagination would stall.
- Match candidates filter both directions. Nearby's two swallowed reads became one call whose failure is recorded.
- `ChatModel.otherUidFor` replaces the bare `firstWhere` in the chat list — the same trap as B1's second bug, but here the wrong answer would **block or report an uninvolved third party**. Returns null for groups, non-participants and self-DMs.
- Block/Report are hidden when the other party is unknown, rather than acting on a wrong id.

**Failure policy — this is a reversal.** These paths previously failed *open*. They now fail *closed*: an unreadable block list means the feed shows an error, the match deck comes back empty, and Nearby refuses to render. Showing someone the exact person they blocked is worse than showing them an error, and a swipe is an irreversible social action. The one deliberate exception is a transient failure *after* a successful load, which keeps the last known set rather than discarding it.

**Coverage:** `functions/test/rules/blocked.rules.test.ts` (13 tests) and `test/shared/block_list_test.dart` (13 tests), plus 6 new `ChatModel.otherUidFor` tests. RED was watched first and earned its keep — it produced the `documentId()` error that redirected the whole approach.

**Backfill:** `scripts/backfill-blocked-uid.js` (`--dry-run` first). Unlike B2 this is **not** a deploy prerequisite — the new rule only grants reads, so ordering can't break anything. Until it runs, old blocks stay half-enforced: filtered from the blocker's own view (by document id), not yet from the reverse direction. A rules test pins that legacy docs stay unreadable meanwhile, so the gap under-hides rather than exposing anything.

**Index:** a `COLLECTION_GROUP`-scoped single-field override on `blocked.blockedUid`. The automatic single-field index only covers `COLLECTION` scope, and the emulator does not enforce indexes — so without it this passes every test here and fails with `FAILED_PRECONDITION` in production.

**Not covered by test:** the provider wiring itself (feed filtering, match filtering, Nearby) — same DI limitation. The extracted logic and the rules are tested; the call sites are verified by reading.

### H14 / H15. Match deck: stuck spinner, and profiles that come back — ✅ FIXED 2026-07-21
`MatchProvider`, `match_logic.dart`, `match_screen.dart`

**H14** — `loadCandidates` read the user profile and the candidate list with no `try/catch` (only the blocked-list read, added for H10, was guarded). Offline or `permission-denied` threw straight past `_loading = false`, so the tab spun forever. All reads are now in one `try`; a new `error` getter surfaces the failure and the screen shows a retry (`_MatchError`) instead of an endless spinner.

**H15** — the candidate query excluded nobody you'd already acted on, so passed profiles returned on the next load, and `passUser` `add()`ed a fresh doc every pass.
- `recordLike` / `recordPass` write with a **deterministic edge id** (`${me}__${them}`) — one outgoing edge per pair, so re-liking / re-passing / like-then-pass overwrites instead of duplicating.
- `fetchActedOnUids` unions two directions. The second is the subtle one: a match completed via the *other* person's doc has *them* as `userA`, so a naive `userA == me` scan misses it and the matched person resurfaces after a reload. Someone whose like of me is still `pending` is deliberately kept in the deck so I can match back.

Both new queries are equality-only with no `orderBy`, so no composite index is needed. **Coverage:** 11 new `match_logic` tests (idempotency, `recordPass`, `fetchActedOnUids`). Provider wiring itself untested — same DI limitation.

### H13. A post with others' engagement could never be deleted — ✅ FIXED 2026-07-21
`firestore.rules` (likes, comments), `PostProvider`, like/comment write paths

`deletePost` built one atomic batch deleting every comment and like, then the post. But `likes/{userId}` was `allow write: if isOwner(userId)` and comments delete-only-by-author — so the instant *another* user engaged, their doc was denied and Firestore failed the **whole batch atomically**. The author's own post became undeletable. This is the write-side twin of the B2/H7 "one denied doc fails the whole operation" rule.

**Fix (denormalised, no `get()`):**
- Each like/comment now carries `postAuthorId`, written at engagement time. The delete rule admits `isOwner(userId) || request.auth.uid == resource.data.postAuthorId || isAdmin()`. `get()` was avoided deliberately — a cascade batch would blow past Firestore's **20-document-access ceiling** for multi-doc operations, so the `get()`-per-delete approach would itself fail on a popular post.
- `deletePost` chunks the cascade at 400 writes/batch (< the 500 cap), fixing a second latent bug the report noted: a viral post's engagement would overflow a single batch. The post doc is deleted **last**, so a mid-cascade failure leaves a retryable post rather than orphans under a vanished parent.

**Backfill:** `scripts/backfill-engagement-post-author.js` (`--dry-run` first) sets `postAuthorId` on pre-existing likes/comments from their parent post's author. **Not** a deploy prerequisite — the rule only grants delete power, so ordering breaks nothing; until it runs, deleting a post with *old* foreign engagement still fails, exactly the original bug for legacy data. Orphaned engagement (post already gone) is left as-is and reported.

**Coverage:** `functions/test/rules/post-deletion.rules.test.ts` (8 tests) — author can delete others' engagement on their own post; owners keep their own delete power; a stranger cannot; being a liker grants nothing over third-party likes. Client wiring verified by reading (DI limitation).

### H9. Another user's passport showed — and deleted — YOUR trips — ✅ FIXED 2026-07-21
`trips_screen.dart`, `TripProvider`, `passport_ownership.dart`

`/passport/:userId` was opened for other users (from their profile), but `TripsScreen` never read `widget.userId`. `TripProvider.trips` streams only the signed-in user's trips, so a foreign passport showed **your** trips, titled "My Trips", with a live Add button and a per-row Delete — and tapping Delete removed **your own** trip. The `userId` field even had a doc-comment promising a read-only view that was never implemented.

**Fix:**
- `isOwnPassport(viewerUid, routeUserId)` gates everything: a null route id (bottom-tab entry) or a matching uid is your own; anyone else is read-only; a signed-out viewer never owns a specific-user passport.
- Own passport keeps the live `TripProvider.trips` stream and edit controls. A foreign one uses a new `watchUserTrips(userId)` stream (the `trips` read rule already allows `isAuth()`, and the `userId + startDate` index already exists). Title becomes "Trips", the Add action and every Delete are gone, and the empty state speaks about them, not you.

**Coverage:** `passport_ownership_test.dart` (5 tests) pins the ownership decision — including the two signed-out edge cases, where it must never grant edit over anyone. The screen wiring is verified by reading (presentation layer) and on device.

### H19. Business analytics showed every OTHER business's numbers — ✅ FIXED (UI) 2026-07-21
`analytics_screen.dart`, `dashboard_screen.dart`, `business_scope.dart`

`PromotionProvider` streams the whole `promotions` collection — correct, because the public "Crew Deals" feed needs every active deal. But the analytics and dashboard screens aggregated that **raw** list: top promotion, total views, active-deal count, redemption leader, recent activity were all computed across every business. Business A's dashboard showed Business B's titles, views, saves and redemptions as its own. `myPromotions(uid)` existed and simply wasn't used; the "upcoming events" tile leaked the same way over the global events list.

**Fix:** `ownPromotions(all, businessId)` / `ownEvents(all, businessId)` scope every aggregation to the signed-in business. A **null uid returns nothing, not everything** — "show all" was exactly the leak, so the failure mode is empty, not global. Applied at all five sites across the two screens.

**Coverage:** `business_scope_test.dart` (6 tests), including the null-uid guard in both directions.

**Honest limit — this is a UI fix, not a data-model fix.** The `promotions` read rule is `allow read: if isAuth()`, so `views` / `saves` / `currentRedemptions` sit on publicly-readable deal docs — a determined actor can still read a competitor's counts directly. Today those counters are static (the rule comments note the view/save/redeem *tracking* feature "doesn't exist yet"), so the exposure is latent. **When real tracking ships, those metrics must move to an owner-only-readable location** (a subcollection or side doc) to be genuinely private. Filed as the H19 follow-up.

### H24. Opening a busy chat could crash; history loaded unbounded — ✅ FIXED 2026-07-21
`ChatProvider`, `chat_logic.dart`

Two problems in the conversation screen's data path:
- **The crash.** `markMessagesRead` — called fire-and-forget from `initState` — read every non-own message and wrote them all in **one** batch. Firestore caps a batch at 500 writes, so a chat with >500 unread threw an uncaught exception out of `initState`, taking the screen down on open.
- **Unbounded load.** `watchMessages` streamed the *entire* history with no limit, re-emitting every message on each new one — memory and read cost that grew without bound on a long chat.

**Fix:**
- `markMessagesReadIn` chunks the writes at `kWriteBatchLimit` (400, < the 500 cap), and the provider call is wrapped in try/catch so a best-effort mark-read never surfaces as an unhandled async error from `initState` — the unread badge simply persists to the next open.
- `chunked()` is now the shared helper for both this and `deletePost`'s cascade (H13), which was doing the same thing inline.
- `watchMessages` is bounded to the most recent 100 (queried newest-first + reversed for display). Single-field `orderBy`, so no composite index. This matches the usual chat default of showing recent history; **scroll-back pagination for older messages is a follow-up**, not built here.

**Coverage:** `chat_logic_test.dart` (8 tests) — `chunked` boundaries, and `markMessagesReadIn` marking others' unread / skipping own / not duplicating / handling 900 messages across chunks. fake_cloud_firestore doesn't enforce the 500 cap, so the crash itself can't be reproduced in a unit test; the chunking that prevents it is covered structurally.

### H17. Turning off location sharing kept uploading your coordinates — ✅ FIXED 2026-07-21
`nearby_users_screen.dart`, `location_share_gate.dart`

Nearby gated the location upload on `AuthProvider.currentUser.settings`. Settings writes through `UserProvider`, and `AuthProvider.currentUser` never refreshes — so `shareLocation: false` was invisible here and your coordinates kept uploading to `users/{uid}.lat/lng` on every Nearby open, indefinitely, until an app restart.

Worse, it couldn't be fixed by just reading `UserProvider` instead: **`UserProvider.updateAuth` does `_currentUser = auth.currentUser` on every auth notify**, so even its freshly-fetched settings get clobbered back to the stale `AuthProvider` copy. Neither in-memory provider is a trustworthy source for a privacy gate.

**Fix:** `persistLocationIfAllowed(db, uid, lat, lng)` reads the `shareLocation` / `approxLocationOnly` settings **authoritatively from Firestore** at the moment of the upload decision, sidestepping every cached copy. It **fails closed** — if the settings read throws (offline/permission), nothing is uploaded, the opposite of the old `catch (_) {/* fail open */}`. The two pure helpers (`shouldShareLocation`, `resolveCoordinateToPersist`) moved into the gate file alongside it.

**Coverage:** `location_share_gate_test.dart` (5 tests) — no write when off, reads the *current* value not a stale one, exact vs. fuzzed coordinate, default-on when settings absent. The existing helper tests moved with them.

**Residuals (noted, not fixed here):** the SafeCheck check-in call site still fuzzes with `user.settings` (stale `approxLocationOnly`) — a lesser concern since check-in is explicit consent, only the fuzz *precision* can lag. And the root cause — `UserProvider.updateAuth` clobbering fresh state — is exactly what the **provider DI refactor** would resolve properly; this fix routes around it for the one privacy-critical path.

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
