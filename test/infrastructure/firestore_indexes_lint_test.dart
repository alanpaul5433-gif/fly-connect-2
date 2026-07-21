// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint pass for `firestore.indexes.json`.
///
/// # Why this test exists
///
/// Firestore composite indexes are not auto-discovered locally. The Firebase
/// emulator enforces them strictly, but `flutter test` does not — so a query
/// that needs a composite index will look fine in unit tests, compile fine,
/// pass code review, and then 500 the first time it runs against production
/// data with the message:
///
///     FAILED_PRECONDITION: The query requires an index. You can create it
///     here: https://console.firebase.google.com/...
///
/// Anyone who's shipped a real Firestore app has been bitten by this.
///
/// This test enumerates every `.where()` + `.orderBy()` query we actually
/// run (the [_queries] list below), derives what composite index each one
/// requires according to Firestore's rules, and asserts the index exists in
/// `firestore.indexes.json`. If you add a new query you must:
///   1. Add it to the [_queries] list
///   2. If the lint then fails, add the missing index to
///      `firestore.indexes.json` and re-run.
///
/// # Composite-index rules implemented
///
/// A composite index is required when ANY of these is true:
///   • The query has an `arrayContains` (or `arrayContainsAny`) clause AND
///     **any** other `where` clause or an `orderBy` on a different field.
///   • The query has an inequality / range filter (`<`, `<=`, `>`, `>=`,
///     `!=`) AND an `orderBy` on a different field.
///   • The query has one or more equality `where` clauses AND an
///     `orderBy` on a field not covered by the equality.
///   • The query has two or more inequality / range / array filters on
///     **different** fields (always — multiple ranges are illegal without
///     a composite anyway).
///
/// What does NOT need a composite index (Firestore auto-creates single-field
/// indexes for every scalar field in a document):
///   • A single equality `where` with no `orderBy`
///   • A single `orderBy` with no `where`
///   • Range `where` + `orderBy` on the **same** field
///   • Multiple equality filters with no `orderBy` (merged via index
///     intersection at query time)
///
/// # Caveats
///
/// • This is a static lint of a manually-maintained list. It cannot find
///   queries we forgot to register. The real source of truth for missing
///   indexes is the Firestore emulator running an integration test, which
///   we don't have a CI runner for yet. Until then, this catches the
///   common "added a query, forgot the index" mistake.
/// • The list below intentionally omits subcollection queries
///   (`users/{uid}/trips`) where the `orderBy` field is the only filter —
///   those use the automatic single-field index on the subcollection.
void main() {
  late Map<String, dynamic> indexesJson;
  late List<_DeclaredIndex> declared;

  setUpAll(() {
    final file = File('firestore.indexes.json');
    expect(file.existsSync(), isTrue,
        reason: 'firestore.indexes.json must exist at the repo root');
    indexesJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final raw = (indexesJson['indexes'] as List).cast<Map<String, dynamic>>();
    declared = raw.map(_DeclaredIndex.fromJson).toList();
  });

  group('firestore.indexes.json', () {
    test('is valid JSON with an "indexes" array', () {
      expect(indexesJson['indexes'], isA<List>());
    });

    test('each declared index has a unique field-set on its collection', () {
      final seen = <String>{};
      for (final idx in declared) {
        final key = '${idx.collection}::${idx.fields.join("|")}';
        expect(seen.add(key), isTrue,
            reason: 'Duplicate index on $key — drop one');
      }
    });

    test('every query that needs a composite index has one declared', () {
      final missing = <_QuerySpec>[];
      for (final q in _queries) {
        if (!_requiresCompositeIndex(q)) continue;
        if (!declared.any((d) => d.satisfies(q))) {
          missing.add(q);
        }
      }
      if (missing.isNotEmpty) {
        final lines = missing
            .map((q) => '  • ${q.label}: ${q.indexHint}')
            .join('\n');
        fail('Missing composite indexes for:\n$lines\n\n'
            'Add the corresponding entries to firestore.indexes.json and '
            'redeploy (`firebase deploy --only firestore:indexes`).');
      }
    });

    test('every declared composite index is used by at least one query', () {
      // Indexes that nothing uses are dead weight — they take write-amplification
      // cost in Firestore but never benefit reads. Flag them so we either:
      //   (a) hook them up to a query that needs them, or
      //   (b) delete them from firestore.indexes.json.
      //
      // Some indexes here are *speculative* — declared ahead of a planned
      // feature. Allow-list those with their stated reason.
      const speculative = {
        'safeChecks::status,expiresAt':
            'planned for the SafeCheck "active alerts" admin filter',
        'reports::status,createdAt':
            'planned for filtering moderation queue by status',
      };

      final unused = <_DeclaredIndex>[];
      for (final d in declared) {
        final used = _queries
            .where(_requiresCompositeIndex)
            .any((q) => d.satisfies(q));
        if (!used) unused.add(d);
      }
      final unjustified = unused.where((d) {
        final key = '${d.collection}::${d.fields.join(",")}';
        return !speculative.containsKey(key);
      }).toList();
      if (unjustified.isNotEmpty) {
        final lines = unjustified
            .map((d) =>
                '  • ${d.collection} (${d.fields.join(", ")})')
            .join('\n');
        fail('These composite indexes are declared but no registered '
            'query uses them:\n$lines\n\n'
            'Either register the query in test/infrastructure/'
            'firestore_indexes_lint_test.dart#_queries or delete the '
            'index from firestore.indexes.json.');
      }
    });
  });
}

