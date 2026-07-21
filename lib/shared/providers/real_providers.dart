import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import '../utils/account_deletion.dart';
import '../utils/image_compress.dart';
import '../utils/report_rate_limiter.dart';
import '../models/models.dart';
import '../mock/mock_data.dart';

// ─── Mock credentials (used when isMock = true) ───────────────
const _mockCredentials = {
  'user@flyconnect.com':    ('user123',    'user'),
  'sarah@flyconnect.com':   ('sarah123',   'user'),
  'business@flyconnect.com':('business123','business'),
  'emirates@flyconnect.com':('emirates123','business'),
  // Unverified business — exercises the "pending verification" create-gate
  // (create_promotion_screen.dart, create_event_screen.dart,
  // create_group_screen.dart); the other two mock business accounts are
  // both verified, so there was previously no way to test this path without
  // hitting real Firebase.
  'newbiz@flyconnect.com':  ('newbiz123',  'business'),
};

UserModel _mockUserModelFor(String email, String role) {
  switch (email) {
    case 'sarah@flyconnect.com':
      return UserModel(
        uid: 'user_007', name: 'Sarah Mitchell', email: email,
        airline: 'British Airways', position: 'Flight Attendant',
        airport: 'LHR', city: 'London', state: 'England',
        bio: 'Cabin crew with a passion for discovering hidden gems 🌍',
        hobbies: ['Travel','Photography','Yoga','Reading'],
        matchType: 'buddy', followerCount: 843, followingCount: 210, postCount: 31,
        passportStamps: ['GB','US','FR','IT','JP','AU','AE','TH'],
        travelHistory: ['New York','Paris','Tokyo','Sydney'],
        isVerified: true, role: 'user',
        createdAt: DateTime.now().subtract(const Duration(days: 220)),
        photoUrl: 'https://i.pravatar.cc/200?img=25',
      );
    case 'business@flyconnect.com':
      return UserModel(
        uid: 'biz_001', name: 'Sky Lounge NYC', email: email,
        role: 'business', position: 'Airport Lounge', airport: 'JFK',
        city: 'New York', state: 'NY',
        bio: 'Premium airport lounge at JFK Terminal 4.',
        photoUrl: 'https://picsum.photos/seed/lounge/200',
        followerCount: 2840, followingCount: 0, postCount: 12,
        passportStamps: [], travelHistory: [], hobbies: [],
        isVerified: true, createdAt: DateTime.now().subtract(const Duration(days: 180)),
      );
    case 'emirates@flyconnect.com':
      return UserModel(
        uid: 'biz_002', name: 'Emirates Business Lounge', email: email,
        role: 'business', position: 'Airlines', airport: 'DXB',
        city: 'Dubai', state: 'Dubai',
        bio: 'Official Emirates lounge at Dubai International.',
        photoUrl: 'https://picsum.photos/seed/emirates/200',
        followerCount: 5120, followingCount: 0, postCount: 28,
        passportStamps: [], travelHistory: [], hobbies: [],
        isVerified: true, createdAt: DateTime.now().subtract(const Duration(days: 300)),
      );
    default: // user@flyconnect.com and any other email
      return UserModel(
        uid: 'user_001', name: 'Alex Johnson', email: email,
        airline: 'Delta Air Lines', position: 'Pilot',
        airport: 'JFK', city: 'New York', state: 'NY',
        bio: 'Senior pilot with 12 years of experience ✈️',
        hobbies: ['Photography','Hiking','Coffee','Travel','Fitness'],
        matchType: 'buddy', followerCount: 1284, followingCount: 342, postCount: 47,
        passportStamps: ['US','GB','JP','FR','DE','AU','TH','AE','SG','IT'],
        travelHistory: ['London','Tokyo','Paris','Berlin','Sydney'],
        isVerified: true, role: 'user',
        createdAt: DateTime.now().subtract(const Duration(days: 365)),
        photoUrl: 'https://i.pravatar.cc/200?img=11',
      );
  }
}

/// Fetches `users/{uid}` plus its owner-only `private/data` subdoc (email,
/// phone, fcmToken) and merges them into one [UserModel] — only valid for the
/// SIGNED-IN user's own uid, since `private/data` is owner-read-only. Fetching
/// another user's uid here would just have the private read silently return
/// nothing (not an error) and behave like a plain doc fetch.
Future<UserModel?> _fetchSelfWithPrivate(FirebaseFirestore db, String uid) async {
  final doc = await db.collection('users').doc(uid).get();
  if (!doc.exists) return null;
  final data = Map<String, dynamic>.from(doc.data()!);
  final privateDoc =
      await db.collection('users').doc(uid).collection('private').doc('data').get();
  if (privateDoc.exists) data.addAll(privateDoc.data()!);
  // Same Timestamp handling as UserModel.fromFirestore.
  if (data['createdAt'] is Timestamp) data['createdAt'] = (data['createdAt'] as Timestamp).toDate();
  if (data['lastSeen'] is Timestamp) data['lastSeen'] = (data['lastSeen'] as Timestamp).toDate();
  return UserModel.fromMap(data, uid);
}

