import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_routes.dart';
import '../utils/app_router.dart';

/// Handles FCM lifecycle:
/// - Requests notification permission (iOS + Android 13+)
/// - Stores the device FCM token on the user doc
/// - Refreshes the token on rotation
/// - Listens for foreground messages
/// - **Routes the user to the right screen when a notification is tapped**
///   (handles foreground tap, background-resume tap, and cold-start tap).
///
/// Call [NotificationService.init] from main.dart after Firebase.initializeApp.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<User?>? _authSub;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Web uses a different FCM pipeline (service worker + VAPID key).
    // Mobile-first for now; web push can be wired later with a VAPID key
    // passed to getToken(vapidKey: ...).
    if (kIsWeb) return;

    final messaging = FirebaseMessaging.instance;

    // Ask permission (shows the iOS system dialog; on Android 13+ triggers
    // the POST_NOTIFICATIONS runtime prompt if declared in the manifest).
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // User said no — skip token registration until they re-enable.
      return;
    }

    // Persist token whenever auth state changes (catches logout/login) and on rotation.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final token = await _resolveFcmToken(messaging);
        if (token != null) await _saveToken(user.uid, token);
      } catch (e) {
        // Never let a token hiccup escape into the zone (Crashlytics/debugger).
        // onTokenRefresh persists the token once FCM actually has it.
        debugPrint('[FCM] token fetch deferred: $e');
      }
    });

    _tokenSub = messaging.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await _saveToken(uid, token);
    });

    // Foreground messages — deliver to the in-app notification center.
    // Background/terminated messages go through the native handler registered
    // in AndroidManifest (flyconnect_default channel).
    _fgSub = FirebaseMessaging.onMessage.listen((msg) {
      // No-op here — UI subscribes via NotificationProvider stream.
      // Log in debug to confirm delivery during QA.
      debugPrint('[FCM foreground] ${msg.notification?.title} '
          'data=${msg.data}');
    });

    // App was in background, user tapped a notification → resume.
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // App was terminated, user tapped a notification → cold start.
    // getInitialMessage returns the message that opened the app, or null.
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      // Defer until after the router is mounted on the first frame.
      // ignore: discarded_futures
      Future<void>.delayed(const Duration(milliseconds: 300))
          .then((_) => _handleTap(initial));
    }
  }

  /// Fetches the FCM token, ensuring the APNS token exists first on Apple
  /// platforms.
  ///
  /// iOS/macOS deliver the APNS token asynchronously a beat *after* the
  /// permission grant, and [FirebaseMessaging.getToken] throws
  /// `apns-token-not-set` if called before then. We poll [getAPNSToken]
  /// briefly; if it never arrives we return null instead of throwing, and
  /// [FirebaseMessaging.onTokenRefresh] persists the token once it lands.
  Future<String?> _resolveFcmToken(FirebaseMessaging messaging) async {
    final isApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (isApple) {
      var apns = await messaging.getAPNSToken();
      for (var attempt = 0; apns == null && attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        apns = await messaging.getAPNSToken();
      }
      if (apns == null) return null; // not ready — let onTokenRefresh retry
    }
    return messaging.getToken();
  }

  /// Resolves the FCM data payload into an in-app deep link and navigates.
  ///
  /// Expected payload contract (set by the server / Cloud Function that
  /// sends the push):
  ///   type=message      data.chatId       → /conversation/{chatId}
  ///   type=match                            → /match
  ///   type=post_like    data.postId       → /posts/{postId}
  ///   type=post_comment data.postId       → /posts/{postId}
  ///   type=event        data.eventId      → /events/{eventId}
  ///   type=group        data.groupId      → /groups/{groupId}
  ///   type=follow       data.userId       → /users/{userId}
  ///   type=safe_check                       → /nearby
  ///   (anything else)                       → /notifications
  ///
  /// We never throw from here — a malformed payload should still leave the
  /// user inside the app, just on the notifications screen, never crashed.
  void _handleTap(RemoteMessage msg) {
    try {
      final route = resolveRouteFromPayload(msg.data);
      debugPrint('[FCM tap] data=${msg.data} → $route');
      appRouter.go(route);
    } catch (e, st) {
      debugPrint('[FCM tap] failed to route: $e\n$st');
      // Last-resort fallback so the tap is never a black hole.
      try {
        appRouter.go(AppRoutes.notifications);
      } catch (_) {}
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      // fcmToken is PII-adjacent (a push token identifying this device) and
      // lives in the owner-only private/data subdoc, not the widely-readable
      // main user doc — see H-2 in docs/QA_AUDIT_REPORT.md.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('data')
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      // Doc may not exist yet (first sign-up); the auth listener will retry
      // the next time it fires. Log so a *persistent* failure (which means no
      // push delivery) is visible rather than silent.
      debugPrint('[FCM] token save deferred (will retry on next auth event): $e');
    }
  }

  Future<void> dispose() async {
    await _fgSub?.cancel();
    await _openedSub?.cancel();
    await _tokenSub?.cancel();
    await _authSub?.cancel();
    _initialized = false;
  }
}

/// Pure mapping from an FCM `data` payload to an in-app deep-link route.
///
/// Extracted as a top-level function so it can be unit-tested without
/// pulling in Firebase or the GoRouter binding.
String resolveRouteFromPayload(Map<String, dynamic> data) {
  final type = (data['type'] as String?)?.trim().toLowerCase() ?? '';

  String? str(String key) {
    final v = data[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  switch (type) {
    case 'message':
    case 'chat':
      final chatId = str('chatId');
      if (chatId != null) return '${AppRoutes.conversation}/$chatId';
      return AppRoutes.chat;

    case 'match':
    case 'new_match':
      return AppRoutes.match;

    case 'post_like':
    case 'post_comment':
    case 'post':
      final postId = str('postId');
      if (postId != null) return '${AppRoutes.postDetails}/$postId';
      return AppRoutes.home;

    case 'event':
    case 'event_invite':
    case 'event_reminder':
      final eventId = str('eventId');
      if (eventId != null) return '${AppRoutes.eventDetails}/$eventId';
      return AppRoutes.events;

    case 'group':
    case 'group_invite':
      final groupId = str('groupId');
      if (groupId != null) return '${AppRoutes.groupDetails}/$groupId';
      return AppRoutes.groupsList;

    case 'promotion':
    case 'new_promotion':
      final promotionId = str('promotionId');
      if (promotionId != null) return '/promotions/$promotionId';
      return AppRoutes.offers;

    case 'follow':
    case 'follow_request':
      final userId = str('userId');
      if (userId != null) return '${AppRoutes.userProfile}/$userId';
      return AppRoutes.notifications;

    case 'safe_check':
    case 'safecheck':
      return AppRoutes.nearby;

    default:
      return AppRoutes.notifications;
  }
}
