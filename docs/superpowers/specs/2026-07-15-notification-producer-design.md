# Notification Producer (C-3) + Minimal Deep-Link Fix (C-4) — Design

**Date:** 2026-07-15
**Origin:** `docs/QA_AUDIT_REPORT.md` findings C-3 (Critical) and C-4 (Critical, coupled to C-3)
**Status:** Revised after a 5-lens multi-agent design review (architecture/cost, security/privacy,
data-model consistency, test adequacy, C-4/Flutter routing) — see "Review disposition" below.
Approved for implementation planning.

## Problem

No social action in FlyConnect ever produces a notification. The only writers of the
`notifications` collection are two admin-only screens (`admin_notifications_page.dart`,
`admin_safecheck_page.dart`). Likes, comments, follows, matches, messages, and RSVPs never
write one, and there are no Cloud Functions in the repo to fan out real push. The bell-icon
badge (`TopBarActions` → `NotificationProvider.unreadCount`) and the Notifications screen are
fully wired on the client but structurally starved of data.

Separately, `/posts/:postId` is not a registered route (C-4). This is masked today only because
C-3 means no `post_like`/`post_comment` notification is ever generated to tap. The moment C-3
ships, tapping those notifications hits GoRouter's raw error page. This pass fixes both together.

## Scope decisions (confirmed with user)

1. **Full push via Cloud Functions**, not a client-side-only/rules-loosening approach for
   *notification creation*. The project (`flyconnect-ab4f2`) is confirmed already on the Blaze
   plan, which Cloud Functions of any kind require. (This pass *does* still touch
   `firestore.rules` — see "Rules changes" below — but only to close gaps in the documents that
   *trigger* producers, not to loosen the `notifications` collection's own rules, which stay
   exactly as they are today.)
2. **Messages get both a push and a `notifications/` list entry**, in addition to their existing
   separate per-chat unread badge / read-receipt system (fixed under H-3, unrelated to this
   collection).
3. **C-4 is bundled into this pass** with the audit's own suggested minimal fix (register the
   route with a fetch-by-id loader, add a router `errorBuilder`) rather than shipped broken or
   worked around by suppressing the deep link.
4. Claude implements and verifies against the Firebase emulator suite; the user reviews and runs
   `firebase deploy` themselves — same deploy gate already standing for C-1/C-2 in the audit.

## Review disposition

This spec went through a 5-lens multi-agent review panel before implementation planning. The
panel found 3 blockers and 12 majors, all verified against actual source (rules/code line
references spot-checked and confirmed accurate). Per user direction, **all blockers and majors
are folded into this revision**; the panel's 5 minors are recorded as known follow-ups rather
than fixed now (see "Known limitations").