// ─── Real Auth Provider ──────────────────────────────────────
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  UserModel? _currentUser;
  bool _loading = false;
  String? _error;

  // When true, login uses mock credentials instead of Firebase Auth
  final bool isMock;

  UserModel? get currentUser => _currentUser;
  dynamic get firebaseUser => isMock ? _currentUser : _auth.currentUser;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn => isMock ? _currentUser != null : _auth.currentUser != null;
  String get userRole => _currentUser?.role ?? 'user';

  StreamSubscription<User?>? _authSub;

  // Completes once the first authStateChanges event has been fully handled
  // (including the Firestore role fetch for a logged-in user). SplashScreen
  // awaits this before reading userRole so it doesn't route on the 'user'
  // default while _fetchUser is still in flight.
  final Completer<void> _authReadyCompleter = Completer<void>();
  Future<void> get authReady => _authReadyCompleter.future;

  AuthProvider({this.isMock = false}) {
    if (!isMock) {
      _authSub = _auth.authStateChanges().listen((user) async {
        if (user != null) {
          await _fetchUser(user.uid);
        } else {
          _currentUser = null;
        }
        if (!_authReadyCompleter.isCompleted) _authReadyCompleter.complete();
        notifyListeners();
      });
    } else {
      _authReadyCompleter.complete();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchUser(String uid) async {
    final user = await _fetchSelfWithPrivate(_db, uid);
    if (user != null) {
      _currentUser = user;
    }
  }

  Future<bool> login(String email, String password) async {
    _loading = true; _error = null; notifyListeners();

    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 600));
      final entry = _mockCredentials[email.trim().toLowerCase()];
      if (entry != null && entry.$1 == password) {
        _currentUser = _mockUserModelFor(email.trim().toLowerCase(), entry.$2);
        _loading = false; notifyListeners();
        return true;
      }
      // Any unrecognised email/password still logs in as the default user
      _currentUser = _mockUserModelFor(email.trim().toLowerCase(), 'user');
      _loading = false; notifyListeners();
      return true;
    }

    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      await _fetchUser(cred.user!.uid);
      // SOC 2 / audit posture: every admin sign-in lands in the audit
      // log so reviewers can spot credential stuffing or off-hours
      // access. Regular-user sign-ins are skipped to keep the log
      // signal high.
      if (_currentUser?.role == 'admin') {
        try {
          await _db.collection('audit_log').add({
            'adminId': cred.user!.uid,
            'adminName': _currentUser?.name ?? email,
            'action': 'admin_signin',
            'targetType': 'session',
            'targetId': cred.user!.uid,
            'details': 'Admin signed in via email/password',
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (_) {/* silent: best-effort */}
      }
      _loading = false; notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Login failed';
      _loading = false; notifyListeners();
      return false;
    } catch (e) {
      _error = 'Login failed. Please check your connection and try again.';
      _loading = false; notifyListeners();
      return false;
    }
  }

  Future<bool> signup({
    required String name, required String email, required String password,
    String? phone, String? airline, String? airport, String? position,
    String? city, String? state, String role = 'user', String? bio,
    DateTime? dob, String? ein, String? licenseNumber,
  }) async {
    _loading = true; _error = null; notifyListeners();

    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 600));
      _currentUser = UserModel(
        uid: 'mock_new_${DateTime.now().millisecondsSinceEpoch}',
        name: name, email: email, phone: phone,
        airline: airline, airport: airport, position: position,
        city: city, state: state, role: role, bio: bio,
        createdAt: DateTime.now(),
        hobbies: [], passportStamps: [], travelHistory: [],
      );
      _loading = false; notifyListeners();
      return true;
    }

    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await cred.user!.updateDisplayName(name);
      final user = UserModel(
        uid: cred.user!.uid, name: name, email: email, phone: phone,
        airline: airline, airport: airport, position: position,
        city: city, state: state, role: role, bio: bio,
        createdAt: DateTime.now(),
        hobbies: [], passportStamps: [], travelHistory: [],
      );
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
      _currentUser = user;
      _loading = false; notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Signup failed';
      _loading = false; notifyListeners();
      return false;
    } catch (e) {
      _error = 'Signup failed. Please check your connection and try again.';
      _loading = false; notifyListeners();
      return false;
    }
  }

  void switchUser(UserModel user) {
    _currentUser = user;
    notifyListeners();
  }

  /// Deletes the user's Firestore data and the FirebaseAuth user itself.
  /// Required by Google Play Store (since May 2024) and Apple App Store.
  ///
  /// Steps:
  /// 1. Verify the sign-in is recent enough for `user.delete()` to succeed \u2014
  ///    BEFORE erasing anything (see below)
  /// 2. Erase Firestore data via [purgeUserData], user doc last
  /// 3. Sign the user out of Google / Apple
  /// 4. Call `FirebaseAuth.currentUser!.delete()`
  ///
  /// Ordering is the point. The original deleted `users/{uid}` first and called
  /// `user.delete()` last, so the common `requires-recent-login` failure left
  /// the profile destroyed and the Auth account alive \u2014 a signed-in user with
  /// no profile document and no way back. The freshness pre-flight now fails
  /// the operation before anything is erased.
  ///
  /// Returns `true` on success. On a stale session, sets `_error` and returns
  /// `false` having changed nothing.
  Future<bool> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      _error = 'You must be signed in to delete your account.';
      notifyListeners();
      return false;
    }
    final uid = user.uid;

    // 1. Pre-flight. Firebase rejects delete() on a session older than a few
    // minutes. Checking first keeps a doomed call from destroying data.
    final lastSignIn = user.metadata.lastSignInTime;
    if (lastSignIn == null ||
        DateTime.now().difference(lastSignIn) > _recentLoginWindow) {
      _error = 'For your security, please sign out and sign in again, '
          'then delete your account. Nothing has been deleted.';
      notifyListeners();
      return false;
    }

    _loading = true; _error = null; notifyListeners();

    try {
      // 2. Erase Firestore data (user doc last \u2014 see purgeUserData).
      await purgeUserData(_db, uid);

      // 3. Sign out of Google (native only)
      if (!kIsWeb) {
        try { await GoogleSignIn().signOut(); } catch (_) {}
      }

      // 4. Delete the Firebase Auth user
      await user.delete();

      _currentUser = null;
      _loading = false; notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Should be unreachable thanks to the pre-flight, but a session can
        // still age out mid-operation. The data is already gone at this point,
        // so say so rather than implying a clean retry.
        _error = 'Your data was removed, but the sign-in could not be deleted. '
            'Sign in again and retry to finish removing your account.';
      } else {
        _error = e.message ?? 'Could not delete account.';
      }
      _loading = false; notifyListeners();
      return false;
    } catch (e) {
      _error = 'Could not delete account: $e';
      _loading = false; notifyListeners();
      return false;
    }
  }

  /// How recent a sign-in must be for `user.delete()` to be accepted. Firebase
  /// does not document an exact figure; 5 minutes is the widely used value and
  /// errs toward asking the user to re-authenticate rather than toward
  /// destroying data on a call that will be refused.
  static const Duration _recentLoginWindow = Duration(minutes: 5);


  Future<bool> resetPassword(String email) async {
    _loading = true; _error = null; notifyListeners();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      _loading = false; notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Failed to send reset email';
      _loading = false; notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to send reset email: $e';
      _loading = false; notifyListeners();
      return false;
    }
  }

  Future<bool> logout() async {
    _error = null;
    if (isMock) {
      _currentUser = null;
      notifyListeners();
      return true;
    }
    try {
      if (!kIsWeb) {
        // Sign out of Google too on native, otherwise re-login skips picker.
        try { await GoogleSignIn().signOut(); } catch (_) {}
      }
      await _auth.signOut();
      _currentUser = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Logout failed. Please check your connection and try again.';
      notifyListeners();
      return false;
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────
  // Web: uses signInWithPopup (no extra package config needed).
  // Mobile: uses google_sign_in package — requires:
  //   • iOS: REVERSED_CLIENT_ID added to Info.plist URL Schemes
  //   • Android: SHA-1 fingerprint added to Firebase Console
  //   • Firebase Console: Google sign-in provider enabled
  Future<bool> signInWithGoogle({String role = 'user'}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      UserCredential cred;
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        cred = await _auth.signInWithPopup(provider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          _loading = false; notifyListeners();
          return false; // user cancelled
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        cred = await _auth.signInWithCredential(credential);
      }

      await _ensureUserDoc(cred.user!, provider: 'google', role: role);
      _loading = false; notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Google sign-in failed';
      _loading = false; notifyListeners();
      return false;
    } catch (e) {
      _error = 'Google sign-in failed: $e';
      _loading = false; notifyListeners();
      return false;
    }
  }

  // ── Apple Sign-In ──────────────────────────────────────────
  // iOS native: uses the bundle id as the client (no Services ID needed).
  // Web/Android: use Apple's web OAuth flow via the Services ID below.
  //
  // NOTE: this Services ID must exist in the Apple Developer portal
  // (Identifiers → Services IDs) with "Sign in with Apple" configured for
  // primary App ID com.urbansyncinnovations.flyconnect and the redirect URL
  // below registered as a Return URL. It is NOT the bundle id.
  static const _appleServicesId = 'com.urbansyncinnovations.flyconnect.signin';
  static const _appleRedirectUri =
      'https://flyconnect-ab4f2.firebaseapp.com/__/auth/handler';

  Future<bool> signInWithApple({String role = 'user'}) async {
    _loading = true; _error = null; notifyListeners();
    try {
      UserCredential cred;
      if (kIsWeb) {
        final provider = OAuthProvider('apple.com')
          ..addScope('email')
          ..addScope('name');
        cred = await _auth.signInWithPopup(provider);
      } else {
        // Generate cryptographic nonce for replay protection
        final rawNonce = _generateNonce();
        final nonce = _sha256(rawNonce);

        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: nonce,
          // Android has no native Apple SDK — it must use Apple's web OAuth
          // flow, which needs the Services ID as the client + the Firebase
          // callback as the return URL. iOS uses the native sheet and ignores
          // this, so only pass it on Android.
          webAuthenticationOptions:
              defaultTargetPlatform == TargetPlatform.android
                  ? WebAuthenticationOptions(
                      clientId: _appleServicesId,
                      redirectUri: Uri.parse(_appleRedirectUri),
                    )
                  : null,
        );

        // ── Diagnostic (Phase 1 evidence) ──────────────────────────
        // Decode the Apple idToken to see the exact claims Firebase validates:
        //   aud  must == our bundle id (com.urbansyncinnovations.flyconnect)
        //   iss  must == https://appleid.apple.com
        //   nonce claim must == sha256(rawNonce)
        //   exp  must be in the future
        // Whichever is wrong is why Firebase returns invalid-credential.
        assert(() {
          final tok = appleCredential.identityToken;
          debugPrint('[AppleSignIn] identityToken present: ${tok != null} '
              '(len=${tok?.length ?? 0}); '
              'authCode present: ${appleCredential.authorizationCode.isNotEmpty}; '
              'rawNonce len: ${rawNonce.length}');
          if (tok != null) {
            final c = _decodeJwtPayload(tok);
            debugPrint('[AppleSignIn] claims: aud=${c['aud']} iss=${c['iss']} '
                'sub=${c['sub']} exp=${c['exp']} '
                'nonceClaim=${c['nonce']} '
                'nonce==sha256(raw)? ${c['nonce'] == _sha256(rawNonce)}');
          }
          return true;
        }());

        final oauthCredential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce,
        );
        cred = await _auth.signInWithCredential(oauthCredential);

        // Apple only provides name on first sign-in
        final displayName = [
          appleCredential.givenName,
          appleCredential.familyName
        ].where((p) => p != null && p.isNotEmpty).join(' ');
        if (displayName.isNotEmpty && cred.user!.displayName == null) {
          await cred.user!.updateDisplayName(displayName);
        }
      }

      await _ensureUserDoc(cred.user!, provider: 'apple', role: role);
      _loading = false; notifyListeners();
      return true;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        _loading = false; notifyListeners();
        return false;
      }
      _error = 'Apple sign-in failed: ${e.message}';
      _loading = false; notifyListeners();
      return false;
    } on FirebaseAuthException catch (e) {
      // The CODE is the diagnostic field; the message is generic.
      assert(() {
        debugPrint('[AppleSignIn] FirebaseAuthException '
            'code=${e.code} message=${e.message}');
        return true;
      }());
      _error = _describeAppleAuthError(e.code) ?? e.message ?? 'Apple sign-in failed';
      _loading = false; notifyListeners();
      return false;
    } catch (e) {
      _error = 'Apple sign-in failed: $e';
      _loading = false; notifyListeners();
      return false;
    }
  }

  // Create the Firestore user doc on first OAuth sign-in.
  // `role` is honored only when the doc doesn't yet exist (first-time login).
  // Existing users keep whatever role they already have.
  Future<void> _ensureUserDoc(User user,
      {required String provider, String role = 'user'}) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) {
      _currentUser = UserModel.fromFirestore(snap);
      // Update lastSeen on every login
      await ref.update({'lastSeen': Timestamp.now()});
      return;
    }
    final newUser = UserModel(
      uid: user.uid,
      name: user.displayName ?? user.email?.split('@').first ?? 'New User',
      email: user.email ?? '',
      photoUrl: user.photoURL,
      role: role,
      createdAt: DateTime.now(),
      hobbies: [],
      passportStamps: [],
      travelHistory: [],
    );
    final docData = newUser.toFirestore();
    if (role == 'business') {
      docData['verificationStatus'] = 'pending';
    }
    await ref.set(docData);
    _currentUser = newUser;
  }

  // ── Helpers for Apple nonce ────────────────────────────────
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  // Decode a JWT payload (base64url) — diagnostics only, no verification.
  Map<String, dynamic> _decodeJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return const {};
    var p = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    p = p.padRight(p.length + ((4 - p.length % 4) % 4), '=');
    try {
      return json.decode(utf8.decode(base64.decode(p))) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  // ── Map a FirebaseAuthException.code to an actionable Apple message ──
  // TODO(you): translate the raw code into guidance. This is a real UX /
  // diagnostics decision — what does the END USER see vs. what helps YOU
  // debug? Codes worth handling:
  //   • 'operation-not-allowed' → Apple provider is OFF in Firebase Console
  //   • 'invalid-credential'    → nonce / token mismatch or expired token
  //   • 'internal-error'        → Apple Developer App ID "Sign In with Apple"
  //                               capability / grouping (carries the
  //                               "Invalid OAuth response from apple.com" text)
  // Return a string to override the generic message, or null to fall back.
  String? _describeAppleAuthError(String code) {
    // TODO: implement the mapping (5-10 lines).
    return null;
  }
}

