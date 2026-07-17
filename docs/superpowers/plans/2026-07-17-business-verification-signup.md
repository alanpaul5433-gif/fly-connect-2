# Business Verification Signup Gap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make business signups actually land in the admin's Pending Verification queue (`ein`, `licenseNumber`, `verificationStatus: 'pending'`), and close a `firestore.rules` gap that lets a signup write set `isVerified: true` directly.

**Architecture:** Two new optional fields on the existing business signup step, threaded through `AuthProvider.signup()` into the existing PII-protection split (main doc vs. owner-only `private/data` subdoc), plus a `firestore.rules` tightening on `/users/{userId}` create, plus a one-line addition to the admin page's fetch to pull the new private fields back in — mirroring the exact pattern `admin_users_page.dart` already uses for email/phone.

**Tech Stack:** Flutter/Dart, Provider (`ChangeNotifier`), Cloud Firestore, `firebase_auth`, `mocktail` + `flutter_test` (widget tests), `fake_cloud_firestore` (provider contract tests).

## Global Constraints

- No `UserModel` changes — `ein`/`licenseNumber`/`verificationStatus` are added as raw map fields on the Firestore writes, exactly like `dob`/`termsAcceptedAt` already are in `AuthProvider.signup()` (`lib/shared/providers/real_providers.dart:212-262`).
- `ein`/`licenseNumber` are optional, free-text, no format validation in this pass.
- `ein`/`licenseNumber` go to `users/{uid}/private/data` (owner+admin read only). `verificationStatus` goes on the main `users/{uid}` doc (business-status filtering needs to read it broadly; it isn't sensitive on its own).
- Document upload and an in-app resubmission flow are explicitly out of scope (see the design doc, `docs/superpowers/specs/2026-07-17-business-verification-signup-design.md`).
- **`firestore.rules` changes in Task 1 must NOT be deployed to production as part of this plan.** Validate locally/via MCP and commit only — deployment is a separate, explicit, user-confirmed step (`firebase deploy --only firestore:rules`), same as every prior rules change in this repo's history.
- **Known test-harness limitation carried over from the approved design:** `admin_business_verification_page.dart` calls `FirebaseFirestore.instance` directly with no injection seam. Per this repo's own documented limitation (see `test/widgets/admin_safecheck_page_test.dart`'s file comment, and the fact that its sibling `admin_users_page.dart` — which does the identical private-subdoc merge — has **no test file at all**), Task 4 does not add a new test file. This is a deliberate deviation from the design doc's testing section (which proposed a full behavioral test); flag this to the user when the plan completes.

---

### Task 1: Close the `isVerified` self-set gap in `firestore.rules`

**Files:**
- Modify: `firestore.rules:34-48`

**Interfaces:**
- Produces: no code interface — this is a rules-only change. Tasks 2-4 don't depend on it (they touch client code, not the rule text), but it must land before any production deploy of this feature.

- [ ] **Step 1: Read the current rule to confirm line numbers haven't drifted**

Run: `sed -n '33,48p' firestore.rules`

