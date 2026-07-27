/// Email-domain normalisation and matching for the signup allowlist.
///
/// Pure Dart on purpose — no Firebase, no BuildContext — so every nasty input
/// below is testable without an emulator. Same pattern as `block_list.dart`
/// and `match_logic.dart`.
///
/// Two rules govern everything in this file:
///
///   1. **Exact set membership, never suffix matching.** `endsWith('delta.com')`
///      matches `x@notdelta.com`, and `contains('@delta.com')` matches
///      `x@delta.com.evil.com` — and registering `delta.com.evil.com` costs an
///      attacker nothing. Subdomains are separate entries, added deliberately.
///
///   2. **The client and firestore.rules must agree.** Rules compute the domain
///      as `request.auth.token.email.lower().split('@')[1]` and have no way to
///      strip invisible characters. So the client must not silently "fix" an
///      address here and then hand the unfixed one to Firebase Auth — that
///      disagreement is exactly how you get an account whose profile write is
///      then denied. [sanitizeEmail] is the single boundary: sanitise once,
///      then use that value for BOTH the check and `createUserWithEmailAndPassword`.
library;

/// Characters that are invisible, survive `String.trim()`, and arrive via
/// copy-paste from email signatures and web pages.
///
/// Dart's `trim()` strips Unicode White_Space. U+200B and friends are *not*
/// White_Space, so `'a@delta.com​'.trim()` keeps the zero-width space and
/// the address silently fails to match a domain that looks correct on screen.
const _invisible = <int>{
  0x200B, // zero-width space
  0x200C, // zero-width non-joiner
  0x200D, // zero-width joiner
  0x2060, // word joiner
  0xFEFF, // zero-width no-break space / BOM
};

/// Strips invisible characters and surrounding whitespace from a typed email.
///
/// Call this once at the input boundary and use the result everywhere — the
/// allowlist check *and* the actual Firebase Auth call. See the library note:
/// sanitising only for the check is worse than not sanitising at all, because
/// the client would approve an address the server then rejects.
///
/// Deliberately does NOT lowercase: the local part of an address is
/// case-sensitive per RFC 5321, and mangling it is not this function's job.
/// [domainOf] lowercases the domain, which is the only part we compare.
String _stripInvisible(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    if (!_invisible.contains(rune)) buf.writeCharCode(rune);
  }
  return buf.toString().trim();
}

String sanitizeEmail(String raw) {
  final cleaned = _stripInvisible(raw);
  final at = cleaned.lastIndexOf('@');
  if (at < 1 || at == cleaned.length - 1) return cleaned;
  // More than one '@' is not an address; leave it alone so domainOf rejects it
  // rather than silently reshaping something malformed into something valid.
  if (cleaned.indexOf('@') != at) return cleaned;

  var domain = cleaned.substring(at + 1).toLowerCase();
  // Exactly one trailing dot — `delta.com.` is a legitimate root-anchored
  // FQDN and Firebase Auth will not strip it, but firestore.rules computes
  // the domain as `token.email.lower().split('@')[1]` and has no way to strip
  // it either. Left in place, the client would approve `delta.com` while the
  // rules looked up `delta.com.`, found nothing, and denied the profile
  // write — after the Auth account already existed. Stripping a SECOND dot
  // would be wrong: `delta.com..` is malformed, not root-anchored, and must
  // stay rejected rather than be cleaned up into a match.
  if (domain.endsWith('.')) domain = domain.substring(0, domain.length - 1);

  return '${cleaned.substring(0, at)}@$domain';
}

/// A syntactically valid, ASCII-only domain of at least two labels.
///
/// ASCII-only is a security requirement, not a simplification. `dеlta.com` with
/// a Cyrillic 'е' (U+0435) renders identically to `delta.com` in most fonts.
/// An attacker gains nothing from it — a homoglyph domain simply won't match —
/// but an *admin* who pastes one adds an entry that looks perfect and blocks
/// the entire real airline, and the discrepancy is invisible on screen.
/// Punycode A-labels (`xn--…`) are ASCII and therefore still accepted.
final _validDomain = RegExp(
  r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$',
);