// ─── Real User Provider ──────────────────────────────────────
class UserProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  UserModel? _currentUser;
  final Set<String> _following = {};

  UserModel? get currentUser => _currentUser;
  bool get loading => false;

  UserProvider({this.isMock = false}) {
    if (isMock) _following.addAll({'user_002', 'user_006'});
  }

  void updateAuth(AuthProvider auth) {
    _currentUser = auth.currentUser;
    notifyListeners();
  }

  Future<UserModel?> fetchUser(String uid) async {
    if (isMock) {
      if (uid == 'mock_alex' || uid == 'user_001') return mockCurrentUser;
      if (uid == 'mock_biz1' || uid == 'biz_001') return mockBusinessUser;
      if (uid == 'mock_biz2' || uid == 'biz_002') return mockBusinessUser2;
      if (uid == 'mock_sarah' || uid == 'user_007') return mockCurrentUser2;
      return mockUsers.where((u) => u.uid == uid).firstOrNull;
    }
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    if (isMock) { await Future.delayed(const Duration(milliseconds: 300)); notifyListeners(); return; }
    await _db.collection('users').doc(uid).update(data);
    if (_currentUser != null && uid == _currentUser!.uid) {
      final user = await _fetchSelfWithPrivate(_db, uid);
      if (user != null) _currentUser = user;
    }
    notifyListeners();
  }

  /// Upload a profile avatar and return its download URL (null in mock / when
  /// signed out). Stored at `profile_photos/{uid}/avatar.png` — the two-segment
  /// path matches the `profile_photos/{uid}/{file=**}` rule in storage.rules so
  /// `isOwner(uid)` resolves to the real uid (a single-segment `{uid}.png` path
  /// would capture the extension into {uid} and fail the owner check). Errors
  /// propagate so the caller can surface them instead of silently dropping the
  /// photo. Mirrors [PostProvider.uploadPostImage].
  Future<String?> uploadProfilePhoto(Uint8List bytes) async {
    if (isMock) return null;
    final uid = _currentUser?.uid;
    if (uid == null) return null;
    final compressed = await compressForUpload(bytes, maxDimension: 1024);
    final ref = FirebaseStorage.instance.ref('profile_photos/$uid/avatar.png');
    await ref.putData(compressed, SettableMetadata(contentType: 'image/png'));
    return await ref.getDownloadURL();
  }

  /// Stories (M-6: was RAM-only via a `StoryState` singleton — lost on app
  /// restart, and never visible to anyone else since nothing ever read it
  /// back). Deliberately "mine-only": one current-story doc per user, no
  /// expiry/viewer-tracking/multi-user feed — a real stories feed is a much
  /// bigger, separate feature. Mirrors [uploadProfilePhoto]'s storage-path
  /// convention.
  Future<String?> getMyStory(String uid) async {
    if (isMock) return null;
    final doc = await _db.collection('stories').doc(uid).get();
    return doc.data()?['imageUrl'] as String?;
  }

  Future<String?> postStory(Uint8List bytes) async {
    if (isMock) return null;
    final uid = _currentUser?.uid;
    if (uid == null) return null;
    final compressed = await compressForUpload(bytes, maxDimension: 1080);
    final ref = FirebaseStorage.instance
        .ref('user_uploads/$uid/stories/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _db.collection('stories').doc(uid).set({
      'imageUrl': url,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return url;
  }

  Future<void> removeStory(String uid) async {
    if (isMock) return;
    final ref = _db.collection('stories').doc(uid);
    final url = (await ref.get()).data()?['imageUrl'] as String?;
    await ref.delete();
    // Best-effort — mirrors deletePost's swallow-and-continue storage cleanup.
    if (url != null) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }
  }

  /// Match preferences live under users/{uid}.matchPrefs (a nested map) so they
  /// sync across devices. The `matchPrefs` key is whitelisted in firestore.rules.
  Future<Map<String, dynamic>> getMatchPrefs(String uid) async {
    if (isMock) return {};
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?['matchPrefs'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> saveMatchPrefs(String uid, Map<String, dynamic> prefs) =>
      updateProfile(uid, {'matchPrefs': prefs});

  /// Notification + privacy toggles from the Settings screen, stored as a raw
  /// map under `users/{uid}.settings` — same shape as [saveMatchPrefs].
  Future<void> saveSettings(String uid, Map<String, dynamic> settings) =>
      updateProfile(uid, {'settings': settings});

  /// Persists the viewer's own current position so other users' Nearby
  /// queries can compute a real distance to them. Callers are responsible
  /// for the privacy gating (only call this when 'shareLocation' is on, and
  /// pass an already-fuzzed coordinate when 'approxLocationOnly' is on) —
  /// see nearby_users_screen.dart. This method is a pure "write these two
  /// numbers" call, same shape as [saveSettings].
  Future<void> updateMyLocation(String uid, double lat, double lng) =>
      updateProfile(uid, {'lat': lat, 'lng': lng});

  Future<void> followUser(String targetUid) async {
    if (isMock) { _following.add(targetUid); notifyListeners(); return; }
    final uid = _currentUser?.uid;
    if (uid == null) return;
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid).collection('following').doc(targetUid),
      {'followedAt': Timestamp.now()});
    batch.set(_db.collection('users').doc(targetUid).collection('followers').doc(uid),
      {'followedAt': Timestamp.now()});
    batch.update(_db.collection('users').doc(uid), {'followingCount': FieldValue.increment(1)});
    batch.update(_db.collection('users').doc(targetUid), {'followerCount': FieldValue.increment(1)});
    await batch.commit();
    notifyListeners();
  }

  Future<void> unfollowUser(String targetUid) async {
    if (isMock) { _following.remove(targetUid); notifyListeners(); return; }
    final uid = _currentUser?.uid;
    if (uid == null) return;
    final batch = _db.batch();
    batch.delete(_db.collection('users').doc(uid).collection('following').doc(targetUid));
    batch.delete(_db.collection('users').doc(targetUid).collection('followers').doc(uid));
    batch.update(_db.collection('users').doc(uid), {'followingCount': FieldValue.increment(-1)});
    batch.update(_db.collection('users').doc(targetUid), {'followerCount': FieldValue.increment(-1)});
    await batch.commit();
    notifyListeners();
  }

  Future<bool> isFollowing(String targetUid) async {
    if (isMock) return _following.contains(targetUid);
    final uid = _currentUser?.uid;
    if (uid == null) return false;
    final doc = await _db.collection('users').doc(uid).collection('following').doc(targetUid).get();
    return doc.exists;
  }
}