// ─── Catalogue of real Firestore queries ────────────────────────────
//
// Format: every query the production code runs that has at least one
// `where`/`orderBy`/`arrayContains` clause goes here. Subcollection
// queries (e.g. /users/{uid}/trips) are not represented as their parent
// path because Firestore indexes subcollections by their leaf name —
// only the leaf collection ("trips") matters for composite indexing.
final List<_QuerySpec> _queries = [
  // ── posts ─────────────────────────────────────────────────────
  const _QuerySpec(
    label: 'home feed (PostProvider._resubscribeFeed)',
    collection: 'posts',
    equalities: ['audience'],
    orderBy: 'createdAt',
  ),
  const _QuerySpec(
    label: 'user posts (PostRepo.watchUserPosts, GDPR export)',
    collection: 'posts',
    equalities: ['authorId'],
    orderBy: 'createdAt',
  ),
  const _QuerySpec(
    label: 'reported posts (admin content)',
    collection: 'posts',
    equalities: ['isReported'],
    orderBy: 'reportCount',
  ),

  // ── events ────────────────────────────────────────────────────
  const _QuerySpec(
    label: 'events feed (EventProvider._subscribeEvents)',
    collection: 'events',
    orderBy: 'date',
  ),
  const _QuerySpec(
    label: 'approved events (EventRepo.watchEvents)',
    collection: 'events',
    equalities: ['isApproved'],
    orderBy: 'date',
  ),

  // ── chats ─────────────────────────────────────────────────────
  const _QuerySpec(
    label: 'my chats (ChatProvider._subscribeChats / ChatRepo)',
    collection: 'chats',
    arrayContains: 'participants',
    orderBy: 'lastMessageAt',
  ),
  const _QuerySpec(
    label: 'find DM with user (ChatProvider.openOrCreateDm)',
    collection: 'chats',
    equalities: ['type'],
    arrayContains: 'participants',
  ),

  // ── messages (subcollection — leaf collection name only) ──────
  const _QuerySpec(
    label: 'conversation messages (ChatProvider.watchMessages)',
    collection: 'messages',
    orderBy: 'createdAt',
  ),

  // ── notifications ─────────────────────────────────────────────
  const _QuerySpec(
    label: 'my notifications (NotificationProvider._subscribeNotifications)',
    collection: 'notifications',
    equalities: ['userId'],
    orderBy: 'createdAt',
  ),

  // ── trips (subcollection — only the leaf "trips" indexes) ─────
  const _QuerySpec(
    label: 'user trips (TripRepo.watchTrips)',
    collection: 'trips',
    orderBy: 'startDate',
  ),
  const _QuerySpec(
    // top-level "trips" with userId filter (legacy/admin pathways)
    label: 'top-level trips by user',
    collection: 'trips',
    equalities: ['userId'],
    orderBy: 'startDate',
  ),

  // ── users ─────────────────────────────────────────────────────
  const _QuerySpec(
    label: 'crew-only directory (nearby_users_screen / repos)',
    collection: 'users',
    equalities: ['role'],
  ),
  const _QuerySpec(
    label: 'name prefix search (SearchProvider/UserRepo)',
    collection: 'users',
    ranges: ['name'],
    // Range + no orderBy → single-field index suffices.
  ),

  // ── matches ───────────────────────────────────────────────────
  const _QuerySpec(
    label: 'my matches (MatchRepo.watchMatches)',
    collection: 'matches',
    equalities: ['userA', 'status'],
  ),
  const _QuerySpec(
    label: 'pending reciprocal like (MatchRepo.likeUser)',
    collection: 'matches',
    equalities: ['userA', 'userB', 'status'],
  ),

  // ── groups ────────────────────────────────────────────────────
  const _QuerySpec(
    label: 'popular groups (GroupRepo)',
    collection: 'groups',
    orderBy: 'memberCount',
  ),
  const _QuerySpec(
    label: 'my groups (GroupRepo)',
    collection: 'groups',
    arrayContains: 'members',
  ),

  // ── admin: GDPR ───────────────────────────────────────────────
  const _QuerySpec(
    label: 'GDPR queue (admin_gdpr_page)',
    collection: 'gdpr_requests',
    orderBy: 'createdAt',
  ),

  // ── admin: audit_log ──────────────────────────────────────────
  const _QuerySpec(
    label: 'audit log (admin_audit_page)',
    collection: 'audit_log',
    orderBy: 'timestamp',
  ),

  // ── admin: reports / safeChecks ───────────────────────────────
  const _QuerySpec(
    label: 'reports queue (admin_reports_page)',
    collection: 'reports',
    orderBy: 'createdAt',
  ),
  const _QuerySpec(
    label: 'safeCheck stream (admin, unconstrained)',
    collection: 'safeChecks',
    orderBy: 'createdAt',
  ),
  // H18: SafeCheckProvider now runs one constrained subscription per
  // visibility branch, because the rules only admit a provably-scoped query.
  const _QuerySpec(
    label: 'safeChecks visible to everyone (SafeCheckProvider "all"/"verified")',
    collection: 'safeChecks',
    equalities: ['visibility'],
    orderBy: 'createdAt',
  ),
  const _QuerySpec(
    label: 'own safeCheck history (SafeCheckProvider "mine")',
    collection: 'safeChecks',
    equalities: ['userId'],
    orderBy: 'createdAt',
  ),
  const _QuerySpec(
    label: 'friends-only safeChecks (SafeCheckProvider "friends")',
    collection: 'safeChecks',
    equalities: ['visibility'],
    arrayContains: 'visibleTo',
    orderBy: 'createdAt',
  ),
  const _QuerySpec(
    label: 'need-help safeChecks (admin_dashboard)',
    collection: 'safeChecks',
    equalities: ['status'],
  ),

  // ── promotions ────────────────────────────────────────────────
  const _QuerySpec(
    label: 'promotions list (admin_promotions_page)',
    collection: 'promotions',
    orderBy: 'createdAt',
  ),
];