| # | Finding | Disposition |
|---|---|---|
| Blocker | Follow producer trusts a wide-open `firestore.rules` write, enabling forgery/spam | **Fixed** — rules tightened, see "Rules changes" |
| Blocker | No Firestore-emulator-backed integration test for trigger wiring | **Fixed** — added to Testing |
| Blocker | No test pinning push fan-out to `private/data.fcmToken`, not the stale flat `UserModel.fcmToken` | **Fixed** — added to Testing |
| Major | No idempotency against Cloud Functions' at-least-once delivery | **Fixed** — deterministic doc IDs, see "Idempotency" |
| Major | Admin broadcast becomes an unbatched, unbounded push burst | **Fixed** — `maxInstances` cap + sizing note |
| Major | Likes get the full push pipeline with no volume coalescing | **Fixed** — Stage 2 skips FCM send for `type == 'like'` |
| Major | No blocked-user filtering in any producer | **Fixed** — shared `isBlocked()` guard on every producer |
| Major | Match mutual-consent not rules-enforced | **Fixed** — rules tightened to require the non-initiator |
| Major | Message fan-out to uncapped/unvalidated chat participants | **Fixed** — capped at 50 in both the Cloud Function and `firestore.rules`; the deeper "who can be added to a chat" trust question is a separate, pre-existing subsystem (chat creation/invites) and is out of scope here — recorded as a follow-up |
| Major | Stage 2 needs an `actorId`→`userId` field rename the spec didn't state | **Fixed** — full lookup table spelled out below |
| Major | `'comment'` type string not recognized by `resolveRouteFromPayload` | **Fixed** — in the same lookup table |
| Major | Admin writers' `type` strings (`admin`, `admin_safecheck`) don't map to a route | **Fixed** — in the same lookup table |
| Major | "Same pattern as `EventDetailsScreen`" is the wrong precedent (it doesn't fetch by id) | **Fixed** — now cites `GroupDetailsScreen` + `GroupProvider.getGroup()` |
| Major | Router redirect swallows unauthenticated deep links, no post-login resume | **Documented as a known limitation** (pre-existing gap shared by every deep-link route, not introduced by this pass; a real fix is a separate, larger piece of auth/redirect work) |
| Major | `errorBuilder` claim overstated; test plan conflated route-registration with errorBuilder behavior | **Fixed** — wording tightened, tests split |

## Rules changes

Two `firestore.rules` tightenings, both closing gaps in documents that now drive real push
notifications (previously harmless because nothing read them for that purpose):

**`users/{targetUid}/followers/{followerId}`** — today `allow write: if isAuth();`, with no
check that the writer is the follower themself. Change to:

```
allow write: if isOwner(followerId) && isNotBanned() && followerId != targetUid;
```

Mirrors the existing `posts/{postId}/likes/{userId}` ownership pattern already used elsewhere in
this file. The Cloud Function also independently guards `followerId != targetUid` as
defense-in-depth (belt-and-braces, not a substitute for the rule).

**`matches/{matchId}`** — today any participant (`userA` or `userB`) may update `status` to
anything in `['pending','matched','passed']`-shaped writes covered by `changedOnly([...])`,
including flipping `pending → matched` unilaterally. Per the app's own logic in `likeUser()`,
only the *reciprocating* party (`userB` of the existing pending doc — `userA` is always whoever
created the doc, i.e. the original liker) should be able to complete a match. Change the update
rule to:

```
allow update: if isAuth()
  && request.auth.uid == resource.data.userB
  && resource.data.status == 'pending'
  && request.resource.data.status == 'matched'
  && changedOnly(['status','matchedAt','chatId']);
```

This also happens to make the update rule *more* correct generally (the app never updates a
match doc for any other transition — `passUser()` always creates a new doc rather than updating
an existing one), not just tighter for this feature.

**`chats/{chatId}` create/update** — add a defensive size cap so one write can't fan out
notifications (or unread-count increments, per H-3) to an unbounded number of arbitrary uids:

```
allow create: if isAuth()
  && request.auth.uid in request.resource.data.participants
  && request.resource.data.participants.size() <= 50;
allow update: if isAuth()
  && request.auth.uid in resource.data.participants
  && request.resource.data.participants == resource.data.participants;
```
(only the `create` rule changes; `update` already forbids changing `participants` at all). This
caps the blast radius of the message producer (below) without touching chat invite/membership
UX, which is out of scope here.

No changes to the `notifications` collection's own rules — Admin SDK writes from Cloud Functions
bypass `firestore.rules` entirely, so the existing restrictive `create` rule (self-only or admin)
is untouched and still correct.

## Architecture

Two kinds of Cloud Function, both in a new `functions/` directory (Node 20, TypeScript,
`firebase-admin` + `firebase-functions` v2 API, `onDocumentCreated`/`onDocumentUpdated` triggers).

### Idempotency

Firestore triggers are at-least-once, not exactly-once — retries happen on timeouts, cold
starts, or transient infra errors. Every producer writes its notification doc with a
**deterministic ID** derived from the triggering event, using `.doc(id).create()` (which throws
`ALREADY_EXISTS` on a duplicate write) rather than `.add()`:

| Producer | Deterministic doc ID |
|---|---|
| Like | `like_{postId}_{likerUid}` |
| Comment | `comment_{commentId}` |
| Follow | `follow_{targetUid}_{followerId}` |
| Match | `match_{matchId}_{recipientUid}` (one per recipient — two docs total per match) |
| RSVP | `rsvp_{eventId}_{uid}` |
| Message | `message_{messageId}_{recipientUid}` (one per non-sender participant) |

A retried trigger invocation hits `ALREADY_EXISTS`, is caught and treated as a no-op success —
no duplicate doc, and since Stage 2 only fires on genuine document *creation*, no duplicate push
either.

### Blocked-user filtering

A shared helper, `isBlocked(actorId, recipientId)`, checks both directions —
`users/{recipientId}/blocked/{actorId}` and `users/{actorId}/blocked/{recipientId}` — via the
Admin SDK. Every producer calls it before writing a notification and skips (no doc, no push) if
either direction returns true. This closes the gap where a blocked user's continued activity
(which was silently ignored before this pass) would otherwise become an active push to the
person who blocked them.

### Stage 1 — six producer triggers

Each producer is a small Firestore trigger that, on the relevant write, resolves the recipient(s),
applies the self-notify and blocked-user guards, and writes a `notifications/{id}` doc (see
Idempotency above for the ID scheme) via the Admin SDK.

Notification doc shape written by producers (matches the existing `NotificationModel` fields,
plus untyped extra fields only Stage 2 reads — same pattern the two existing admin writers
already use with their extra `uid` field):

```
{
  userId: string,       // recipient — required, part of NotificationModel
  type: string,          // 'like' | 'comment' | 'follow' | 'match' | 'message' | 'event'
  title: string,
  body: string,
  deepLink: string | null,
  isRead: false,
  createdAt: serverTimestamp(),
  // extra, untyped — read only by the Stage 2 push-fanout function, identifiers only,
  // never raw user-generated content (e.g. never a full comment body — see "known limitations"):
  actorId: string,
  postId?: string, chatId?: string, eventId?: string,
}
```

(`matchUserId` from the previous draft is dropped — nothing on either the in-app or FCM tap path
ever reads it; the match deep link is always the static `/match` route with no id.)

| Trigger | Firestore path | Recipient resolution | Guards | `type` / `deepLink` |
|---|---|---|---|---|
| Like | `onCreate posts/{postId}/likes/{uid}` | read `posts/{postId}`, use `authorId` | skip if `uid == authorId`; skip if blocked either direction | `like` / `/posts/{postId}` — **Stage 2 does not send a push for this type** (see Stage 2) |
| Comment | `onCreate posts/{postId}/comments/{commentId}` | read `posts/{postId}`, use `authorId` | skip if comment's `authorId == post.authorId`; skip if blocked | `comment` / `/posts/{postId}` |
| Follow | `onCreate users/{targetUid}/followers/{followerId}` | `targetUid` (from path) | skip if `followerId == targetUid`; skip if blocked (rules now also enforce `followerId != targetUid` and ownership, see "Rules changes") | `follow` / `/users/{followerId}` |
| Match | `onUpdate matches/{matchId}` | **both** `userA` and `userB` | fires **only** when `status` transitions `pending → matched` (now also rules-enforced to require `userB`, the non-initiator, see "Rules changes"); a one-way pending like or a `passed` write never notifies (no admirer reveal) | `match` / `/match` |
| RSVP | `onCreate events/{eventId}/rsvps/{uid}` | read `events/{eventId}`, use `createdBy` | skip if `uid == createdBy`; skip if blocked | `event` / `/events/{eventId}` |
| Message | `onCreate chats/{chatId}/messages/{messageId}` | read parent chat doc's `participants`, one notification per participant except `senderId`, **capped at the first 50 participants** (matches the new `firestore.rules` chat-creation cap; logs a warning if a chat somehow exceeds it) | none beyond the sender exclusion and the cap (mirrors the exact loop already added to `sendMessage`'s `unreadCount` increment for H-3); blocked-check is skipped here since chat participants already had to mutually exist in the chat to message at all |

