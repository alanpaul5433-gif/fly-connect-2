# Store Readiness Test Plan — FlyConnect

Companion to `docs/audit-report.md`. Targets the **actual** coverage gaps found in the audit
(provider unit coverage 3/12, ~no feature-screen widget tests, integration tests skipped).

The existing suite (`test/providers/*`) validates the **data-layer contract against
`fake_cloud_firestore`** rather than instantiating providers (which use `FirebaseFirestore.instance`
singletons). New unit tests below follow that same proven pattern, so they drop in and pass.

---

## 1. Priority order (highest store-risk first)

| # | Test | Why it matters for submission | Type |
|:-:|------|-------------------------------|------|
| 1 | Account-deletion contract | Hard store requirement; verify subcollections + auth purge | unit (exists, extend) |
| 2 | Report write contract | UGC moderation must persist (Apple 1.2 / Play UGC) | unit (exists, extend) |
| 3 | Block filters feed/chat/nearby | Blocked users must actually disappear | unit |
| 4 | ChatProvider message contract | Core flow a reviewer will exercise | unit |
| 5 | MatchProvider swipe/match contract | Headline feature | unit |
| 6 | Notification tap → route | Deep-link from push (exists ✓) | unit (exists) |
| 7 | Login screen renders Google **and** Apple | Guideline 4.8 evidence | widget |
| 8 | Signup blocks without consent | ToS gate must hold | widget |
| 9 | Auth → home happy path | Smoke of the critical flow | integration (un-skip) |

---

## 2. Drop-in unit stubs

### `test/providers/chat_provider_test.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// ChatProvider data-layer contract (mirrors post_provider_test pattern).
void main() {
  late FakeFirebaseFirestore db;
  const me = 'user-a';
  const them = 'user-b';
  const chatId = 'user-a_user-b';

  setUp(() => db = FakeFirebaseFirestore());

  group('Chat creation', () {
    test('a chat lists both participants', () async {
      await db.collection('chats').doc(chatId).set({
        'participants': [me, them],
        'lastMessage': '',
        'updatedAt': Timestamp.now(),
      });
      final snap = await db.collection('chats').doc(chatId).get();
      expect(snap.data()!['participants'], containsAll([me, them]));
    });
  });

  group('Messaging', () {
    test('sending a message writes to messages with the correct senderId', () async {
      await db.collection('chats').doc(chatId)
          .collection('messages').add({
        'senderId': me,
        'text': 'Layover in DXB?',
        'sentAt': Timestamp.now(),
        'readBy': [me],
      });
      final msgs = await db.collection('chats').doc(chatId)
          .collection('messages').get();
      expect(msgs.docs, hasLength(1));
      expect(msgs.docs.first['senderId'], me);
    });

    test('marking read appends the reader to readBy without forging sender', () async {
      final ref = await db.collection('chats').doc(chatId)
          .collection('messages').add({'senderId': me, 'readBy': [me]});
      await ref.update({'readBy': FieldValue.arrayUnion([them])});
      final doc = await ref.get();
      expect(doc['readBy'], containsAll([me, them]));
      expect(doc['senderId'], me); // unchanged
    });
  });
}
```

### `test/providers/match_provider_test.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// MatchProvider data-layer contract.
void main() {
  late FakeFirebaseFirestore db;
  const a = 'user-a';
  const b = 'user-b';

  setUp(() => db = FakeFirebaseFirestore());

  test('creating a match is owned by userA and starts pending', () async {
    final ref = await db.collection('matches').add({
      'userA': a, 'userB': b, 'status': 'pending', 'createdAt': Timestamp.now(),
    });
    final doc = await ref.get();
    expect(doc['userA'], a);
    expect(doc['status'], 'pending');
  });

  test('mutual like transitions pending -> matched', () async {
    final ref = await db.collection('matches').add({
      'userA': a, 'userB': b, 'status': 'pending',
    });
    await ref.update({'status': 'matched', 'matchedAt': Timestamp.now()});
    expect((await ref.get())['status'], 'matched');
  });

  test('a pass is recorded as status=passed (not deleted)', () async {
    final ref = await db.collection('matches').add({
      'userA': a, 'userB': b, 'status': 'pending',
    });
    await ref.update({'status': 'passed'});
    expect((await ref.get())['status'], 'passed');
  });
}
```

### `test/providers/block_filtering_test.dart`

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Blocking must both persist AND remove the blocked author's content from view.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const blocked = 'blocked-user';

  setUp(() => db = FakeFirebaseFirestore());

  test('blocking writes to users/{me}/blocked/{id}', () async {
    await db.collection('users').doc(me)
        .collection('blocked').doc(blocked).set({'at': Timestamp.now()});
    final doc = await db.collection('users').doc(me)
        .collection('blocked').doc(blocked).get();
    expect(doc.exists, true);
  });

  test('feed excludes posts authored by a blocked user', () async {
    await db.collection('users').doc(me)
        .collection('blocked').doc(blocked).set({'at': Timestamp.now()});
    await db.collection('posts').add({'authorId': blocked, 'text': 'hidden'});
    await db.collection('posts').add({'authorId': 'someone', 'text': 'visible'});

    final blockedIds = (await db.collection('users').doc(me)
        .collection('blocked').get()).docs.map((d) => d.id).toSet();
    final visible = (await db.collection('posts').get()).docs
        .where((d) => !blockedIds.contains(d['authorId'])).toList();

    expect(visible, hasLength(1));
    expect(visible.first['text'], 'visible');
  });
}
```

