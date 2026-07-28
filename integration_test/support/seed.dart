/// Constants that mirror the deterministic fixtures created by
/// `tools/seed_emulator.js`. The runner clears + re-seeds the emulator before
/// every test FILE, so each file can rely on exactly this starting state.
///
/// Keep this in lock-step with `tools/seed_emulator.js` — if a UID/email is
/// changed there, change it here.
library;

/// Every seeded account uses this password.
const String kTestPassword = 'Test1234!';

// ── Crew accounts (role 'user') ──────────────────────────────
const String kAlexUid = 'uid_alex';
const String kAlexEmail = 'alex@delta.com'; // verified
const String kAlexName = 'Alex Johnson';

const String kMariaUid = 'uid_maria';
const String kMariaEmail = 'maria@united.com'; // verified
const String kMariaName = 'Maria Chen';

const String kJamesUid = 'uid_james';
const String kJamesEmail = 'james@american.com'; // unverified
const String kJamesName = 'James Wright';

const String kSaraUid = 'uid_sara';
const String kMikeUid = 'uid_mike';
const String kPriyaUid = 'uid_priya';

// ── Business accounts ────────────────────────────────────────
const String kSkyLoungeUid = 'uid_skylounge'; // verified business ("store")
const String kSkyLoungeEmail = 'info@skyloungelnyc.com';
const String kSkyLoungeName = 'Sky Lounge NYC';

const String kPendingBizUid = 'uid_pendingbiz'; // verificationStatus 'pending'
const String kPendingBizEmail = 'newbiz@flyconnect.com';

// ── Admin ────────────────────────────────────────────────────
const String kAdminUid = 'uid_admin';
const String kAdminEmail = 'admin@flyconnect.com';

// ── Seeded posts ─────────────────────────────────────────────
const String kAlexPostId = 'post_1';
const String kMariaPostId = 'post_2';
const String kJamesPostId = 'post_3';
const String kJamesPostCaption = 'Just got my ATP certificate! Dream achieved!';

// ── Seeded promotions ────────────────────────────────────────
const String kApprovedPromoId = 'promo_1';
const String kPendingPromoId = 'promo_pending';

// ── Allowed / disallowed signup domains ──────────────────────
const String kAllowedDomain = 'delta.com';
const String kDisallowedDomain = 'evil.com';

/// A per-run suffix so data a test CREATES (emails, captions) is unique across
/// re-runs within a single emulator lifetime. The runner reseeds per file, but
/// a flaky retry inside one file must not collide with a half-written doc.
String uniqueRunId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36);