Each producer that needs the actor's display name for the notification `body` (e.g. "Maria Chen
liked your post") reads `users/{actorId}`. If that read comes back missing (e.g. the actor's
account was since GDPR-deleted), the producer still writes the notification with a generic
fallback body ("Someone liked your post") rather than throwing and silently dropping it.

### Stage 2 — shared push fan-out

One trigger, `onDocumentCreated('notifications/{id}')`, with `maxInstances: 20` — an explicit,
non-infinite ceiling (Cloud Functions v2 defaults to effectively unbounded auto-scaling) so a
large admin broadcast queues through 20 concurrent invocations rather than spiking cost/concurrency
unboundedly. 20 is chosen to keep a broadcast to a few hundred recipients draining in well under a
minute while capping the worst-case concurrent-invocation bill; revisit if broadcasts routinely
exceed the low thousands. Admin broadcasts (`admin_notifications_page.dart`,
`admin_safecheck_page.dart`) already write via a single `batch.commit()` today and are expected
to stay in the hundreds-not-thousands range for this app's user base; if that changes, moving
broadcast push to a dedicated batched `sendEachForMulticast()` callable is a follow-up, not
required now.

1. If `type == 'like'`: write nothing further — the in-app notification doc (already written by
   Stage 1) is sufficient; no push is sent. Likes are the highest-frequency, lowest-signal action
   in the app and don't warrant a push per event.