> Note: the third test encodes the **client-side filter contract**. Confirm the real feed
> applies this filter (`real_providers.dart` PostProvider) — if blocked authors aren't filtered
> in the live query, that is itself a finding to fix.

---

## 3. Drop-in widget stubs

### `test/widgets/login_buttons_test.dart` — evidence for Guideline 4.8

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// import the login screen + wrap with the providers it needs (see existing
// forgot_password_screen_test.dart for the MultiProvider + MaterialApp.router harness).

void main() {
  testWidgets('login offers BOTH Google and Apple sign-in', (tester) async {
    // await tester.pumpWidget(wrapWithApp(const LoginScreen()));
    // expect(find.text('Sign in with Google'), findsOneWidget);
    // expect(find.text('Sign in with Apple'), findsOneWidget);
  }, skip: true); // un-skip once the provider harness is imported
}
```

### `test/widgets/signup_consent_test.dart`

```dart
// Verifies the ToS/Privacy gate: tapping "Create account" without checking the
// box surfaces the consent-required message and does NOT call the auth provider.
// Harness: pump SignupScreen, tap submit, expect find.text(
//   'Please agree to the Terms of Service and Privacy Policy to continue.').
```

---

## 4. Integration tests (un-skip in CI)

`integration_test/auth_flow_test.dart` and `post_create_flow_test.dart` exist but are `skip: true`
pending an emulator. To activate:

1. Add the Firebase emulator to CI before `flutter test integration_test`:
   ```yaml
   - run: curl -sL https://firebase.tools | bash
   - run: firebase emulators:exec --only auth,firestore "flutter test integration_test"
   ```
2. Seed a known test account in the emulator (or via `firebase_auth_mocks` for widget-level).
3. Remove `skip: true` once green locally.

CI today (`/.github/workflows/ci.yml`) runs `flutter test` (unit+widget) and gates the AAB/iOS
build on green — add an `integration_test` step in the same job.

---

## 5. Manual release-build smoke test

`docs/manual-smoke-test.md` already exists — run it on a **physical** Android 15 device and a
**physical** iPhone (Sign in with Apple cannot be tested in the simulator) against a **release**
build before each submission. Pay special attention to:

- Google **and** Apple sign-in complete on iOS (validates blockers #2/#3/#4 are cleared).
- A push notification arrives on iOS and the tap routes correctly (validates FCM/iOS Firebase).
- Tapping the in-app Terms/Privacy links opens a live page (validates blocker #1).
- Delete Account → confirm the user can no longer sign in and their profile is gone.

---

## 6. Update — 2026-07-13 audit findings (see `docs/store-readiness-audit-2026-07-13.md`)

New Critical finding this pass: **contract-style tests (Section 2's pattern — mirror what a provider
*should* write against `fake_cloud_firestore`) cannot catch a screen that never calls the provider at
all.** That's exactly how `group_management_screen.dart` and `event_management_screen.dart` shipped
with 5+ fake actions (Delete Group, Broadcast, Remove Member/Attendee, Edit Event, fake "Link copied!")
undetected — every existing test in this suite tests the write shape, none test that the UI actually
triggers it. Closing this gap needs a **second test shape**, not just more of the first:

### New priority order (highest risk first, supersedes nothing in Section 1 — additive)

| # | Test | Why it matters | Type | Blocked on |
|:-:|------|-----------------|------|:-:|
| 1 | `GroupManagementScreen` "Delete Group" actually deletes | Critical #2 in the audit — currently a pure UI no-op reachable by real business users | widget (pump + verify provider call) | `GroupProvider.deleteGroup()` doesn't exist yet — write the test alongside the method, not before it |
| 2 | `GroupManagementScreen` "Broadcast Message" actually sends | Same | widget | `GroupProvider.broadcastMessage()` doesn't exist yet |
| 3 | `EventManagementScreen` "Save Changes" persists to Firestore | Currently silently reverts on reload | widget | none — provider write path can reuse the existing `EventProvider` update pattern |
| 4 | `EventManagementScreen` "Remove Attendee" persists | Currently local-only; `_approve`/`_decline` on the same screen show the correct pattern to copy | widget | none |
| 5 | `EventManagementScreen` share button calls `Clipboard.setData` | One-line fix, but currently silently claims success | widget | none |
| 6 | `group_details_screen.dart` remove-member icon hidden for non-admins | Currently shown to every viewer, not just group admins | widget | none |
| 7 | `otp_screen.dart` continue button blocks on `emailVerified` | Currently unconditional per the screen's own comment | widget | none |

### Why these must be widget tests, not contract tests

Section 1-3's stubs (e.g. `test/features/profile_moderation_test.dart`) prove a *hand-written mirror*
of the intended Firestore write is well-formed — they never instantiate the actual screen, so they
can't fail when a button's `onPressed` forgets to call anything. The new tests must:

1. `pumpWidget` the real screen (with a `MultiProvider` override supplying a fake/spy `GroupProvider`
   or `EventProvider`).
2. `tester.tap()` the real button.
3. Assert the spy provider recorded the expected call (e.g. `verify(mockGroupProvider.deleteGroup('grp_1')).called(1)`), or, if using `fake_cloud_firestore` end-to-end, assert the document is actually gone/changed after the tap.

This repo doesn't yet have a mocking package (`mockito`/`mocktail`) in `dev_dependencies` — add one
before writing tests #1-2, since a hand-rolled spy provider is more brittle for capturing call
arguments than a generated mock.

**Test stub code is intentionally not included here yet** — `GroupProvider.deleteGroup()` and
`.broadcastMessage()` don't exist in `real_providers.dart`, so a compiling test can't be written
until Remediation Roadmap item #8 (in the audit report) lands. Writing speculative test code against
methods that don't exist would violate this skill's "must actually compile" rule. Once those methods
exist, tests #1-2 should be added in the same commit, using the `MultiProvider`-override + `tester.tap()`
pattern above — not the contract-mirror pattern used elsewhere in this file.

---

_Generated by `store-readiness-audit`. Stubs follow the repo's existing `fake_cloud_firestore` contract style._