// ─── Query → composite-index logic ──────────────────────────────────
class _QuerySpec {
  /// Human label shown in failure messages. No semantic meaning.
  final String label;
  final String collection;

  /// `where('x', isEqualTo: ...)` fields, in the order they appear in code.
  final List<String> equalities;

  /// `where('x', isGreaterThan: ...)` / `<` / `!=` fields.
  final List<String> ranges;

  /// `where('x', arrayContains: ...)`. Firestore allows at most one per query.
  final String? arrayContains;

  final String? orderBy;

  const _QuerySpec({
    required this.label,
    required this.collection,
    this.equalities = const [],
    this.ranges = const [],
    this.arrayContains,
    this.orderBy,
  });

  /// Suggested index entry for the failure message — what to add to JSON.
  String get indexHint {
    final fields = <String>[
      ...equalities,
      if (arrayContains != null) '$arrayContains (arrayContains)',
      if (orderBy != null && !equalities.contains(orderBy)) orderBy!,
    ];
    return '$collection (${fields.join(", ")})';
  }
}

bool _requiresCompositeIndex(_QuerySpec q) {
  // arrayContains combined with any other where or any orderBy:
  if (q.arrayContains != null) {
    if (q.equalities.isNotEmpty || q.ranges.isNotEmpty) return true;
    if (q.orderBy != null && q.orderBy != q.arrayContains) return true;
    return false;
  }
  // range + orderBy on a different field:
  if (q.ranges.isNotEmpty) {
    if (q.ranges.length > 1) return true; // multi-range is illegal w/o
    if (q.orderBy != null && q.orderBy != q.ranges.single) return true;
    return false;
  }
  // equality(ies) + orderBy on a field not in the equalities:
  if (q.equalities.isNotEmpty && q.orderBy != null) {
    if (!q.equalities.contains(q.orderBy)) return true;
  }
  return false;
}

class _DeclaredIndex {
  final String collection;
  final List<String> fields; // ordered

  const _DeclaredIndex(this.collection, this.fields);

  factory _DeclaredIndex.fromJson(Map<String, dynamic> j) {
    final col = j['collectionGroup'] as String;
    final fields = (j['fields'] as List).cast<Map<String, dynamic>>()
        .map((f) => f['fieldPath'] as String)
        .toList();
    return _DeclaredIndex(col, fields);
  }

  /// Returns true if this declared index covers the given query — i.e.
  /// the index's fields contain every equality/arrayContains/orderBy
  /// field the query uses, in a valid order.
  ///
  /// Strict ordering rules of Firestore composite indexes:
  ///   • Equality fields can appear in any order before the
  ///     arrayContains / range / orderBy field.
  ///   • The arrayContains / range field must precede the orderBy
  ///     field in the index when both are present (Firestore enforces).
  ///
  /// We implement a tolerant check: every required field must be in
  /// the index, and any orderBy must appear *after* its companion
  /// arrayContains/range. That's enough to catch missing indexes
  /// without false-negatives from minor field-order quirks.
  bool satisfies(_QuerySpec q) {
    if (collection != q.collection) return false;

    final needed = <String>{
      ...q.equalities,
      if (q.arrayContains != null) q.arrayContains!,
      if (q.orderBy != null && q.orderBy != q.arrayContains)
        q.orderBy!,
    };
    if (!needed.every(fields.contains)) return false;

    // orderBy must come after the arrayContains field in the index, if both present.
    if (q.arrayContains != null && q.orderBy != null &&
        q.orderBy != q.arrayContains) {
      final ac = fields.indexOf(q.arrayContains!);
      final ob = fields.indexOf(q.orderBy!);
      if (ac >= ob) return false;
    }
    return true;
  }
}
