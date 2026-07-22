import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A user's presence, interpreted from the RTDB `/status/{uid}` record (H8).
class Presence {
  final bool online;
  final DateTime? lastSeen;
  const Presence({required this.online, this.lastSeen});

  /// No record at all — never connected, or the read failed. Never treated as
  /// online, so the UI shows nothing rather than a fabricated status.
  static const Presence unknown = Presence(online: false, lastSeen: null);
}

/// Parses an RTDB `/status/{uid}` value: `{state, lastChanged}`. Tolerant of
/// nulls and malformed data — presence is best-effort, never a crash.
Presence parsePresence(Object? raw) {
  if (raw is! Map) return Presence.unknown;
  final lc = raw['lastChanged'];
  return Presence(
    online: raw['state'] == 'online',
    lastSeen: lc is int ? DateTime.fromMillisecondsSinceEpoch(lc) : null,
  );
}

/// The status line for the chat header, or null when there's nothing honest to
/// show. Online → "Online"; recently offline → "last seen …"; no data → null.
String? presenceLabel(Presence p, DateTime now) {
  if (p.online) return 'Online';
  final seen = p.lastSeen;
  if (seen == null) return null;
  return 'last seen ${timeago.format(seen, clock: now)}';
}

/// The presence writes [PresenceController] drives. An interface so the
/// controller's lifecycle logic can be tested without a live RTDB (which has no
/// fake). [PresenceService] is the real implementation.
abstract class PresenceSink {
  Future<void> setOnline(String uid);
  Future<void> setOffline(String uid);
  Stream<bool> connected();
}

/// Reads and writes presence to Realtime Database using the canonical Firebase
/// pattern: an `onDisconnect` handler flips the record to offline server-side
/// when the socket drops, so a force-quit or lost connection is reflected
/// without any client cooperation. `lastSeen` (login-time only) can't do this.
class PresenceService implements PresenceSink {
  PresenceService({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;
  final FirebaseDatabase _db;

  DatabaseReference _statusRef(String uid) => _db.ref('status/$uid');

  Map<String, Object> _payload(String state) =>
      {'state': state, 'lastChanged': ServerValue.timestamp};

  /// Marks [uid] online and arms the server-side onDisconnect → offline. Must
  /// be re-armed on every reconnect, so callers drive this from the
  /// `.info/connected` stream (see [PresenceController]).
  @override
  Future<void> setOnline(String uid) async {
    final ref = _statusRef(uid);
    await ref.onDisconnect().set(_payload('offline'));
    await ref.set(_payload('online'));
  }

  /// Marks [uid] offline immediately (clean sign-out / background).
  @override
  Future<void> setOffline(String uid) => _statusRef(uid).set(_payload('offline'));

  /// Whether the RTDB socket is currently connected.
  @override
  Stream<bool> connected() =>
      _db.ref('.info/connected').onValue.map((e) => e.snapshot.value == true);

  /// Live presence for [uid].
  Stream<Presence> watch(String uid) =>
      _statusRef(uid).onValue.map((e) => parsePresence(e.snapshot.value));
}

/// Drives [PresenceService] from auth + app lifecycle: online while the signed-
/// in app is foregrounded (re-arming onDisconnect on every reconnect), offline
/// on background and sign-out. Start it once for the signed-in user.
class PresenceController with WidgetsBindingObserver {
  PresenceController(this._service);
  final PresenceSink _service;
  String? _uid;
  StreamSubscription<bool>? _connSub;

  void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
    // Re-arm onDisconnect + mark online each time the socket (re)connects.
    _connSub = _service.connected().listen((isConnected) {
      if (isConnected && _uid != null) _service.setOnline(_uid!);
    });
  }

  void stop() {
    final uid = _uid;
    _connSub?.cancel();
    _connSub = null;
    if (uid != null) {
      _service.setOffline(uid);
      WidgetsBinding.instance.removeObserver(this);
    }
    _uid = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _uid;
    if (uid == null) return;
    if (state == AppLifecycleState.resumed) {
      _service.setOnline(uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _service.setOffline(uid);
    }
  }
}
