import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Email sign up ─────────────────────────────────────────
  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? airline,
    String? airport,
    String? position,
    String? city,
    String? state,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email, password: password,
    );
    await credential.user!.updateDisplayName(name);

    final user = UserModel(
      uid: credential.user!.uid,
      name: name,
      email: email,
      phone: phone,
      airline: airline,
      airport: airport,
      position: position,
      city: city,
      state: state,
      createdAt: DateTime.now(),
    );

    await _db.collection('users').doc(user.uid).set(user.toFirestore());
    return user;
  }

  // ── Email sign in ─────────────────────────────────────────
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // ── Phone auth ────────────────────────────────────────────
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) onVerificationCompleted,
    required Function(FirebaseAuthException) onVerificationFailed,
    required Function(String, int?) onCodeSent,
    required Function(String) onCodeAutoRetrievalTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onVerificationFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout,
    );
  }

  Future<UserCredential> signInWithPhoneCredential(PhoneAuthCredential credential) {
    return _auth.signInWithCredential(credential);
  }

  // ── Sign out ──────────────────────────────────────────────
  Future<void> signOut() => _auth.signOut();

  // ── Password reset ────────────────────────────────────────
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  // ── Update password ───────────────────────────────────────
  Future<void> updatePassword(String newPassword) =>
      _auth.currentUser!.updatePassword(newPassword);

  // ── Fetch user from Firestore ─────────────────────────────
  Future<UserModel?> fetchCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  // ── Update FCM token ──────────────────────────────────────
  // fcmToken lives in the owner-only private/data subdoc, not the widely
  // readable main user doc — see H-2 in docs/QA_AUDIT_REPORT.md.
  Future<void> updateFcmToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).collection('private').doc('data')
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  // ── Update last seen ──────────────────────────────────────
  Future<void> updateLastSeen() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'lastSeen': Timestamp.fromDate(DateTime.now()),
    });
  }
}
