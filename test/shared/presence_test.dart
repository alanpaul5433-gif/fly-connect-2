import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/services/presence.dart';

/// Records the online/offline calls and lets the test drive connectivity.
class _FakeSink implements PresenceSink {
  final calls = <String>[];
  final _conn = StreamController<bool>.broadcast();
  @override Future<void> setOnline(String uid) async => calls.add('online:$uid');
  @override Future<void> setOffline(String uid) async => calls.add('offline:$uid');
  @override Stream<bool> connected() => _conn.stream;
  void emitConnected(bool v) => _conn.add(v);
}

/// Coverage for H8 (real version) — interpreting the RTDB presence record.
///
/// RTDB stores `/status/{uid} = {state: 'online'|'offline', lastChanged: <ms>}`,
/// with an onDisconnect handler flipping it to offline server-side. These pure
/// functions parse that record and turn it into the label the chat UI shows,
/// so the RTDB plumbing (untestable without a live database) is the only
/// unproven part.
void main() {
  // PresenceController registers a WidgetsBindingObserver, which needs a
  // binding even for plain test() cases.
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 7, 22, 12, 0, 0);

  group('parsePresence', () {
    test('online when state is online', () {
      final p = parsePresence({'state': 'online', 'lastChanged': 1000});
      expect(p.online, isTrue);
    });

    test('offline with a lastSeen when state is offline', () {
      final ms = now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      final p = parsePresence({'state': 'offline', 'lastChanged': ms});
      expect(p.online, isFalse);
      expect(p.lastSeen, DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('a null record (never connected) is unknown, not online', () {
      expect(parsePresence(null).online, isFalse);
      expect(parsePresence(null).lastSeen, isNull);
    });

    test('a malformed record does not throw and is not online', () {
      expect(parsePresence('garbage').online, isFalse);
      expect(parsePresence({'state': 'online'}).lastSeen, isNull);
    });
  });

  group('presenceLabel', () {
    test('shows "Online" when online', () {
      expect(presenceLabel(const Presence(online: true), now), 'Online');
    });

    test('shows a "last seen" line when offline with a timestamp', () {
      final p = Presence(online: false, lastSeen: now.subtract(const Duration(minutes: 5)));
      final label = presenceLabel(p, now);
      expect(label, isNotNull);
      expect(label, startsWith('last seen'));
    });

    test('shows nothing when we have no presence at all', () {
      // Never a fabricated status — the H8 whole point.
      expect(presenceLabel(const Presence(online: false), now), isNull);
      expect(presenceLabel(Presence.unknown, now), isNull);
    });
  });

  group('PresenceController', () {
    late _FakeSink sink;
    late PresenceController controller;

    setUp(() {
      sink = _FakeSink();
      controller = PresenceController(sink);
    });
    tearDown(() => controller.stop());

    test('marks online only once the socket reports connected', () async {
      controller.start('me');
      expect(sink.calls, isEmpty); // not online until connected
      sink.emitConnected(true);
      await pumpEventQueue();
      expect(sink.calls, contains('online:me'));
    });

    test('re-arms online on every reconnect (onDisconnect needs re-setting)', () async {
      controller.start('me');
      sink.emitConnected(true);
      await pumpEventQueue();
      sink.emitConnected(false);
      await pumpEventQueue();
      sink.emitConnected(true);
      await pumpEventQueue();
      expect(sink.calls.where((c) => c == 'online:me').length, 2);
    });

    test('app pause marks offline, resume marks online', () async {
      controller.start('me');
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(sink.calls, contains('offline:me'));
      sink.calls.clear();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(sink.calls, contains('online:me'));
    });

    test('stop marks offline', () {
      controller.start('me');
      sink.calls.clear();
      controller.stop();
      expect(sink.calls, contains('offline:me'));
    });

    test('lifecycle events after stop do nothing', () {
      controller.start('me');
      controller.stop();
      sink.calls.clear();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(sink.calls, isEmpty);
    });
  });
}