/// Canonical form of a bare domain, or `null` if it isn't one.
///
/// Lowercases, strips exactly one trailing root dot (`delta.com.` is a valid
/// FQDN), then validates. Stripping only one dot matters: `delta.com..` must
/// stay rejected rather than being cleaned up into a match.
String? canonicalizeDomain(String raw) {
  var d = _stripInvisible(raw).toLowerCase();
  if (d.endsWith('.')) d = d.substring(0, d.length - 1);
  if (d.isEmpty || d.length > 253) return null;
  return _validDomain.hasMatch(d) ? d : null;
}

/// The canonical domain of [email], or `null` if the address is unusable.
///
/// Uses `lastIndexOf('@')` rather than `split('@')`. `'alex'.split('@').last`
/// returns `'alex'` — so a sloppy implementation ends up comparing the whole
/// string against the domain list and a no-`@` input reads as a domain rather
/// than as an error. A `null` return always means deny.
String? domainOf(String email) {
  final cleaned = sanitizeEmail(email);
  final at = cleaned.lastIndexOf('@');
  // at < 1 covers both "no @" (-1) and an empty local part (0).
  if (at < 1 || at == cleaned.length - 1) return null;
  // More than one '@' is not a valid address; rules' split('@')[1] would also
  // disagree with us here, so reject rather than guess.
  if (cleaned.indexOf('@') != at) return null;
  // Validate only — sanitizeEmail has already lowercased the domain and
  // stripped the single legal trailing dot. Canonicalising a second time here
  // would strip a second dot and turn the malformed `delta.com..` into a match.
  final domain = cleaned.substring(at + 1);
  if (domain.length > 253) return null;
  return _validDomain.hasMatch(domain) ? domain : null;
}

/// Apple's "Hide My Email" relay domain.
///
/// This can never match a company domain, so a relay signup is always refused —
/// but it must be refused with its own message, not a generic "your airline
/// isn't on the list". The user chose a privacy option; they did not mistype
/// their employer. Allowlisting this domain is not an option: it would admit
/// anyone holding an Apple ID.
const kAppleRelayDomain = 'privaterelay.appleid.com';

/// Whether [email] is a Apple private-relay address.
bool isAppleRelay(String email) => domainOf(email) == kAppleRelayDomain;

/// Exact membership test against the enabled allowlist.
///
/// [enabledDomains] must already be canonical (lowercase, validated) — the
/// admin write path guarantees that, so this stays a plain set lookup with no
/// per-call normalisation of the allowlist itself.
///
/// Note what this deliberately does NOT do: no subdomain expansion, no
/// wildcards. `crew@mail.delta.com` is denied unless `mail.delta.com` was added
/// as its own entry. Every "convenient" relaxation of this is a bypass — see
/// the library note.
bool isEmailDomainAllowed(String email, Set<String> enabledDomains) {
  final domain = domainOf(email);
  return domain != null && enabledDomains.contains(domain);
}

/// Public and disposable mail providers.
///
/// Adding one of these to the allowlist silently converts "airline employees
/// only" into "anyone on earth", with no error and nothing in any log that
/// reads as a problem. The admin UI must require a typed confirmation for these
/// rather than accepting the entry quietly. Not exhaustive and cannot be —
/// disposable domains rotate constantly. It catches the realistic slip
/// (an admin adding `gmail.com` because a partner asked), not a determined one.
const kPublicEmailProviders = <String>{
  'gmail.com', 'googlemail.com', 'outlook.com', 'hotmail.com', 'live.com',
  'yahoo.com', 'ymail.com', 'aol.com', 'icloud.com', 'me.com', 'mac.com',
  'proton.me', 'protonmail.com', 'gmx.com', 'mail.com', 'zoho.com',
  'yandex.com', 'mail.ru', 'qq.com', '163.com',
  // Disposable
  'mailinator.com', '10minutemail.com', 'guerrillamail.com', 'tempmail.com',
  'throwawaymail.com', 'yopmail.com', 'trashmail.com', 'sharklasers.com',
};

/// Outcome of validating what an admin typed into the "add domain" field.
class AdminDomainInput {
  /// Canonical domain to store, or `null` when [error] is set.
  final String? domain;

  /// User-facing reason the input was refused, or `null` on success.
  final String? error;

  /// True when [domain] is a public/disposable provider. Not an error — the
  /// admin may genuinely mean it — but the UI must require typed confirmation
  /// and the audit entry should be flagged.
  final bool needsPublicProviderConfirmation;

