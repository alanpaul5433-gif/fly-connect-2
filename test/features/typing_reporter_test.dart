import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/chat/typing_reporter.dart';

/// Coverage for H25 — the typing indicator.
///
/// `onChanged: (v) => setTyping(chatId, v.isNotEmpty)` fired one Firestore
/// write per keystroke, and setTyping(false) was never called on send or
/// dispose — so the other party saw "typing…" forever. TypingReporter writes
/// only on TRANSITIONS (idle→typing, typing→idle), collapsing a burst of
/// keystrokes into a single `true` and guaranteeing a `false` on stop.
void main() {
  late List<bool> writes;
  late TypingReporter reporter;

  setUp(() {
    writes = [];
    reporter = TypingReporter(writes.add);
  });

  test('a burst of keystrokes writes true exactly once, not per character', () {
    for (final _ in 'hello'.split('')) {
      reporter.onInput(hasText: true);
    }
    expect(writes, [true]);
  });

  test('clearing the field after typing writes false once', () {
    reporter.onInput(hasText: true);
    reporter.onInput(hasText: false);
    expect(writes, [true, false]);
  });

  test('stop() after typing writes false (used on send and dispose)', () {
    reporter.onInput(hasText: true);
    reporter.stop();
    expect(writes, [true, false]);
  });

  test('stop() when not typing writes nothing', () {
    reporter.stop();
    expect(writes, isEmpty);
  });

  test('never writes false twice in a row', () {
    reporter.onInput(hasText: true);
    reporter.stop();
    reporter.stop();
    reporter.onInput(hasText: false);
    expect(writes, [true, false]);
  });

  test('resumes with a fresh true after a stop', () {
    reporter.onInput(hasText: true);
    reporter.stop();
    reporter.onInput(hasText: true);
    expect(writes, [true, false, true]);
  });

  test('input on an empty field before typing writes nothing', () {
    // A focus event / backspace on an already-empty field.
    reporter.onInput(hasText: false);
    expect(writes, isEmpty);
  });
}