Expected output (context — confirms you're editing the right block):
```
    // ── Users ──────────────────────────────────────────────
    match /users/{userId} {
      allow read: if isAuth();
      allow create: if isOwner(userId)
        && request.resource.data.role in ['user', 'business']  // admins created server-side
        && request.resource.data.isBanned == false;
      // Users may edit their own profile but not role/ban/verified flags.
      // Admins may touch anything.
      allow update: if isAdmin()
        || (isOwner(userId) && changedOnly([
              'name','phone','photoUrl','bio','airline','airport','position',
              'city','state','hobbies','passportStamps','travelHistory',
              'followerCount','followingCount','postCount',
              'lastSeen','matchType','matchPrefs','settings','lat','lng'
            ]));
      allow delete: if isAdmin();
```

- [ ] **Step 2: Edit the `create` rule**

Replace:
```
      allow create: if isOwner(userId)
        && request.resource.data.role in ['user', 'business']  // admins created server-side
        && request.resource.data.isBanned == false;
```

With:
```
      // isVerified/verificationStatus must not be settable by the client at
      // create time — otherwise a business signup could write isVerified:
      // true (or verificationStatus:'verified') in the same write that
      // creates the account, fully bypassing isVerifiedBusiness()'s
      // admin-approval gate (found while wiring up the verification-status
      // submission flow below).
      allow create: if isOwner(userId)
        && request.resource.data.role in ['user', 'business']  // admins created server-side
        && request.resource.data.isBanned == false
        && request.resource.data.isVerified == false
        && (!('verificationStatus' in request.resource.data)
            || request.resource.data.verificationStatus in ['none', 'pending']);
```

- [ ] **Step 3: Validate the rule syntax**

Use the `mcp__plugin_firebase_firebase__firebase_validate_security_rules` tool against the local `firestore.rules` file (do NOT deploy). Expected: `OK`, no syntax/compile errors.

If the MCP tool isn't available in this session, fall back to: `firebase deploy --only firestore:rules --dry-run` is not a real firebase-tools flag — instead run `firebase deploy --only firestore:rules` **only after** explicit user confirmation later; for now, confirm syntax by eye against the diff above (matching brace/parenthesis count, valid CEL-like rules-language function calls already used elsewhere in the file).

- [ ] **Step 4: Commit**

```bash
git add firestore.rules
git commit -m "fix(rules): block client-set isVerified/verificationStatus at users create"
```

---

### Task 2: `AuthProvider.signup()` writes verification fields for business signups

**Files:**
- Modify: `lib/shared/providers/real_providers.dart:212-262`
- Test: `test/providers/auth_provider_test.dart`

**Interfaces:**
- Consumes: nothing new from Task 1.
- Produces: `AuthProvider.signup({..., String? ein, String? licenseNumber})` — Task 3's UI calls this with the two new named args. When `role == 'business'`, the main `users/{uid}` doc write gains `verificationStatus: 'pending'`; the `users/{uid}/private/data` write gains `ein`/`licenseNumber` (only the non-null ones).

- [ ] **Step 1: Write the failing contract test**

This repo's `AuthProvider` instantiates `FirebaseAuth.instance`/`FirebaseFirestore.instance` directly (not dependency-injected — see the file-level comment already in `test/providers/auth_provider_test.dart:5-15`), so existing tests in this file validate the *intended Firestore write shape* against a fake db rather than calling the real method body. Add a new test in that same style, in the `'Auth business rules'` group:

```dart
    test('business signup doc shape: verificationStatus pending on main doc, '
        'ein/licenseNumber on the private subdoc', () async {
      const uid = 'biz-uid-1';
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'Sky Lounge',
        'email': 'lounge@delta.com',
        'role': 'business',
        'isBanned': false,
        'isVerified': false,
        'verificationStatus': 'pending',
      });
      await db.collection('users').doc(uid).collection('private').doc('data').set({
        'email': 'lounge@delta.com',
        'ein': '12-3456789',
        'licenseNumber': 'LIC-998877',
      });

      final mainSnap = await db.collection('users').doc(uid).get();
      expect(mainSnap.data()!['verificationStatus'], 'pending');
      expect(mainSnap.data()!.containsKey('ein'), false);

      final privateSnap = await db
          .collection('users').doc(uid).collection('private').doc('data').get();
      expect(privateSnap.data()!['ein'], '12-3456789');
      expect(privateSnap.data()!['licenseNumber'], 'LIC-998877');
    });

    test('user (non-business) signup doc has no verificationStatus field', () async {
      const uid = 'user-uid-1';
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'Alex Crew',
        'email': 'alex@delta.com',
        'role': 'user',
        'isBanned': false,
        'isVerified': false,
      });
      final snap = await db.collection('users').doc(uid).get();
      expect(snap.data()!.containsKey('verificationStatus'), false);
    });
```

- [ ] **Step 2: Run the tests to verify they pass against the fake db as written**

Run: `flutter test test/providers/auth_provider_test.dart`
Expected: PASS (these are shape/contract tests against `fake_cloud_firestore` directly — they lock in the intended shape *before* touching `real_providers.dart`, matching this file's existing convention. They do not yet exercise `AuthProvider.signup()` itself.)

- [ ] **Step 3: Implement `signup()`'s new params and writes**

In `lib/shared/providers/real_providers.dart`, change the signature at line 212:

```dart
  Future<bool> signup({
    required String name, required String email, required String password,
    String? phone, String? airline, String? airport, String? position,
    String? city, String? state, String role = 'user', String? bio,
    DateTime? dob, String? ein, String? licenseNumber,
  }) async {
```

Then in the live (non-mock) branch, replace lines 244-260:

```dart
      // email/phone/dob are PII and go to the owner-only `private/data`
      // subdoc, not the main doc (any authed user can read `users/{uid}` —
      // see firestore.rules and H-2 in docs/QA_AUDIT_REPORT.md). DOB is not
      // on UserModel because most code shouldn't need it — it's stored as an
      // extra field for audit + future age verification (Apple 5.1.1, Play
      // Families policy, GDPR Article 8 / COPPA). ein/licenseNumber follow
      // the same pattern for the same reason — see the business-verification
      // signup design doc.
      final docData = user.toFirestore()..remove('email')..remove('phone');
      docData['termsAcceptedAt'] = FieldValue.serverTimestamp();
      if (role == 'business') {
        docData['verificationStatus'] = 'pending';
      }
      await _db.collection('users').doc(user.uid).set(docData);

      final privateData = <String, dynamic>{'email': email, 'phone': phone};
      if (dob != null) {
        privateData['dob'] = Timestamp.fromDate(dob);
        privateData['ageVerifiedAt'] = FieldValue.serverTimestamp();
      }
      if (ein != null && ein.isNotEmpty) privateData['ein'] = ein;
      if (licenseNumber != null && licenseNumber.isNotEmpty) {
        privateData['licenseNumber'] = licenseNumber;
      }
      await _db.collection('users').doc(user.uid)
          .collection('private').doc('data').set(privateData);
```

- [ ] **Step 4: Run the full provider test file again**

Run: `flutter test test/providers/auth_provider_test.dart`
Expected: PASS (unchanged — Step 3 doesn't change what the contract tests assert against the fake db; it changes the real, non-DI'd `signup()` method, whose actual Firestore calls this file cannot exercise, matching the file's documented limitation).

- [ ] **Step 5: Run `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/shared/providers/real_providers.dart test/providers/auth_provider_test.dart
git commit -m "feat(auth): write verificationStatus/ein/licenseNumber on business signup"
```

---

### Task 3: Signup UI collects EIN + License Number for business accounts

**Files:**
- Modify: `lib/features/auth/signup_screen.dart:60,80-81,469-472,204-212`
- Test: `test/widgets/signup_screen_test.dart`

**Interfaces:**
- Consumes: `AuthProvider.signup({..., String? ein, String? licenseNumber})` from Task 2.
- Produces: nothing new consumed by later tasks — this is a leaf UI change.

- [ ] **Step 1: Write the failing widget test**

Add to `test/widgets/signup_screen_test.dart`, inside `main()`:

```dart
  testWidgets('business signup passes EIN and License Number to signup()',
      (tester) async {
    when(() => authProvider.signup(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          city: any(named: 'city'),
          state: any(named: 'state'),
          role: any(named: 'role'),
          bio: any(named: 'bio'),
          ein: any(named: 'ein'),
          licenseNumber: any(named: 'licenseNumber'),
        )).thenAnswer((_) async => true);
    when(() => authProvider.userRole).thenReturn('business');

    await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.text('Business'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'lounge@delta.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    await _agreeToTerms(tester);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    // Business step 2 TextFields in build order (the Category dropdown is a
    // DropdownButtonFormField, not a TextField, so it doesn't occupy an
    // index): 0=Business Name, 1=Website, 2=EIN, 3=License Number, 4=City,
    // 5=State, 6=Bio. Matches this file's existing index-based convention
    // (see the step-1 email/password test above) rather than finding by
    // hint text, which isn't used anywhere else in this file.
    await tester.enterText(find.byType(TextField).at(0), 'Sky Lounge');
    await tester.enterText(find.byType(TextField).at(2), '12-3456789');
    await tester.enterText(find.byType(TextField).at(3), 'LIC-998877');

    await tester.tap(find.widgetWithText(PrimaryButton, 'Create Account'));
    await tester.pumpAndSettle();

    verify(() => authProvider.signup(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          city: any(named: 'city'),
          state: any(named: 'state'),
          role: 'business',
          bio: any(named: 'bio'),
          ein: '12-3456789',
          licenseNumber: 'LIC-998877',
        )).called(1);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/signup_screen_test.dart -N "business signup passes EIN"`
Expected: FAIL — the `verify(...)` call fails because `signup()` was never called with `ein: '12-3456789'` (the field at `TextField` index 2 doesn't exist yet, so `enterText` either throws "no widget found at index" or silently misses, and the eventual `signup()` call — once Task 2's params exist — receives `ein: null`, not the expected value).

- [ ] **Step 3: Add controllers**

In `lib/features/auth/signup_screen.dart`, after line 60 (`final _websiteCtrl = TextEditingController();`):

```dart
  final _einCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
```

- [ ] **Step 4: Dispose the new controllers**

Replace the `dispose()` body (lines 76-82):

```dart
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose();
    _phoneCtrl.dispose(); _airportCtrl.dispose(); _cityCtrl.dispose();
    _stateCtrl.dispose(); _bioCtrl.dispose();
    _bizNameCtrl.dispose(); _websiteCtrl.dispose();
    _einCtrl.dispose(); _licenseCtrl.dispose();
    super.dispose();
```

- [ ] **Step 5: Add the two fields to the business step UI**

In the business branch, after the Website field (line 471, right before the City/State `Row`):

```dart
            AppTextField(hint: 'Website (optional)', controller: _websiteCtrl,
              keyboardType: TextInputType.url,
              prefixIcon: const Icon(Icons.language_outlined, size: 20)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: AppTextField(hint: 'EIN (optional)', controller: _einCtrl,
                prefixIcon: const Icon(Icons.numbers, size: 20))),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(hint: 'License Number (optional)', controller: _licenseCtrl,
                prefixIcon: const Icon(Icons.badge_outlined, size: 20))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: AppTextField(hint: 'City', controller: _cityCtrl)),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(hint: 'State', controller: _stateCtrl)),
            ]),
```

(This replaces the existing Website field block through the existing City/State `Row` — i.e. only the new EIN/License `Row` is inserted between them, nothing else changes.)

- [ ] **Step 6: Pass the new fields through to `signup()`**

In `_submit()`, replace the business branch's call (lines 204-212):

```dart
      ok = await auth.signup(
        name: bizName,
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
        role: 'business',
        bio: bizBio.isEmpty ? null : bizBio,
        ein: _einCtrl.text.trim().isEmpty ? null : _einCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim().isEmpty ? null : _licenseCtrl.text.trim(),
      );
```

- [ ] **Step 7: Run the new test to verify it passes**

Run: `flutter test test/widgets/signup_screen_test.dart -N "business signup passes EIN"`
Expected: PASS

- [ ] **Step 8: Run the full signup screen test file to check for regressions**

Run: `flutter test test/widgets/signup_screen_test.dart`
Expected: All tests PASS, including the pre-existing `'business role hides name/phone/DOB and advances to business step 2'` test (it only counts `TextField`s on business **step 1**, which is unaffected — the new fields are on step 2).

- [ ] **Step 9: Run `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add lib/features/auth/signup_screen.dart test/widgets/signup_screen_test.dart
git commit -m "feat(auth): collect EIN + License Number on business signup"
```

---

### Task 4: Admin verification page reads back the private EIN/License fields

**Files:**
- Modify: `lib/features/admin/admin_business_verification_page.dart:26-47`

**Interfaces:**
- Consumes: `users/{uid}/private/data` subdoc written by Task 2's `signup()`.
- Produces: nothing consumed by later tasks (last task in this plan).

No test file is added for this task — see the "Global Constraints" note above: `admin_business_verification_page.dart` calls `FirebaseFirestore.instance` directly, and its sibling `admin_users_page.dart` (which merges the exact same `private/data` subdoc for the exact same email/phone reason) has no test file either, since an unmocked Firestore `.get()` in this test environment hangs rather than failing fast or returning fake data. Matching that precedent rather than inventing new test infrastructure for one page.

- [ ] **Step 1: Add the private-data merge helper**

In `lib/features/admin/admin_business_verification_page.dart`, add this method to `_AdminBusinessVerificationPageState`, right before `_fetchBusinesses()` (line 26):

```dart
  /// ein/licenseNumber live in the owner+admin-only `users/{uid}/private/data`
  /// subdoc (not the broadly-readable main doc — see the business-
  /// verification signup design doc), so fan out one extra read per row to
  /// merge them back in. Mirrors `admin_users_page.dart`'s `_withPrivateData`
  /// for the identical email/phone situation.
  Future<List<Map<String, dynamic>>> _withPrivateData(
      List<Map<String, dynamic>> docs) async {
    return Future.wait(docs.map((data) async {
      final id = data['id'] as String;
      try {
        final privateDoc = await FirebaseFirestore.instance
            .collection('users').doc(id).collection('private').doc('data').get();
        if (privateDoc.exists) return {...data, ...privateDoc.data()!};
      } catch (_) {/* fail open — card still renders without ein/license */}
      return data;
    }));
  }
```

- [ ] **Step 2: Call it from `_fetchBusinesses()`**

Replace the body of `_fetchBusinesses()` (lines 26-47):

```dart
  Future<void> _fetchBusinesses() async {
    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'business')
          .limit(100)
          .get();
      if (!mounted) return;
      final docs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      final withPrivate = await _withPrivateData(docs);
      if (!mounted) return;
      setState(() {
        _businesses = withPrivate;
      });
    } catch (e) {
      debugPrint('[AdminBusinessVerify] fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
```

- [ ] **Step 3: Run `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: All tests pass (baseline was 354/354 per the last recorded run in `docs/QA_AUDIT_REPORT.md`; this task adds 2 tests in Task 2 and 1 in Task 3, so expect 357/357 — confirm the exact count in the terminal output rather than assuming it).

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/admin_business_verification_page.dart
git commit -m "feat(admin): surface EIN/License Number on business verification cards"
```

---

## After this plan

- `firestore.rules` is not deployed by this plan (Task 1 explicitly stops short of `firebase deploy`). Deploying is a separate, explicit step the user should confirm — same as every other rules change in this repo's history.
- Two things explicitly deferred (per the approved design doc): document upload at signup, and an in-app resubmission flow for rejected/info-requested businesses.