  const AdminDomainInput._(
      this.domain, this.error, this.needsPublicProviderConfirmation);

  const AdminDomainInput.accepted(String domain, {bool isPublicProvider = false})
      : this._(domain, null, isPublicProvider);

  const AdminDomainInput.rejected(String error) : this._(null, error, false);

  bool get isAccepted => domain != null;
}

/// Validates and canonicalises what an admin typed into the "add domain" field.
///
/// This is the *write* side of the allowlist, and it is where a typo becomes an
/// outage: an entry that is stored but can never match silently blocks an
/// entire airline, and diagnosing it means eyeballing two visually identical
/// strings. So the one thing this function must never do is accept an input
/// and store it unchanged when it will not match.
///
/// Inputs seen in practice, and what has to happen to each:
///
///   `delta.com`          → accept
///   `DELTA.COM`          → accept as `delta.com` (canonicalizeDomain does this)
///   `@delta.com`         → the most common typo; leading '@' is not part of a domain
///   `https://delta.com`  → pasted from the browser bar. Also contains '/', which
///                          is illegal in a Firestore document id — this one throws
///                          on write rather than merely failing to match.
///   `www.delta.com`      → the nastiest: plausible, and never appears in an email
///   `delta.com/`         → trailing slash from a copied URL
///   `*.delta.com`        → wildcards are not supported by [isEmailDomainAllowed]
///   `*`, `.com`, `com`   → would make the gate a no-op if they ever matched
///   `gmail.com`          → valid, but set [needsPublicProviderConfirmation]
///   multi-line paste     → admins will paste 40 domains at once on day one
///
/// Policy: auto-fix the unambiguous, reject the ambiguous.
///
/// A leading `@`, a URL scheme, a trailing slash and casing all have exactly
/// one sensible reading, so they are corrected silently and the caller shows
/// the normalised result before saving. `www.`, wildcards and multi-line
/// pastes have more than one reading, so they are refused with a message that
/// says what to type instead — guessing there would store something the admin
/// did not intend and cannot see is wrong.
AdminDomainInput normalizeAdminDomainInput(String raw) {
  var s = _stripInvisible(raw).toLowerCase();
  if (s.isEmpty) return const AdminDomainInput.rejected('Enter a domain.');

  // Multi-line or space-separated paste. Refusing beats silently keeping the
  // first entry and dropping the other 39.
  if (RegExp(r'[\s,;]').hasMatch(s)) {
    return const AdminDomainInput.rejected(
        'Add one domain at a time, without spaces or commas.');
  }

  // Unambiguous fixes.
  s = s.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), ''); // scheme
  s = s.split('/').first; // path or trailing slash
  if (s.startsWith('@')) s = s.substring(1); // the most common typo
  if (s.contains('@')) s = s.substring(s.indexOf('@') + 1); // a full address

  // Ambiguous — say what to type instead.
  if (s.startsWith('*')) {
    final suggestion = s.replaceFirst(RegExp(r'^\*\.?'), '');
    return AdminDomainInput.rejected(
        'Wildcards aren\'t supported. Add "$suggestion" on its own, and add '
        'any subdomains as separate entries.');
  }
  if (s.startsWith('www.')) {
    // Never part of an email address, but "strip it" is a guess about intent.
    return AdminDomainInput.rejected(
        'Email domains don\'t include "www." — did you mean '
        '"${s.substring(4)}"?');
  }

  final domain = canonicalizeDomain(s);
  if (domain == null) {
    if (!s.contains('.')) {
      return AdminDomainInput.rejected(
          '"$s" isn\'t a full domain. Use something like "delta.com".');
    }
    if (RegExp(r'[^\x00-\x7F]').hasMatch(s)) {
      // Homoglyph guard. Worth its own message: the entry looks correct on
      // screen, so a generic "invalid" would send the admin hunting for a typo
      // that is invisible.
      return const AdminDomainInput.rejected(
          'This contains non-Latin characters that look like normal letters. '
          'Retype it rather than pasting.');
    }
    return AdminDomainInput.rejected('"$s" isn\'t a valid domain.');
  }

  return AdminDomainInput.accepted(
    domain,
    isPublicProvider: kPublicEmailProviders.contains(domain),
  );
}
