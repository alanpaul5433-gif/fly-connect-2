/// DEV-ONLY seeder. NOT shipped with production builds.
///
/// Seeds Firestore with test data for the new admin pages:
///   - reports          (Unified Reports Queue)
///   - gdpr_requests    (Privacy/GDPR Center)
///   - audit_log        (Admin Audit Log)
///   - promotions       (extra pending ones for Promotions Approval)
///
/// Run:
///   flutter run -t tools/seed_admin_data.dart -d chrome --web-port 8090
///
/// Auto-runs on launch (no button click required). Safe to re-run; each
/// call adds a fresh batch with timestamped IDs.
library;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flyconnect/core/config/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: FirebaseConfig.currentPlatformOptions);
  runApp(const _SeedApp());
}

class _SeedApp extends StatelessWidget {
  const _SeedApp();
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: _Seeder()));
}

class _Seeder extends StatefulWidget {
  const _Seeder();
  @override
  State<_Seeder> createState() => _SeederState();
}

class _SeederState extends State<_Seeder> {
  String _status = 'Auto-seeding admin test data…';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seed());
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done) const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_status, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );

  Future<void> _seed() async {
    try {
      final db = FirebaseFirestore.instance;
      final now = DateTime.now();

      // Look up real seeded UIDs from existing `users` collection so foreign keys are valid.
      final userSnap = await db.collection('users').limit(20).get();
      final userIds = userSnap.docs.map((d) => d.id).toList();
      final userNames = {for (final d in userSnap.docs) d.id: d.data()['name'] ?? 'User'};
      final userEmails = {for (final d in userSnap.docs) d.id: d.data()['email'] ?? ''};

      String pickUid(int i) => userIds.isEmpty ? 'demo_uid_$i' : userIds[i % userIds.length];
      String pickName(String uid) => userNames[uid] ?? 'Demo User';

      // ── 0. Backfill `isApproved` on existing promotions ────
      // Promotions seeded before the approval gate was added are missing this field.
      // Default them to approved so the consumer feed keeps showing them.
      setState(() => _status = 'Backfilling existing promotions…');
      final promoSnap = await db.collection('promotions').get();
      int backfilled = 0;
      for (final doc in promoSnap.docs) {
        if (!doc.data().containsKey('isApproved')) {
          await doc.reference.update({'isApproved': true});
          backfilled++;
        }
      }
      debugPrint('[SeedAdmin] backfilled isApproved on $backfilled promotions');

      // ── 1. Reports (unified queue) ─────────────────────────
      setState(() => _status = 'Seeding reports…');
      final reports = [
        {'type': 'post', 'reason': 'Spam content', 'description': 'User posting same link multiple times across feed', 'severity': 'high'},
        {'type': 'user', 'reason': 'Harassment', 'description': 'Sending threatening DMs to multiple crew members', 'severity': 'high'},
        {'type': 'chat', 'reason': 'Inappropriate language', 'description': 'Profanity in group chat "NYC Crew"', 'severity': 'medium'},
        {'type': 'comment', 'reason': 'Hate speech', 'description': 'Discriminatory comment on a passport photo', 'severity': 'high'},
        {'type': 'trip', 'reason': 'Fake location', 'description': 'Trip claims layover in country user has never visited', 'severity': 'low'},
        {'type': 'post', 'reason': 'Misinformation', 'description': 'False rumour about flight cancellations causing panic', 'severity': 'medium'},
        {'type': 'user', 'reason': 'Impersonation', 'description': 'Profile claims to be a Delta captain — unverified', 'severity': 'medium'},
        {'type': 'post', 'reason': 'Off-topic / Spam', 'description': 'Promotional pitch unrelated to aviation', 'severity': 'low'},
        {'type': 'chat', 'reason': 'Solicitation', 'description': 'Trying to sell counterfeit airline merchandise in DM', 'severity': 'medium'},
        {'type': 'comment', 'reason': 'Personal attack', 'description': 'Calling out a crew member by name with insults', 'severity': 'high'},
      ];
      for (int i = 0; i < reports.length; i++) {
        final r = reports[i];
        final reporter = pickUid(i);
        final target = pickUid(i + 1);
        await db.collection('reports').add({
          'type': r['type'],
          'targetId': target,
          'targetName': pickName(target),
          'reporterId': reporter,
          'reporterName': pickName(reporter),
          'reason': r['reason'],
          'description': r['description'],
          'severity': r['severity'],
          'status': i < 7 ? 'pending' : (i == 7 ? 'resolved' : 'dismissed'),
          'createdAt': Timestamp.fromDate(now.subtract(Duration(hours: i * 3 + 1))),
        });
      }

      // ── 2. GDPR Requests ───────────────────────────────────
      setState(() => _status = 'Seeding GDPR requests…');
      final gdpr = [
        {'type': 'export', 'status': 'pending', 'notes': 'Routine annual data export request'},
        {'type': 'delete', 'status': 'pending', 'notes': 'User leaving the industry, wants full deletion'},
        {'type': 'export', 'status': 'processing', 'notes': 'Compiling data, ETA 2 days'},
        {'type': 'delete', 'status': 'completed', 'notes': 'All user data successfully removed'},
        {'type': 'export', 'status': 'completed', 'notes': 'CSV delivered via secure link'},
        {'type': 'delete', 'status': 'rejected', 'notes': 'Active legal hold on account — cannot delete yet'},
        {'type': 'export', 'status': 'pending', 'notes': 'GDPR request from EU resident'},
      ];
      for (int i = 0; i < gdpr.length; i++) {
        final g = gdpr[i];
        final uid = pickUid(i);
        await db.collection('gdpr_requests').add({
          'userId': uid,
          'userName': pickName(uid),
          'userEmail': userEmails[uid] ?? 'user@example.com',
          'requestType': g['type'],
          'status': g['status'],
          'notes': g['notes'],
          'createdAt': Timestamp.fromDate(now.subtract(Duration(days: i * 2 + 1))),
          'completedAt': g['status'] == 'completed'
              ? Timestamp.fromDate(now.subtract(Duration(days: i)))
              : null,
        });
      }

      // ── 3. Audit Log (historical admin actions) ────────────
      setState(() => _status = 'Seeding audit log…');
      final adminUid = userIds.isNotEmpty ? userIds.first : 'admin_uid';
      final adminName = pickName(adminUid);
      final actions = [
        {'action': 'ban_user', 'targetType': 'user', 'details': 'Banned spam account "FakeAirlineDeals"'},
        {'action': 'approve_event', 'targetType': 'event', 'details': 'Approved "JFK Crew Trivia Night"'},
        {'action': 'reject_promotion', 'targetType': 'promotion', 'details': 'Rejected misleading "90% off all flights" promo'},
        {'action': 'resolve_safecheck', 'targetType': 'safecheck', 'details': 'Resolved Need-Help at ATL Terminal B'},
        {'action': 'verify_user', 'targetType': 'user', 'details': 'Verified pilot credential for user_007'},
        {'action': 'remove_post', 'targetType': 'post', 'details': 'Removed off-topic promotional post'},
        {'action': 'verify_business', 'targetType': 'business', 'details': 'Verified Sky Lounge NYC after EIN check'},
        {'action': 'feature_event', 'targetType': 'event', 'details': 'Featured "Pacific NW Pilots Meetup"'},
        {'action': 'complete_gdpr', 'targetType': 'gdpr_request', 'details': 'Completed export request for EU user'},
        {'action': 'resolved_report', 'targetType': 'report', 'details': 'Resolved harassment report after warning'},
        {'action': 'unban_user', 'targetType': 'user', 'details': 'Unbanned account after appeal review'},
        {'action': 'reject_event', 'targetType': 'event', 'details': 'Rejected duplicate event posting'},
        {'action': 'dismissed_report', 'targetType': 'report', 'details': 'Dismissed report — content within guidelines'},
        {'action': 'approve_promotion', 'targetType': 'promotion', 'details': 'Approved Sky Lounge welcome drink offer'},
        {'action': 'activate_promotion', 'targetType': 'promotion', 'details': 'Reactivated paused holiday promo'},
      ];
      for (int i = 0; i < actions.length; i++) {
        final a = actions[i];
        await db.collection('audit_log').add({
          'adminId': adminUid,
          'adminName': adminName,
          'action': a['action'],
          'targetType': a['targetType'],
          'targetId': 'demo_target_${i + 1}',
          'details': a['details'],
          'timestamp': Timestamp.fromDate(now.subtract(Duration(minutes: i * 47 + 5))),
        });
      }

      // ── 4. Promotions (extra pending for approval queue) ───
      setState(() => _status = 'Seeding extra pending promotions…');
      final extraPromos = [
        {'title': '50% Off Crew Meals', 'desc': 'Half-price crew menu at Concourse C diner', 'pct': 50, 'pending': true},
        {'title': 'Free WiFi 30-day Pass', 'desc': 'Complimentary airport WiFi for FlyConnect members', 'pct': 100, 'pending': true},
        {'title': 'Holiday Lounge Discount', 'desc': 'Seasonal access pricing', 'pct': 25, 'pending': false},
      ];
      for (int i = 0; i < extraPromos.length; i++) {
        final p = extraPromos[i];
        await db.collection('promotions').add({
          'title': p['title'],
          'description': p['desc'],
          'discountPercent': p['pct'],
          'businessName': 'Sky Lounge NYC',
          'businessId': adminUid,
          'imageUrl': 'https://picsum.photos/seed/admin_promo$i/600/400',
          'isApproved': !(p['pending'] as bool),
          'isActive': !(p['pending'] as bool),
          'views': 0,
          'redemptions': 0,
          'validFrom': Timestamp.fromDate(now),
          'validTo': Timestamp.fromDate(now.add(const Duration(days: 30))),
          'createdAt': Timestamp.fromDate(now.subtract(Duration(hours: i * 2))),
        });
      }

      setState(() {
        _done = true;
        _status = 'Done!\n'
            '  • ${reports.length} reports\n'
            '  • ${gdpr.length} GDPR requests\n'
            '  • ${actions.length} audit log entries\n'
            '  • ${extraPromos.length} extra promotions\n\n'
            'You can close this tab and run lib/main.dart now.';
      });
    } catch (e, st) {
      debugPrint('[SeedAdmin] failed: $e\n$st');
      setState(() => _status = 'Error: $e');
    }
  }
}