// ─── Real Post Provider ──────────────────────────────────────
class PostProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<PostModel> _feed = [];
  final Set<String> _liked = {};
  final Set<String> _saved = {};
  final bool _loading = false;
  String? _feedError;
  AuthProvider? _storedAuth;

  bool get loading => _loading;
  List<PostModel> get feed => _feed;

  /// Post ids the signed-in user has liked (as tracked this session +
  /// resolved via [isLiked]). Backs the profile "Liked" grid so it shows
  /// only liked posts instead of the whole feed.
  Set<String> get likedPostIds => _liked;

  /// Non-null when the feed stream has reported a failure. Cleared on
  /// every successful re-subscribe via [listenFeed].
  String? get feedError => _feedError;

  String? get _uid => isMock ? (_storedAuth?.currentUser?.uid ?? 'user_001') : _auth.currentUser?.uid;
  StreamSubscription? _feedSub;

  PostProvider({this.isMock = false}) {
    if (isMock) {
      _feed = List.from(mockPosts);
      _liked.add('post_003');
    }
  }

  void updateAuth(AuthProvider auth) {
    _storedAuth = auth;
    if (isMock) return;
  }

  // Feed pagination via "growing window" — each loadMore press bumps
  // the limit and re-subscribes. The active page is always streamed
  // (real-time updates to existing posts) and older pages keep flowing
  // through the same stream. Simpler than splitting hot vs cold pages
  // and good enough until we hit ~500 posts loaded.
  static const int _feedPageSize = 25;
  int _feedLimit = _feedPageSize;
  bool _feedHasMore = true;
  bool _feedLoadingMore = false;

  bool get feedHasMore => _feedHasMore;
  bool get feedLoadingMore => _feedLoadingMore;

  void listenFeed() {
    if (isMock) { _feed = List.from(mockPosts); notifyListeners(); return; }
    _feedSub?.cancel();
    _feedLimit = _feedPageSize;
    _feedHasMore = true;
    // Clear any prior error so the InlineErrorBanner disappears once the
    // user taps Retry; if the new subscription also fails, onError below
    // will set it again.
    _feedError = null;
    _resubscribeFeed();
  }

  void _resubscribeFeed() {
    _feedSub?.cancel();
    // The audience filter is REQUIRED, not an optimisation: firestore.rules
    // only admits a posts query that is provably limited to public posts, and
    // Firestore rejects the whole query otherwise. Dropping this `where` makes
    // the feed fail with permission-denied rather than over-fetch.
    _feedSub = _db.collection('posts')
        .where('audience', isEqualTo: 'Everyone')
        .orderBy('createdAt', descending: true)
        .limit(_feedLimit)
        .snapshots()
        .listen((snap) {
      _feed = snap.docs.map((d) => PostModel.fromFirestore(d)).toList();
      // If we got fewer than the limit, there's nothing more to fetch.
      _feedHasMore = _feed.length >= _feedLimit;
      _feedLoadingMore = false;
      // Successful snapshot clears any prior error.
      if (_feedError != null) _feedError = null;
      notifyListeners();
    }, onError: (Object err) {
      // Surface the failure to the UI via [feedError]. We keep whatever
      // posts were already in [_feed] so the screen doesn't blank out.
      _feedError = 'Could not load the feed.';
      _feedLoadingMore = false;
      notifyListeners();
    });
  }

  /// Grow the feed window by one page. Safe to call multiple times.
  Future<void> loadMoreFeed() async {
    if (isMock) return;
    if (_feedLoadingMore || !_feedHasMore) return;
    _feedLoadingMore = true;
    notifyListeners();
    _feedLimit += _feedPageSize;
    _resubscribeFeed();
    // _feedLoadingMore flips back to false in the snapshot callback above.
  }

  Future<void> likePost(String postId) async {
    _liked.add(postId);
    if (isMock) {
      final i = _feed.indexWhere((p) => p.id == postId);
      if (i != -1) {
        final p = _feed[i];
        _feed[i] = PostModel(id: p.id, authorId: p.authorId, authorName: p.authorName,
          authorPhotoUrl: p.authorPhotoUrl, caption: p.caption, mediaUrls: p.mediaUrls,
          mediaType: p.mediaType, location: p.location, likeCount: p.likeCount + 1,
          commentCount: p.commentCount, createdAt: p.createdAt);
      }
      notifyListeners(); return;
    }
    if (_uid == null) return;
    await _db.collection('posts').doc(postId).collection('likes').doc(_uid).set({'likedAt': Timestamp.now()});
    await _db.collection('posts').doc(postId).update({'likeCount': FieldValue.increment(1)});
    // No notifyListeners(): the card toggles optimistically and the feed
    // snapshot reflects the new likeCount on its own. Notifying here would
    // rebuild every feed card redundantly.
  }

  Future<void> unlikePost(String postId) async {
    _liked.remove(postId);
    if (isMock) {
      final i = _feed.indexWhere((p) => p.id == postId);
      if (i != -1) {
        final p = _feed[i];
        _feed[i] = PostModel(id: p.id, authorId: p.authorId, authorName: p.authorName,
          authorPhotoUrl: p.authorPhotoUrl, caption: p.caption, mediaUrls: p.mediaUrls,
          mediaType: p.mediaType, location: p.location, likeCount: (p.likeCount - 1).clamp(0, 9999),
          commentCount: p.commentCount, createdAt: p.createdAt);
      }
      notifyListeners(); return;
    }
    if (_uid == null) return;
    await _db.collection('posts').doc(postId).collection('likes').doc(_uid).delete();
    await _db.collection('posts').doc(postId).update({'likeCount': FieldValue.increment(-1)});
    // No notifyListeners(): see likePost — the card and feed snapshot already
    // cover this; an extra notify just rebuilds the whole feed.
  }

  Future<bool> isLiked(String postId) async {
    if (_liked.contains(postId)) return true;
    if (isMock) return false;
    if (_uid == null) return false;
    final doc = await _db.collection('posts').doc(postId).collection('likes').doc(_uid).get();
    if (doc.exists) _liked.add(postId);
    return doc.exists;
  }

  /// Single-document fetch by id — used by the `/posts/:postId` deep link
  /// (notification taps), which can't assume the post is already in [feed].
  /// Returns null only when the post genuinely doesn't exist; a network/
  /// transient failure is left to throw so the caller can offer a retry
  /// instead of silently showing "not found" (see PostByIdScreen).
  Future<PostModel?> getPost(String postId) async {
    if (isMock) return _feed.where((p) => p.id == postId).firstOrNull;
    final doc = await _db.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    return PostModel.fromFirestore(doc);
  }

  // ── Saved / Bookmarked posts ────────────────────────────────

  Future<void> savePost(String postId) async {
    _saved.add(postId);
    if (isMock) { notifyListeners(); return; }
    if (_uid == null) return;
    await _db.collection('users').doc(_uid).collection('savedPosts').doc(postId).set({'savedAt': Timestamp.now()});
    notifyListeners();
  }

  Future<void> unsavePost(String postId) async {
    _saved.remove(postId);
    if (isMock) { notifyListeners(); return; }
    if (_uid == null) return;
    await _db.collection('users').doc(_uid).collection('savedPosts').doc(postId).delete();
    notifyListeners();
  }

  Future<bool> isSaved(String postId) async {
    if (_saved.contains(postId)) return true;
    if (isMock) return false;
    if (_uid == null) return false;
    final doc = await _db.collection('users').doc(_uid).collection('savedPosts').doc(postId).get();
    if (doc.exists) _saved.add(postId);
    return doc.exists;
  }

  /// The signed-in user's saved posts, newest-saved first. `savedPosts` docs
  /// only store `{savedAt}` (see [savePost]), so this re-fetches the actual
  /// `posts` docs on every bookmark-list change rather than filtering
  /// whatever happens to already be in [feed] — a saved post can easily have
  /// scrolled out of the feed's loaded window.
  Stream<List<PostModel>> watchSavedPosts() {
    if (isMock) return Stream.value(const []);
    if (_uid == null) return Stream.value(const []);
    return _db.collection('users').doc(_uid).collection('savedPosts')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .asyncMap((snap) async {
      final ids = snap.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return <PostModel>[];
      // Fetched one document at a time rather than with whereIn(documentId).
      // The posts read rule admits a query only when it is provably limited to
      // public or own posts; a whereIn on document ids proves neither, so the
      // batched form now fails wholesale. Single-document gets are evaluated
      // against the actual document, so each saved post succeeds or fails on
      // its own — a post that was made private after being saved is skipped
      // instead of breaking the whole screen.
      final results = await Future.wait(ids.map((id) async {
        try {
          final doc = await _db.collection('posts').doc(id).get();
          return doc.exists ? PostModel.fromFirestore(doc) : null;
        } catch (_) {
          return null; // no longer visible to this user
        }
      }));
      // Preserve savedAt order, which ids already carries.
      return results.whereType<PostModel>().toList();
    });
  }

  Stream<List<CommentModel>> watchComments(String postId) {
    if (isMock) {
      return Stream.value([
      CommentModel(id: 'c1', postId: postId, authorId: 'user_002',
        authorName: 'Maria Chen', text: 'This is amazing! 🔥',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30))),
      CommentModel(id: 'c2', postId: postId, authorId: 'user_003',
        authorName: 'James Wright', text: 'So inspiring! Congrats 🎉',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15))),
    ]);
    }
    return _db.collection('posts').doc(postId).collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map((d) => CommentModel.fromFirestore(d)).toList());
  }

  Future<void> addComment(String postId, String text) async {
    if (isMock) return;
    if (_uid == null) return;
    final user = _auth.currentUser!;
    final ref = _db.collection('posts').doc(postId).collection('comments').doc();
    await ref.set({
      'postId': postId, 'authorId': _uid, 'authorName': user.displayName ?? 'User',
      'text': text, 'likeCount': 0, 'createdAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('posts').doc(postId).update({'commentCount': FieldValue.increment(1)});
  }

  /// Delete a comment. Firestore rules only allow this for the comment's own
  /// author (`isOwner(resource.data.authorId)`) or an admin — mirrors
  /// [addComment]'s counter update in reverse.
  Future<void> deleteComment(String postId, String commentId) async {
    if (isMock) return;
    if (_uid == null) return;
    await _db.collection('posts').doc(postId).collection('comments').doc(commentId).delete();
    await _db.collection('posts').doc(postId).update({'commentCount': FieldValue.increment(-1)});
  }

  // Client-side defence against report-spamming. See
  // lib/shared/utils/report_rate_limiter.dart for the policy.
  final ReportRateLimiter _reportLimiter = ReportRateLimiter();

  /// Thrown when the user submits reports too fast. UI catches this and
  /// shows a friendly "please wait" SnackBar.
  static const String reportRateLimitError =
      ReportRateLimiter.tooFastMessage;

  Future<void> reportPost(String postId, {String? reason}) async {
    if (isMock) return;
    if (!_reportLimiter.tryConsume()) {
      throw Exception(reportRateLimitError);
    }
    // 1. Flag the post itself so it surfaces in the moderation queue
    await _db.collection('posts').doc(postId).update({
      'reportCount': FieldValue.increment(1), 'isReported': true,
    });
    // 2. Persist a detailed report record for Apple 1.2 / Play UGC compliance
    await _db.collection('reports').add({
      'targetType': 'post',
      'targetId': postId,
      'reporterId': _uid,
      'reason': reason ?? 'Inappropriate content',
      'status': 'pending',      // pending | reviewed | actioned | dismissed
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a post the signed-in user owns. Firestore rules enforce the
  /// owner-or-admin check server-side (`isOwner(resource.data.authorId)`) —
  /// this only needs to clean up what the rules don't cascade automatically:
  /// the comments/likes subcollections and the uploaded media.
  Future<void> deletePost(String postId,
      {List<String> mediaUrls = const [], String? thumbnailUrl}) async {
    if (isMock) return;
    if (_uid == null) return;
    final postRef = _db.collection('posts').doc(postId);

    final batch = _db.batch();
    final comments = await postRef.collection('comments').get();
    for (final d in comments.docs) {
      batch.delete(d.reference);
    }
    final likes = await postRef.collection('likes').get();
    for (final d in likes.docs) {
      batch.delete(d.reference);
    }
    batch.delete(postRef);
    await batch.commit();

    // Best-effort — a storage cleanup failure shouldn't block the post
    // itself from being gone. Mirrors the swallow-and-continue style in
    // [uploadPostImage]/[uploadPostVideo].
    for (final url in [...mediaUrls, if (thumbnailUrl != null) thumbnailUrl]) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (_) {}
    }

    await _db.collection('users').doc(_uid).update({
      'postCount': FieldValue.increment(-1),
    });
  }

  /// Updates an existing post's caption/location (M-7 post edit). Media is
  /// intentionally not editable here. Owner-only is enforced server-side by
  /// the existing posts rule (`isOwner(resource.data.authorId)`) — no rules
  /// change needed.
  Future<void> updatePost(String postId,
      {required String caption, String? location}) async {
    if (isMock) {
      final i = _feed.indexWhere((p) => p.id == postId);
      if (i != -1) {
        final p = _feed[i];
        _feed[i] = PostModel(
          id: p.id, authorId: p.authorId, authorName: p.authorName,
          authorPhotoUrl: p.authorPhotoUrl, mediaUrls: p.mediaUrls,
          mediaType: p.mediaType, thumbnailUrl: p.thumbnailUrl,
          aspectRatio: p.aspectRatio, durationMs: p.durationMs,
          caption: caption, location: location, likeCount: p.likeCount,
          commentCount: p.commentCount, isReported: p.isReported,
          reportCount: p.reportCount, groupId: p.groupId,
          createdAt: p.createdAt, editedAt: DateTime.now(),
        );
      }
      notifyListeners();
      return;
    }
    if (_uid == null) return;
    await _db.collection('posts').doc(postId).update({
      'caption': caption,
      'location': location,
      'editedAt': FieldValue.serverTimestamp(),
    });
    // No manual _feed splice: the live snapshot listener already delivers
    // the updated doc, mirroring likePost/unlikePost's real-mode convention
    // (see their comments a few methods up).
  }

  // ── Generic content reporting (groups, chats, users) ────────
  Future<void> reportContent({
    required String targetType,   // 'group' | 'chat' | 'user' | 'comment'
    required String targetId,
    String? reason,
  }) async {
    if (isMock) return;
    if (!_reportLimiter.tryConsume()) {
      throw Exception(reportRateLimitError);
    }
    await _db.collection('reports').add({
      'targetType': targetType,
      'targetId': targetId,
      'reporterId': _uid,
      'reason': reason ?? 'Inappropriate content',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Block a user (UGC compliance — Apple requires this) ────────
  Future<void> blockUser(String targetUid) async {
    if (isMock) return;
    if (_uid == null) return;
    await _db
        .collection('users')
        .doc(_uid)
        .collection('blocked')
        .doc(targetUid)
        .set({'blockedAt': Timestamp.now()});
    notifyListeners();
  }

  Future<void> unblockUser(String targetUid) async {
    if (isMock) return;
    if (_uid == null) return;
    await _db
        .collection('users')
        .doc(_uid)
        .collection('blocked')
        .doc(targetUid)
        .delete();
    notifyListeners();
  }

  /// The signed-in user's blocked list, newest-blocked first. `blocked` docs
  /// only store `{blockedAt}` (see [blockUser]), so this re-fetches the
  /// actual `users` docs on every change — mirrors [watchSavedPosts].
  Stream<List<UserModel>> watchBlockedUsers() {
    if (isMock) return Stream.value(const []);
    if (_uid == null) return Stream.value(const []);
    return _db.collection('users').doc(_uid).collection('blocked')
        .orderBy('blockedAt', descending: true)
        .snapshots()
        .asyncMap((snap) async {
      final ids = snap.docs.map((d) => d.id).toList();
      if (ids.isEmpty) return <UserModel>[];
      final users = <UserModel>[];
      // Firestore caps whereIn at 30 values per query.
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
        final usersSnap = await _db.collection('users')
            .where(FieldPath.documentId, whereIn: chunk).get();
        users.addAll(usersSnap.docs.map((d) => UserModel.fromFirestore(d)));
      }
      // whereIn doesn't preserve order — resort to match blockedAt order.
      users.sort((a, b) => ids.indexOf(a.uid).compareTo(ids.indexOf(b.uid)));
      return users;
    });
  }

  // Upload image bytes to Firebase Storage and return the public download URL.
  // Path: user_uploads/{uid}/posts/{timestamp}.jpg
  Future<String?> uploadPostImage(Uint8List bytes) async {
    if (isMock) return null;
    if (_uid == null) return null;
    try {
      // Resize down to a sensible max edge (1600px) before upload —
      // phone-camera JPEGs are 5–10 MB and we never display larger
      // than a feed card anyway.
      final compressed = await compressForUpload(bytes);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref('user_uploads/$_uid/posts/$ts.png');
      await ref.putData(compressed,
          SettableMetadata(contentType: 'image/png'));
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  // Upload a post video (+ optional poster) to Firebase Storage and return the
  // download URLs. Mirrors [uploadPostImage] (bytes in → putData → URL out) but
  // skips image compression (that codec is image-only) and tags the correct
  // video content-type. The composer reads bytes and generates the poster, so
  // this stays free of dart:io / plugin imports and is safe for the web build.
  // Path: user_uploads/{uid}/posts/{timestamp}.{mp4|mov} (+ _thumb.jpg)
  Future<Map<String, String>?> uploadPostVideo({
    required Uint8List videoBytes,
    required String ext, // 'mp4' | 'mov'
    Uint8List? thumbnailBytes,
  }) async {
    if (isMock) return null;
    if (_uid == null) return null;
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final contentType = ext == 'mov' ? 'video/quicktime' : 'video/mp4';
      final vref = FirebaseStorage.instance.ref('user_uploads/$_uid/posts/$ts.$ext');
      await vref.putData(videoBytes, SettableMetadata(contentType: contentType));
      final videoUrl = await vref.getDownloadURL();

      String? thumbnailUrl;
      if (thumbnailBytes != null) {
        final tref = FirebaseStorage.instance.ref('user_uploads/$_uid/posts/${ts}_thumb.jpg');
        await tref.putData(thumbnailBytes, SettableMetadata(contentType: 'image/jpeg'));
        thumbnailUrl = await tref.getDownloadURL();
      }
      return {'videoUrl': videoUrl, if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl};
    } catch (_) {
      return null;
    }
  }

  Future<void> createPost({
    required String caption,
    List<String> mediaUrls = const [],
    String mediaType = 'text',
    String? thumbnailUrl,
    double? aspectRatio,
    int? durationMs,
    String? location,
    String? groupId,
    String audience = 'Everyone',  // Everyone | Connections | Only me
  }) async {
    if (isMock) {
      final user = _storedAuth?.currentUser;
      final post = PostModel(
        id: 'post_new_${DateTime.now().millisecondsSinceEpoch}',
        authorId: user?.uid ?? 'user_001', authorName: user?.name ?? 'Alex Johnson',
        authorPhotoUrl: user?.photoUrl,
        caption: caption, mediaUrls: mediaUrls, mediaType: mediaType,
        thumbnailUrl: thumbnailUrl, aspectRatio: aspectRatio, durationMs: durationMs,
        location: location, likeCount: 0, commentCount: 0, createdAt: DateTime.now());
      _feed.insert(0, post);
      notifyListeners(); return;
    }
    if (_uid == null) return;
    final user = _auth.currentUser!;
    final ref = _db.collection('posts').doc();
    final post = PostModel(
      id: ref.id, authorId: _uid!, authorName: user.displayName ?? 'User',
      caption: caption, mediaUrls: mediaUrls, mediaType: mediaType,
      thumbnailUrl: thumbnailUrl, aspectRatio: aspectRatio, durationMs: durationMs,
      location: location, groupId: groupId, createdAt: DateTime.now(),
      audience: audience,
    );
    await ref.set(post.toFirestore());
    await _db.collection('users').doc(_uid).update({'postCount': FieldValue.increment(1)});
    notifyListeners();
  }

  @override
  void dispose() { _feedSub?.cancel(); super.dispose(); }
}

// ─── Real Chat Provider ──────────────────────────────────────
class ChatProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<ChatModel> _chats = [];
  StreamSubscription? _chatsSub;
  AuthProvider? _storedAuth;
  String? _chatsError;

  List<ChatModel> get chats => _chats;

  /// Total unread messages for the signed-in user across every conversation.
  /// Backs the top-bar chat badge; 0 when nothing is unread so the badge hides.
  int get totalUnread =>
      _chats.fold(0, (acc, c) => acc + (c.unreadCount[_uid] ?? 0));

  /// Non-null when the chat-list stream has reported a failure.
  /// Cleared on a successful snapshot or an explicit retry.
  String? get chatsError => _chatsError;

  String? get _uid => isMock ? (_storedAuth?.currentUser?.uid ?? 'user_001') : _auth.currentUser?.uid;

  ChatProvider({this.isMock = false}) {
    if (isMock) _chats = List.from(mockChats);
  }

  void updateAuth(AuthProvider auth) {
    _storedAuth = auth;
    if (isMock) return;
    _subscribeChats();
  }

  /// Re-subscribe to the chat-list stream. Exposed so the UI can wire it
  /// to an InlineErrorBanner Retry button.
  void retryChats() => _subscribeChats();

  void _subscribeChats() {
    _chatsSub?.cancel();
    if (_uid == null) return;
    _chatsError = null;
    _chatsSub = _db.collection('chats')
        .where('participants', arrayContains: _uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .listen((snap) {
      _chats = snap.docs.map((d) => ChatModel.fromFirestore(d)).toList();
      if (_chatsError != null) _chatsError = null;
      notifyListeners();
    }, onError: (Object err) {
      _chatsError = 'Could not load conversations.';
      notifyListeners();
    });
  }

  Stream<List<MessageModel>> watchMessages(String chatId) {
    if (isMock) return Stream.value(mockMessages[chatId] ?? []);
    return _db.collection('chats').doc(chatId).collection('messages')
        .orderBy('createdAt').snapshots()
        .map((s) => s.docs.map((d) => MessageModel.fromFirestore(d)).toList());
  }

  Future<void> sendMessage(String chatId, String text,
      {String? mediaUrl, String mediaType = 'text'}) async {
    if (isMock) {
      final user = _storedAuth?.currentUser;
      final msg = MessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}', chatId: chatId,
        senderId: user?.uid ?? 'user_001', senderName: user?.name ?? 'Alex Johnson',
        text: text, mediaType: mediaType, readBy: [user?.uid ?? 'user_001'],
        createdAt: DateTime.now());
      mockMessages[chatId] = [...(mockMessages[chatId] ?? []), msg];
      final i = _chats.indexWhere((c) => c.id == chatId);
      if (i != -1) {
        final c = _chats[i];
        _chats[i] = ChatModel(id: c.id, type: c.type, participants: c.participants,
          groupName: c.groupName, lastMessage: text, lastMessageAt: DateTime.now(),
          unreadCount: c.unreadCount, createdBy: c.createdBy, createdAt: c.createdAt);
      }
      notifyListeners(); return;
    }
    if (_uid == null) return;
    final user = _auth.currentUser!;
    final chatRef = _db.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final cachedChat = _chats.where((c) => c.id == chatId).firstOrNull;
    final participants = cachedChat?.participants ??
        List<String>.from((await chatRef.get()).data()?['participants'] ?? []);
    final batch = _db.batch();
    batch.set(msgRef, {
      'senderId': _uid, 'senderName': user.displayName ?? 'User',
      'senderPhotoUrl': user.photoURL, 'text': text,
      'mediaUrl': mediaUrl, 'mediaType': mediaType,
      'readBy': [_uid], 'createdAt': FieldValue.serverTimestamp(),
    });
    final chatUpdate = <String, dynamic>{
      // An image sent with no caption would otherwise leave the chat list's
      // "last message" preview blank (M-7 chat attachments).
      'lastMessage': text.isEmpty && mediaType == 'image' ? '📷 Photo' : text,
      'lastMessageSenderId': _uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
    for (final uid in participants) {
      if (uid != _uid) chatUpdate['unreadCount.$uid'] = FieldValue.increment(1);
    }
    batch.update(chatRef, chatUpdate);
    await batch.commit();
    notifyListeners();
  }

  /// Upload a chat image to Firebase Storage and return the public download
  /// URL. Mirrors PostProvider.uploadPostImage exactly (M-7 chat attachments).
  /// Path: user_uploads/{uid}/chat/{timestamp}.png
  Future<String?> uploadChatImage(Uint8List bytes) async {
    if (isMock) return null;
    if (_uid == null) return null;
    try {
      final compressed = await compressForUpload(bytes);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref('user_uploads/$_uid/chat/$ts.png');
      await ref.putData(compressed, SettableMetadata(contentType: 'image/png'));
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> markAsRead(String chatId) async {
    if (isMock) return;
    if (_uid == null) return;
    await _db.collection('chats').doc(chatId).update({'unreadCount.$_uid': 0});
  }

  /// Toggles whether the signed-in user has muted this conversation (M-7).
  /// Muted state is per-user (`mutedBy` array on the chat doc) so it doesn't
  /// affect other participants' notifications.
  Future<void> toggleMute(String chatId) async {
    if (isMock) return;
    if (_uid == null) return;
    final chat = _chats.where((c) => c.id == chatId).firstOrNull;
    final isMuted = chat?.mutedBy.contains(_uid) ?? false;
    await _db.collection('chats').doc(chatId).update({
      'mutedBy': isMuted ? FieldValue.arrayRemove([_uid]) : FieldValue.arrayUnion([_uid]),
    });
  }

  /// Appends the current user to `readBy` on every message they haven't
  /// seen yet, so the sender's bubble flips from a single check to a
  /// double check (read receipt).
  Future<void> markMessagesRead(String chatId) async {
    if (isMock) return;
    if (_uid == null) return;
    final unseen = await _db.collection('chats').doc(chatId).collection('messages')
        .where('senderId', isNotEqualTo: _uid).get();
    final batch = _db.batch();
    var hasWrites = false;
    for (final doc in unseen.docs) {
      final readBy = List<String>.from(doc.data()['readBy'] ?? []);
      if (!readBy.contains(_uid)) {
        batch.update(doc.reference, {'readBy': FieldValue.arrayUnion([_uid])});
        hasWrites = true;
      }
    }
    if (hasWrites) await batch.commit();
  }

  Future<String> getOrCreateDm(String otherUid) async {
    if (isMock) {
      final existing = _chats.where((c) => c.type == 'dm' && c.participants.contains(otherUid)).firstOrNull;
      if (existing != null) return existing.id;
      final newId = 'chat_new_$otherUid';
      final other = mockUsers.where((u) => u.uid == otherUid).firstOrNull;
      _chats.add(ChatModel(id: newId, type: 'dm', participants: [_uid!, otherUid],
        participantNames: ChatModel.namesMap(
          meUid: _uid!, meName: _storedAuth?.currentUser?.name,
          otherUid: otherUid, otherName: other?.name),
        lastMessage: null, lastMessageAt: null,
        unreadCount: {}, createdBy: _uid!, createdAt: DateTime.now()));
      notifyListeners();
      return newId;
    }
    if (_uid == null) return '';
    final snap = await _db.collection('chats')
        .where('type', isEqualTo: 'dm')
        .where('participants', arrayContains: _uid).get();
    for (final doc in snap.docs) {
      final chat = ChatModel.fromFirestore(doc);
      if (chat.participants.contains(otherUid)) return doc.id;
    }
    // Denormalise both display names onto the doc so the chat list can render
    // a DM title without an extra users/{uid} read per row. A failure here
    // must not block chat creation — displayNameFor falls back to 'User'.
    Map<String, String> names = const {};
    try {
      final docs = await Future.wait([
        _db.collection('users').doc(_uid).get(),
        _db.collection('users').doc(otherUid).get(),
      ]);
      names = ChatModel.namesMap(
        meUid: _uid!, meName: docs[0].data()?['name'] as String?,
        otherUid: otherUid, otherName: docs[1].data()?['name'] as String?,
      );
    } catch (_) {
      // Leave names empty; the tile degrades to 'User' rather than failing.
    }

    final ref = _db.collection('chats').doc();
    await ref.set({
      'type': 'dm', 'participants': [_uid, otherUid],
      'participantNames': names,
      'createdBy': _uid, 'unreadCount': {}, 'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setTyping(String chatId, bool isTyping) async {
    if (isMock) return;
    if (_uid == null) return;
    await _db.collection('chats').doc(chatId).collection('typing').doc(_uid)
        .set({'isTyping': isTyping, 'at': FieldValue.serverTimestamp()});
  }

  Stream<Map<String, bool>> watchTyping(String chatId) {
    if (isMock) return Stream.value({});
    return _db.collection('chats').doc(chatId).collection('typing').snapshots()
        .map((s) => Map.fromEntries(
            s.docs.map((d) => MapEntry(d.id, d.data()['isTyping'] as bool? ?? false))));
  }

  @override
  void dispose() { _chatsSub?.cancel(); super.dispose(); }
}

// ─── Real Event Provider ─────────────────────────────────────
class EventProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<EventModel> _events = [];
  final Set<String> _rsvpd = {};
  StreamSubscription? _eventsSub;
  AuthProvider? _storedAuth;
  String? _eventsError;

  List<EventModel> get events => _events;

  /// Events an ordinary user should see: only ones admin has approved. The
  /// admin "Pending" queue was previously cosmetic — nothing else filtered
  /// on isApproved, so every unreviewed event was already publicly visible.
  List<EventModel> get visibleEvents => _events.where((e) => e.isApproved).toList();

  /// An owning business's own events, regardless of approval state, so they
  /// can still see/manage their own pending event on their dashboard.
  List<EventModel> myEvents(String uid) => _events.where((e) => e.createdBy == uid).toList();

  /// Non-null when the events stream has reported a failure. Cleared on
  /// every successful snapshot or via [retryEvents].
  String? get eventsError => _eventsError;

  String? get _uid => isMock ? (_storedAuth?.currentUser?.uid ?? 'user_001') : _auth.currentUser?.uid;

  EventProvider({this.isMock = false}) {
    if (isMock) { _events = List.from(mockEvents); _rsvpd.add('evt_004'); }
  }

  void updateAuth(AuthProvider auth) {
    _storedAuth = auth;
    if (isMock) return;
    _subscribeEvents();
  }

  /// Re-subscribe to the events stream. Wired to InlineErrorBanner Retry.
  void retryEvents() {
    if (isMock) return;
    _subscribeEvents();
  }

  void _subscribeEvents() {
    _eventsSub?.cancel();
    _eventsError = null;
    _eventsSub = _db.collection('events').orderBy('date').snapshots().listen((snap) {
      _events = snap.docs.map((d) => EventModel.fromFirestore(d)).toList();
      if (_eventsError != null) _eventsError = null;
      notifyListeners();
    }, onError: (Object err) {
      _eventsError = 'Could not load events.';
      notifyListeners();
    });
  }

  Future<void> toggleRsvp(String eventId) async {
    if (isMock) {
      if (_rsvpd.contains(eventId)) { _rsvpd.remove(eventId); } else { _rsvpd.add(eventId); }
      notifyListeners(); return;
    }
    if (_uid == null) return;
    final rsvpRef = _db.collection('events').doc(eventId).collection('rsvps').doc(_uid);
    final doc = await rsvpRef.get();
    if (doc.exists) {
      await rsvpRef.delete();
      await _db.collection('events').doc(eventId).update({
        'rsvpList': FieldValue.arrayRemove([_uid]), 'rsvpCount': FieldValue.increment(-1),
      });
      _rsvpd.remove(eventId);
    } else {
      await rsvpRef.set({'rsvpAt': Timestamp.now()});
      await _db.collection('events').doc(eventId).update({
        'rsvpList': FieldValue.arrayUnion([_uid]), 'rsvpCount': FieldValue.increment(1),
      });
      _rsvpd.add(eventId);
    }
    notifyListeners();
  }

  Future<bool> hasRsvped(String eventId) async {
    if (isMock) return _rsvpd.contains(eventId);
    if (_uid == null) return false;
    if (_rsvpd.contains(eventId)) return true;
    final doc = await _db.collection('events').doc(eventId).collection('rsvps').doc(_uid).get();
    if (doc.exists) _rsvpd.add(eventId);
    return doc.exists;
  }

  bool isRsvpd(String eventId) => _rsvpd.contains(eventId);

  // Upload an event cover image to Firebase Storage and return the public
  // download URL. Mirrors [PostProvider.uploadPostImage].
  // Path: user_uploads/{uid}/events/{timestamp}.png
  Future<String?> uploadEventImage(Uint8List bytes) async {
    if (isMock) return null;
    if (_uid == null) return null;
    try {
      final compressed = await compressForUpload(bytes);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref('user_uploads/$_uid/events/$ts.png');
      await ref.putData(compressed, SettableMetadata(contentType: 'image/png'));
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> addEvent(EventModel event) async {
    if (isMock) { _events.insert(0, event); notifyListeners(); return; }
    await _db.collection('events').doc().set(event.toFirestore());
    notifyListeners();
  }

  Future<void> updateEvent(String eventId,
      {String? title, String? description, String? location, String? imageUrl}) async {
    if (isMock) { notifyListeners(); return; }
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (location != null) updates['location'] = location;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;
    if (updates.isEmpty) return;
    await _db.collection('events').doc(eventId).update(updates);
  }

  /// Removes an attendee entirely: deletes their rsvp subdoc and reverses
  /// their contribution to rsvpList/rsvpCount on the parent event.
  Future<void> removeAttendee(String eventId, String uid) async {
    if (isMock) { notifyListeners(); return; }
    await _db.collection('events').doc(eventId).collection('rsvps').doc(uid).delete();
    await _db.collection('events').doc(eventId).update({
      'rsvpList': FieldValue.arrayRemove([uid]),
      'rsvpCount': FieldValue.increment(-1),
    });
    _rsvpd.remove(eventId);
  }

  @override
  void dispose() { _eventsSub?.cancel(); super.dispose(); }
}

// ─── Real Group Provider ─────────────────────────────────────
class GroupProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<GroupModel> _groups = [];
  final Set<String> _joined = {};
  StreamSubscription? _groupsSub;

  List<GroupModel> get groups => _groups;
  List<GroupModel> get myGroups => _groups.where((g) => _joined.contains(g.id)).toList();
  String? get _uid => isMock ? null : _auth.currentUser?.uid;

  GroupProvider({this.isMock = false}) {
    if (isMock) { _groups = List.from(mockGroups); _joined.addAll({'grp_001', 'grp_002'}); }
  }

  void updateAuth(AuthProvider auth) {
    if (isMock) return;
    _groupsSub?.cancel();
    _groupsSub = _db.collection('groups')
        .orderBy('memberCount', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
      _groups = snap.docs.map((d) => GroupModel.fromFirestore(d)).toList();
      if (_uid != null) {
        _joined.clear();
        for (final g in _groups) { if (g.members.contains(_uid)) _joined.add(g.id); }
      }
      notifyListeners();
    });
  }

  Future<GroupModel?> getGroup(String groupId) async {
    if (isMock) return _groups.where((g) => g.id == groupId).firstOrNull;
    final doc = await _db.collection('groups').doc(groupId).get();
    if (!doc.exists) return null;
    return GroupModel.fromFirestore(doc);
  }

  Future<void> joinGroup(String groupId) async {
    if (isMock) { _joined.add(groupId); notifyListeners(); return; }
    if (_uid == null) return;
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([_uid]), 'memberCount': FieldValue.increment(1),
    });
    _joined.add(groupId);
    notifyListeners();
  }

  Future<void> leaveGroup(String groupId) async {
    if (isMock) { _joined.remove(groupId); notifyListeners(); return; }
    if (_uid == null) return;
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([_uid]), 'memberCount': FieldValue.increment(-1),
    });
    _joined.remove(groupId);
    notifyListeners();
  }

  bool isMember(String groupId) => _joined.contains(groupId);

  Future<void> createGroup(GroupModel group) async {
    if (isMock) { _groups.insert(0, group); _joined.add(group.id); notifyListeners(); return; }
    // Track the real Firestore-assigned doc id, not group.id (a disposable
    // client-side placeholder never persisted — see toFirestore()/fromFirestore()) —
    // otherwise _joined never matches the doc the snapshot listener loads back,
    // and the creator's own new group silently never shows up under "My Groups".
    final ref = _db.collection('groups').doc();
    await ref.set(group.toFirestore());
    _joined.add(ref.id);
    notifyListeners();
  }

  Future<void> deleteGroup(String groupId) async {
    if (isMock) { _groups.removeWhere((g) => g.id == groupId); notifyListeners(); return; }
    await _db.collection('groups').doc(groupId).delete();
  }

  /// Resolves member uids to profiles, capped to avoid unbounded reads on
  /// large groups (some groups here run 1000+ members). Chunked into
  /// Firestore's 30-id `whereIn` limit.
  static const int memberFetchCap = 60;

  Future<List<UserModel>> fetchMembers(List<String> memberUids) async {
    if (isMock) return const [];
    final capped = memberUids.take(memberFetchCap).toList();
    final results = <UserModel>[];
    for (var i = 0; i < capped.length; i += 30) {
      final chunk = capped.sublist(i, i + 30 > capped.length ? capped.length : i + 30);
      if (chunk.isEmpty) continue;
      final snap = await _db.collection('users')
          .where(FieldPath.documentId, whereIn: chunk).get();
      results.addAll(snap.docs.map((d) => UserModel.fromFirestore(d)));
    }
    return results;
  }

  Future<void> removeMember(String groupId, String uid) async {
    if (isMock) { notifyListeners(); return; }
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([uid]),
      'admins': FieldValue.arrayRemove([uid]),
      'memberCount': FieldValue.increment(-1),
    });
  }

  Future<void> makeAdmin(String groupId, String uid) async {
    if (isMock) { notifyListeners(); return; }
    await _db.collection('groups').doc(groupId).update({
      'admins': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> setChatEnabled(String groupId, bool enabled) async {
    if (isMock) { notifyListeners(); return; }
    await _db.collection('groups').doc(groupId).update({'chatEnabled': enabled});
  }

  /// Persists a broadcast as a durable, auditable record. Does not yet fan
  /// out as per-member push/notifications — see firestore.rules for the
  /// admin-gated write rule backing this subcollection.
  Future<void> sendBroadcast(String groupId, String text) async {
    if (isMock) return;
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('groups').doc(groupId).collection('broadcasts').add({
      'senderId': uid,
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() { _groupsSub?.cancel(); super.dispose(); }
}

// ─── Real Match Provider ─────────────────────────────────────
class MatchProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<UserModel> _candidates = [];
  final List<MatchModel> _matches = [];
  bool _loading = false;
  AuthProvider? _storedAuth;

  bool get loading => _loading;
  List<UserModel> get candidates => _candidates;
  List<MatchModel> get matches => _matches;
  String? get _uid => isMock ? (_storedAuth?.currentUser?.uid ?? 'user_001') : _auth.currentUser?.uid;

  MatchProvider({this.isMock = false}) {
    if (isMock) _candidates = List.from(mockUsers);
  }

  void updateAuth(AuthProvider auth) {
    _storedAuth = auth;
  }

  Future<void> loadCandidates() async {
    if (isMock) { _candidates = List.from(mockUsers); notifyListeners(); return; }
    if (_uid == null) return;
    _loading = true; notifyListeners();

    // Honor the filters set on the Match Preferences screen
    // (users/{uid}.matchPrefs). Age/distance are persisted there too but can't
    // be applied yet — UserModel carries no DOB or geo — so those stay a
    // follow-up once that data exists. We over-fetch (50) since filtering thins
    // the pool client-side.
    final meDoc = await _db.collection('users').doc(_uid).get();
    final me = meDoc.data() ?? const <String, dynamic>{};
    final prefs = (me['matchPrefs'] as Map<String, dynamic>?) ?? const {};
    final myAirline = me['airline'] as String?;
    final verifiedOnly = prefs['verifiedOnly'] == true;
    final sameAirline = prefs['sameAirline'] == true;
    final airlines = List<String>.from(prefs['airlines'] ?? const <String>[]);
    final positions = List<String>.from(prefs['positions'] ?? const <String>[]);

    final snap = await _db.collection('users').where('role', isEqualTo: 'user').limit(50).get();
    _candidates = snap.docs
        .map((d) => UserModel.fromFirestore(d))
        .where((u) => u.uid != _uid)
        .where((u) => !verifiedOnly || u.isVerified)
        .where((u) => !sameAirline || (myAirline != null && u.airline == myAirline))
        .where((u) => airlines.isEmpty || (u.airline != null && airlines.contains(u.airline)))
        .where((u) => positions.isEmpty || (u.position != null && positions.contains(u.position)))
        .toList();
    _loading = false; notifyListeners();
  }

  Future<void> likeUser(String targetUid, String matchType) async {
    _candidates.removeWhere((u) => u.uid == targetUid);
    if (isMock) {
      if (DateTime.now().millisecond % 2 == 0) {
        final matched = mockUsers.where((u) => u.uid == targetUid).firstOrNull;
        if (matched != null) {
          _matches.add(MatchModel(id: 'match_$targetUid', userA: _uid ?? 'user_001',
            userB: targetUid, status: 'matched', matchType: matchType,
            likedAt: DateTime.now(), matchedAt: DateTime.now()));
        }
      }
      notifyListeners(); return;
    }
    if (_uid == null) return;
    final existing = await _db.collection('matches')
        .where('userA', isEqualTo: targetUid).where('userB', isEqualTo: _uid)
        .where('status', isEqualTo: 'pending').get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({'status': 'matched', 'matchedAt': FieldValue.serverTimestamp()});
      _matches.add(MatchModel(id: existing.docs.first.id, userA: targetUid, userB: _uid!,
        status: 'matched', matchType: matchType, likedAt: DateTime.now(), matchedAt: DateTime.now()));
    } else {
      await _db.collection('matches').add({
        'userA': _uid, 'userB': targetUid, 'status': 'pending',
        'matchType': matchType, 'likedAt': FieldValue.serverTimestamp(),
      });
    }
    notifyListeners();
  }

  Future<void> passUser(String targetUid) async {
    _candidates.removeWhere((u) => u.uid == targetUid);
    if (isMock) { notifyListeners(); return; }
    if (_uid == null) return;
    await _db.collection('matches').add({
      'userA': _uid, 'userB': targetUid, 'status': 'passed',
      'matchType': 'none', 'likedAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }
}

/// Distinguishes "you're offline" from a real backend failure so
/// NotificationProvider doesn't show the same dead-end copy for both (M-8).
String describeNotificationsError(Object err) {
  if (err is FirebaseException && err.code == 'unavailable') {
    return 'You\'re offline. Check your connection and try again.';
  }
  return 'Something went wrong loading notifications. Please try again.';
}

// ─── Real Notification Provider ──────────────────────────────
class NotificationProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<NotificationModel> _notifications = [];
  StreamSubscription? _notifSub;
  AuthProvider? _storedAuth;
  String? _notificationsError;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Non-null when the notifications stream has reported a failure.
  String? get notificationsError => _notificationsError;

  NotificationProvider({this.isMock = false}) {
    if (isMock) _notifications = List.from(mockNotifications);
  }

  void updateAuth(AuthProvider auth) {
    if (isMock) return;
    _storedAuth = auth;
    _subscribeNotifications();
  }

  /// Re-subscribe to the notifications stream. Wired to InlineErrorBanner Retry.
  void retryNotifications() {
    if (isMock) return;
    _subscribeNotifications();
  }

  void _subscribeNotifications() {
    _notifSub?.cancel();
    final uid = _storedAuth?.currentUser?.uid;
    if (uid == null) return;
    _notificationsError = null;
    _notifSub = _db.collection('notifications')
        .where('userId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(50)
        .snapshots().listen((snap) {
      _notifications = snap.docs.map((d) => NotificationModel.fromFirestore(d)).toList();
      if (_notificationsError != null) _notificationsError = null;
      notifyListeners();
    }, onError: (Object err) {
      _notificationsError = describeNotificationsError(err);
      notifyListeners();
    });
  }

  Stream<List<NotificationModel>> watchNotifications() => Stream.value(_notifications);

  Future<void> markAsRead(String id) async {
    final i = _notifications.indexWhere((n) => n.id == id);
    if (i != -1) {
      final n = _notifications[i];
      _notifications[i] = NotificationModel(id: n.id, userId: n.userId,
        type: n.type, title: n.title, body: n.body,
        imageUrl: n.imageUrl, deepLink: n.deepLink, isRead: true, createdAt: n.createdAt);
      notifyListeners();
    }
    if (isMock) return;
    await _db.collection('notifications').doc(id).update({'isRead': true});
  }

  Future<void> markAllAsRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      _notifications[i] = NotificationModel(id: n.id, userId: n.userId,
        type: n.type, title: n.title, body: n.body,
        imageUrl: n.imageUrl, deepLink: n.deepLink, isRead: true, createdAt: n.createdAt);
    }
    notifyListeners();
    if (isMock) return;
    final uid = _notifications.isNotEmpty ? _notifications.first.userId : null;
    if (uid == null) return;
    final snap = await _db.collection('notifications')
        .where('userId', isEqualTo: uid).where('isRead', isEqualTo: false).get();
    final batch = _db.batch();
    for (final doc in snap.docs) { batch.update(doc.reference, {'isRead': true}); }
    await batch.commit();
  }

  Future<void> delete(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
    if (isMock) return;
    await _db.collection('notifications').doc(id).delete();
  }

  @override
  void dispose() { _notifSub?.cancel(); super.dispose(); }
}

// ─── Real Trip Provider ──────────────────────────────────────
class TripProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<TripModel> _trips = [];
  StreamSubscription? _tripsSub;

  List<TripModel> get trips => _trips;

  TripProvider({this.isMock = false}) {
    if (isMock) _trips = List.from(mockTrips);
  }

  void updateAuth(AuthProvider auth) {
    if (isMock) return;
    _tripsSub?.cancel();
    final uid = auth.currentUser?.uid;
    if (uid != null) {
      _tripsSub = _db.collection('trips')
          .where('userId', isEqualTo: uid).orderBy('startDate', descending: true)
          .snapshots().listen((snap) {
        _trips = snap.docs.map((d) => TripModel.fromFirestore(d)).toList();
        notifyListeners();
      });
    }
  }

  Future<void> addTrip(TripModel trip) async {
    if (isMock) { _trips.insert(0, trip); notifyListeners(); return; }
    await _db.collection('trips').doc(trip.id).set(trip.toFirestore());
    notifyListeners();
  }

  Future<void> deleteTrip(String tripId) async {
    _trips.removeWhere((t) => t.id == tripId);
    notifyListeners();
    if (isMock) return;
    await _db.collection('trips').doc(tripId).delete();
  }

  @override
  void dispose() { _tripsSub?.cancel(); super.dispose(); }
}

// ─── Real Promotion Provider ─────────────────────────────────
class PromotionProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<PromotionModel> _promotions = [];
  StreamSubscription? _promoSub;

  List<PromotionModel> get promotions => _promotions;
  List<PromotionModel> get activePromotions =>
      _promotions.where((p) => p.isActive && p.isApproved).toList();
  List<PromotionModel> get expiredPromotions => _promotions.where((p) => !p.isActive).toList();

  /// An owning business's own promotions, regardless of approval/active
  /// state — used by the business's own "Crew Deals" dashboard tab, which
  /// must not show other businesses' promotions.
  List<PromotionModel> myPromotions(String uid) =>
      _promotions.where((p) => p.businessId == uid).toList();

  PromotionProvider({this.isMock = false}) {
    if (isMock) _promotions = List.from(mockPromotions);
  }

  void updateAuth(AuthProvider auth) {
    if (isMock) return;
    _promoSub?.cancel();
    _promoSub = _db.collection('promotions').snapshots().listen((snap) {
      _promotions = snap.docs.map((d) => PromotionModel.fromFirestore(d)).toList();
      notifyListeners();
    });
  }

  Future<void> addPromotion(PromotionModel promo) async {
    if (isMock) { _promotions.insert(0, promo); notifyListeners(); return; }
    await _db.collection('promotions').doc().set(promo.toFirestore());
    notifyListeners();
  }

  @override
  void dispose() { _promoSub?.cancel(); super.dispose(); }
}

// ─── Real Search Provider ────────────────────────────────────
class SearchProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<UserModel> _userResults = [];
  List<EventModel> _eventResults = [];
  List<GroupModel> _groupResults = [];
  bool _loading = false;
  String _query = '';

  List<UserModel> get userResults => _userResults;
  List<EventModel> get eventResults => _eventResults;
  List<GroupModel> get groupResults => _groupResults;
  bool get loading => _loading;
  String get query => _query;

  SearchProvider({this.isMock = false});

  void updateAuth(AuthProvider auth) {}

  Future<void> search(String q) async {
    if (q.isEmpty) { clear(); return; }
    _query = q; _loading = true; notifyListeners();
    if (isMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      final lower = q.toLowerCase();
      _userResults = [...mockUsers, mockCurrentUser]
        .where((u) => u.name.toLowerCase().contains(lower) ||
          (u.airline?.toLowerCase().contains(lower) ?? false)).toList();
      _eventResults = mockEvents
        .where((e) => e.title.toLowerCase().contains(lower) ||
          e.location.toLowerCase().contains(lower)).toList();
      _groupResults = mockGroups
        .where((g) => g.name.toLowerCase().contains(lower) ||
          g.tags.any((t) => t.toLowerCase().contains(lower))).toList();
      _loading = false; notifyListeners(); return;
    }

    final userSnap = await _db.collection('users')
        .where('name', isGreaterThanOrEqualTo: q)
        .where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(10).get();
    _userResults = userSnap.docs.map((d) => UserModel.fromFirestore(d)).toList();

    final eventSnap = await _db.collection('events')
        .where('title', isGreaterThanOrEqualTo: q)
        .where('title', isLessThanOrEqualTo: '$q\uf8ff').limit(10).get();
    _eventResults = eventSnap.docs.map((d) => EventModel.fromFirestore(d)).toList();

    final groupSnap = await _db.collection('groups')
        .where('name', isGreaterThanOrEqualTo: q)
        .where('name', isLessThanOrEqualTo: '$q\uf8ff').limit(10).get();
    _groupResults = groupSnap.docs.map((d) => GroupModel.fromFirestore(d)).toList();

    _loading = false; notifyListeners();
  }

  void clear() {
    _query = ''; _userResults = []; _eventResults = []; _groupResults = [];
    notifyListeners();
  }
}

// ─── Real SafeCheck Provider ─────────────────────────────────
class SafeCheckProvider extends ChangeNotifier {
  final bool isMock;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<SafeCheckModel> _checkIns = [];
  SafeCheckModel? _myLatestCheckIn;
  bool _loading = false;
  StreamSubscription? _checkInSub;

  List<SafeCheckModel> get checkIns => _checkIns;
  SafeCheckModel? get myLatestCheckIn => _myLatestCheckIn;
  bool get loading => _loading;
  List<SafeCheckModel> get activeCheckIns => _checkIns.where((c) => c.isActive).toList();

  SafeCheckProvider({this.isMock = false}) {
    if (isMock) _checkIns = List.from(mockSafeChecks);
  }

  void updateAuth(AuthProvider auth) {
    if (isMock) return;
    _checkInSub?.cancel();
    _checkInSub = _db.collection('safeChecks')
        .orderBy('createdAt', descending: true).limit(100).snapshots().listen((snap) {
      _checkIns = snap.docs.map((d) => SafeCheckModel.fromFirestore(d)).toList();
      final uid = auth.currentUser?.uid;
      if (uid != null) {
        final my = _checkIns.where((c) => c.userId == uid && c.isActive).toList();
        _myLatestCheckIn = my.isNotEmpty ? my.first : null;
      }
      notifyListeners();
    });
  }

  List<SafeCheckModel> nearbyCheckIns(String city) =>
    activeCheckIns.where((c) => c.city.toLowerCase() == city.toLowerCase()).toList();

  SafeCheckModel? latestForUser(String userId) {
    final userCheckIns = activeCheckIns.where((c) => c.userId == userId).toList();
    if (userCheckIns.isEmpty) return null;
    userCheckIns.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return userCheckIns.first;
  }

  Future<void> checkIn({
    required String status, String? message, required String city,
    double? lat, double? lng, required String userId,
    required String userName, String? userPhotoUrl,
  }) async {
    _loading = true; notifyListeners();
    final now = DateTime.now();
    final checkIn = SafeCheckModel(
      id: 'sc_${now.millisecondsSinceEpoch}', userId: userId,
      userName: userName, userPhotoUrl: userPhotoUrl,
      status: status, message: message, city: city, lat: lat, lng: lng,
      createdAt: now, expiresAt: now.add(const Duration(hours: 24)));
    if (isMock) {
      _checkIns.removeWhere((c) => c.userId == userId && c.isActive);
      _checkIns.insert(0, checkIn);
      _myLatestCheckIn = checkIn;
      _loading = false; notifyListeners(); return;
    }
    await _db.collection('safeChecks').add(checkIn.toFirestore());
    _loading = false; notifyListeners();
  }

  void clearMyCheckIn(String userId) {
    if (isMock) {
      _checkIns.removeWhere((c) => c.userId == userId && c.isActive);
      _myLatestCheckIn = null;
      notifyListeners(); return;
    }
    final active = _checkIns.where((c) => c.userId == userId && c.isActive);
    for (final c in active) {
      _db.collection('safeChecks').doc(c.id).update({'expiresAt': DateTime.now()});
    }
    _myLatestCheckIn = null;
    notifyListeners();
  }

  @override
  void dispose() { _checkInSub?.cancel(); super.dispose(); }
}