2. Otherwise, read `users/{userId}/private/data.fcmToken` for the doc's `userId` — **not**
   `users/{userId}.fcmToken`, which is a stale flat field still present on the Dart `UserModel`
   for backward compatibility but no longer written to by `notification_service.dart` (which
   moved the real token to the `private/data` subdoc as PII, alongside the rest of the H-2 work).
   Getting this path wrong means every push silently no-ops — see the dedicated test for this in
   "Testing".
3. If missing: log and stop.
4. If present: `admin.messaging().send()` with the doc's `title`/`body` as the native
   notification payload — **except** for `type == 'match'` and `type == 'message'`, which use a
   generic title/body ("You have a new match" / "New message") instead of the doc's actual
   title/body, since push notification payloads render on the lock screen with weaker access
   control than an authenticated Firestore read (a colleague's name in a "You matched with X"
   banner, or a message preview, both visible to anyone glancing at the device). The full
   title/body is still what's shown in-app (the Firestore doc itself is unchanged).
5. The `data` payload is built via an explicit, fully-specified lookup table (not an "etc." —
   this was a major finding: the previous draft only showed 3 of 8 needed rows):

   | Doc `type` | FCM `data.type` | FCM data fields (renamed from doc fields where noted) |
   |---|---|---|
   | `like` | *(no push sent — see step 1)* | — |
   | `comment` | `post_comment` | `postId` |
   | `follow` | `follow_request` | `userId: <doc's actorId>` — **note the rename**: the doc's own `userId` field is the *recipient*, not the follower; the outgoing payload's `userId` must be the doc's `actorId`, never the doc's own `userId` |
   | `match` | `match` | *(none — always routes to the static `/match`)* |
   | `event` | `event` | `eventId` |
   | `message` | `message` | `chatId` |
   | `admin` (existing admin writer) | *(no data payload — falls through to `AppRoutes.notifications`, matching today's admin-broadcast intent)* | — |
   | `admin_safecheck` (existing admin writer) | `safe_check` | *(none)* |

6. On send failure (invalid/expired token, etc.): catch and log. **Not building** token
   invalidation/cleanup in this pass — flagged as a known follow-up, not a blocker.

Because this fan-out triggers on the collection itself, the two existing **admin** notification
writers start sending real push automatically (per the table above), with no changes needed to
either admin screen's write logic.

### Known limitations (explicitly out of scope for this pass)

- **Unauthenticated deep-link taps are lost.** `app_router.dart`'s `redirect` sends any
  unauthenticated request to a non-public route to `/login` with no mechanism to resume the
  original target after auth. This is a pre-existing gap shared by every deep-link route
  (`/events/:id`, `/groups/:id`, `/conversation/:id`), not something this pass introduces — but
  this pass is what makes `/posts/:postId` reachable via real production push for the first
  time. A real fix (persisting and resuming the intended route post-login) is separate,
  larger auth/redirect work.
- **Chat participant trust.** The 50-participant cap (see Rules changes and the Message producer
  row) bounds the blast radius, but does not address the deeper pre-existing question of whether
  arbitrary uids can be added to a chat's `participants` array without their consent — that's
  chat-creation/invite logic, a different subsystem than this notification work.
- **Push preview privacy for `comment`/`follow`/`event` types.** Only `match` and `message` use a
  generic push title/body (step 4 above); the others still show real content (e.g. the actor's
  name) on the lock screen. Extending generic-preview treatment to more types, or adding a
  user-configurable "hide previews" setting, is a follow-up.
- **`_colorForType` gap.** `notifications_screen.dart`'s `_colorForType` switch doesn't have
  cases for `event`/`message` (both fall through to the default color); `_iconForType` does cover
  them correctly. Cosmetic — not fixed in this pass.
- **No end-to-end payload→route test.** The TypeScript lookup table (Stage 2) and Dart's
  `resolveRouteFromPayload` are tested independently; nothing asserts they agree byte-for-byte on
  every type beyond the explicit table above being copied correctly by hand into both. A shared
  fixture/golden-file test that both sides read from would close this gap; not built now.
- No stale-FCM-token cleanup on send failure.
- No Cloud Functions integration test against a live (non-emulated) Firebase project —
  verification is via the Firebase emulator suite only, since Claude does not deploy.

## C-4 — minimal deep-link fix

Bundled because C-3 immediately exposes it (see Problem section).

- `PostProvider`: add `Future<PostModel?> getPost(String postId)` — a single-document fetch.
  There is currently no fetch-by-id method on `PostProvider` (only stream/list access), and
  `PostDetailsScreen` requires a full `PostModel` (it can't be constructed from just an id).
- New `lib/features/home/post_by_id_screen.dart`, class `PostByIdScreen({required String postId})`
  — the fetch-by-id-then-render precedent to mirror is **`GroupDetailsScreen` +
  `GroupProvider.getGroup()`** (`lib/features/groups/group_details_screen.dart`,
  `real_providers.dart`'s `getGroup`), which does a real single-document await-then-render.
  (**Correction from the original draft:** `EventDetailsScreen` is *not* an equivalent pattern —
  it only filters an already-locally-loaded event list and never does a fetch-by-id read, which
  would render "not found" for any post the recipient hasn't already scrolled past in their own
  feed — exactly the common case for a notification about someone else's post.) `PostByIdScreen`
  has three states, not two: loading, a **retryable error** state (network/transient failure —
  the most likely failure mode right after a cold-start push tap) distinct from **not found**
  (the post genuinely doesn't exist / was deleted, rendering the existing `NotFoundScreen`).
- Register `GoRoute(path: '/posts/:postId', builder: (_, state) => PostByIdScreen(postId:
  state.pathParameters['postId'] ?? ''))` in `app_router.dart`.
- Add a top-level `errorBuilder: (_, __) => const NotFoundScreen(...)` to the `GoRouter` config
  (`lib/core/utils/app_router.dart`). **Scope correction:** this only catches unmatched/malformed
  *locations* (GoRouter-level routing failures), not runtime exceptions thrown while building an
  already-matched screen's widget tree — the original draft's "closes the general class of bug"
  language overstated this. It closes the general class of *unregistered-route* bugs specifically.

## Testing

- **Cloud Functions — unit (mocked Admin SDK):** `firebase-functions-test` + Jest. Per-producer
  tests covering recipient resolution, the self-notify guard, and the blocked-user guard (both
  directions); the match mutual-only transition logic (`pending → matched` fires; a create with
  `status: 'pending'` does not; a `passed` write does not; a `matched → matched` no-op update —
  simulating an at-least-once retry — does not re-notify; a `status` update applied twice in
  sequence does not double-notify; two distinct match docs for the same pair independently
  transitioning `pending → matched` each produce correctly-scoped, non-cross-contaminated
  notifications); the message producer's 3+ participant group-chat case (asserts exactly N-1
  notification docs, none for the sender) alongside the 2-participant DM case, and the 50
  -participant cap being respected; the deterministic-doc-ID idempotency behavior (a duplicate
  trigger invocation via `.create()` hitting `ALREADY_EXISTS` is caught and treated as a no-op,
  not an unhandled error); the actor-doc-missing fallback body case for each producer; and the
  push-fan-out function covering token-present/token-absent/send-failure paths, **plus a
  dedicated test asserting Stage 2 reads `users/{userId}/private/data.fcmToken` and not the flat
  `users/{userId}.fcmToken` field** (seed the token only in `private/data` and assert `send()` is
  called; seed it only on the flat field and assert `send()` is *not* called), and a test that
  `type == 'like'` never triggers a `messaging().send()` call at all.
- **Cloud Functions — integration (Firestore emulator, real trigger wiring):** using
  `firebase emulators:start --only firestore,functions` (or `@firebase/rules-unit-testing`),
  seed production-shaped documents against the real emulated Firestore and assert the resulting
  `notifications/{id}` doc via a real query — at least one integration test per producer plus the
  fan-out trigger. This is the layer that catches a wrong collection path or field-name typo,
  which the mocked-SDK unit tests above structurally cannot.
- **Dart:** a widget test for the new `PostByIdScreen` covering all three states (loading /
  retryable error / not-found); a route-registration test specifically for `/posts/:postId`
  resolving to `PostByIdScreen`; and a **separate** test navigating to a genuinely unregistered
  path (e.g. `/this-route-does-not-exist`) asserting `NotFoundScreen` renders with no raw
  GoRouter error widget — kept distinct per the review finding that folding both into one
  assertion risks "the router builds without throwing" standing in for "the errorBuilder actually
  renders the fallback." Follows the repo's existing test conventions (see
  `test/features/event_management_screen_test.dart` for the closest existing pattern).

## Deployment

- `firebase.json` gains a `functions` block (source `functions`, Node 20 runtime).
- New `functions/package.json`, `functions/tsconfig.json`, and:
  - `functions/src/index.ts` — exports all seven triggers.
  - `functions/src/producers/{likes,comments,follows,matches,rsvps,messages}.ts` — one file per
    producer from the table above.
  - `functions/src/pushFanout.ts` — the Stage 2 `onNotificationCreated` trigger, including the
    fully-specified in-app-`type` → FCM-`data.type` lookup table above.
  - `functions/src/lib/{firestore,fcm,blocked.ts}` — thin Admin SDK helpers shared by the above,
    including the shared `isBlocked()` guard.
- `firestore.rules` changes as specified in "Rules changes" above (`followers` write ownership,
  `matches` update mutual-consent, `chats` create participant cap) — these ship as part of this
  same pass, reviewed alongside the Cloud Functions code, since they're prerequisites for the
  producers to be safe.
- Claude implements and verifies against the Firebase emulator suite (`firebase emulators:start`
  with Firestore + Functions + a mocked/no-op messaging call). The user reviews and runs
  `firebase deploy --only functions,firestore:rules` themselves — this is a real-money,
  production-affecting action on an already-Blaze-billed project, same deploy gate already
  standing for the audit's open C-1/C-2 items.
