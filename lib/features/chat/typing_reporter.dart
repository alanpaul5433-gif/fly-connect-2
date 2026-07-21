/// Reports typing state to a backend, writing only on TRANSITIONS.
///
/// H25: the conversation screen called `setTyping(chatId, v.isNotEmpty)` on
/// every keystroke — one Firestore write per character — and never called
/// `setTyping(false)` on send or dispose, so the other party saw "typing…"
/// forever. This collapses a burst of keystrokes into a single `true` (it only
/// fires when crossing idle↔typing) and guarantees a `false` via [stop], which
/// the screen calls on send and in dispose.
class TypingReporter {
  /// Called with `true` when typing starts, `false` when it stops. In the app
  /// this is `chatProvider.setTyping(chatId, …)`.
  final void Function(bool isTyping) onChanged;

  bool _active = false;

  TypingReporter(this.onChanged);

  /// Feed the current field state on every change. Writes `true` only on the
  /// idle→typing edge and `false` only on the typing→idle edge.
  void onInput({required bool hasText}) {
    if (hasText && !_active) {
      _active = true;
      onChanged(true);
    } else if (!hasText && _active) {
      _active = false;
      onChanged(false);
    }
  }

  /// Force the typing state to stopped (on send, and in dispose). No-op if we
  /// never reported typing, so it can't emit a spurious `false`.
  void stop() {
    if (_active) {
      _active = false;
      onChanged(false);
    }
  }
}
