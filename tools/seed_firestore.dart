/// DEV-ONLY seeder. NOT shipped with production builds.
///
/// Run: flutter run -t tools/seed_firestore.dart -d chrome
/// Seeds Firestore with sample data for development/demo.
/// Run ONCE, then switch back to lib/main.dart.
library;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flyconnect/core/config/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseConfig.currentPlatformOptions,
  );
  runApp(const _SeedApp());
}

class _SeedApp extends StatelessWidget {
  const _SeedApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: _SeedButton())),
  );
}

class _SeedButton extends StatefulWidget {
  @override State<_SeedButton> createState() => _SeedButtonState();
}

class _SeedButtonState extends State<_SeedButton> {
  String _status = 'Auto-seeding...';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seed());
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(_status, style: const TextStyle(fontSize: 16)),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: _running ? null : _seed,
        child: const Text('Seed Firestore'),
      ),
    ],
  );

  Future<void> _seed() async {
    setState(() { _running = true; _status = 'Seeding...'; });
    final db = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final now = DateTime.now();

    try {
      // ── 1. Create auth users ─────────────────────────────────
      setState(() => _status = 'Creating users...');
      final users = [
        {'email': 'alex@delta.com', 'pass': 'Test1234!', 'name': 'Alex Johnson', 'airline': 'Delta Air Lines', 'position': 'Pilot', 'airport': 'JFK', 'city': 'New York', 'state': 'NY', 'bio': 'Senior pilot with 12 years of experience. Love exploring new cities on layovers', 'role': 'user', 'matchType': 'buddy', 'hobbies': ['Photography', 'Hiking', 'Coffee', 'Travel'], 'stamps': ['US','GB','JP','FR','DE','AU'], 'verified': true, 'photo': 'https://i.pravatar.cc/200?img=11'},
        {'email': 'maria@united.com', 'pass': 'Test1234!', 'name': 'Maria Chen', 'airline': 'United Airlines', 'position': 'Flight Attendant', 'airport': 'LAX', 'city': 'Los Angeles', 'state': 'CA', 'bio': 'Flight attendant & foodie. Based in LA.', 'role': 'user', 'matchType': 'dating', 'hobbies': ['Cooking', 'Yoga', 'Photography'], 'stamps': ['US','JP','TH','SG'], 'verified': true, 'photo': 'https://i.pravatar.cc/200?img=5'},
        {'email': 'james@american.com', 'pass': 'Test1234!', 'name': 'James Wright', 'airline': 'American Airlines', 'position': 'Co-Pilot', 'airport': 'ORD', 'city': 'Chicago', 'state': 'IL', 'bio': 'Co-pilot, aviation nerd, coffee addict', 'role': 'user', 'matchType': 'buddy', 'hobbies': ['Cycling', 'Gaming', 'Coffee'], 'stamps': ['US','CA','MX','GB'], 'verified': false, 'photo': 'https://i.pravatar.cc/200?img=12'},
        {'email': 'sara@jetblue.com', 'pass': 'Test1234!', 'name': 'Sara Lim', 'airline': 'JetBlue', 'position': 'Gate Agent', 'airport': 'BOS', 'city': 'Boston', 'state': 'MA', 'bio': 'Gate agent turning delays into adventures', 'role': 'user', 'matchType': 'solo', 'hobbies': ['Reading', 'Running', 'Art'], 'stamps': ['US','FR','ES','IT'], 'verified': true, 'photo': 'https://i.pravatar.cc/200?img=16'},
        {'email': 'mike@southwest.com', 'pass': 'Test1234!', 'name': 'Mike Torres', 'airline': 'Southwest Airlines', 'position': 'Ground Crew', 'airport': 'DAL', 'city': 'Dallas', 'state': 'TX', 'bio': 'Ground crew keeping the skies safe', 'role': 'user', 'matchType': 'all', 'hobbies': ['Surfing', 'Camping', 'Fitness'], 'stamps': ['US','MX','BR','CA'], 'verified': false, 'photo': 'https://i.pravatar.cc/200?img=15'},
        {'email': 'priya@alaska.com', 'pass': 'Test1234!', 'name': 'Priya Patel', 'airline': 'Alaska Airlines', 'position': 'Flight Attendant', 'airport': 'SEA', 'city': 'Seattle', 'state': 'WA', 'bio': 'Pacific Northwest based FA. Mountains and planes', 'role': 'user', 'matchType': 'buddy', 'hobbies': ['Hiking', 'Photography', 'Yoga'], 'stamps': ['US','JP','IN','AU','CA','GB'], 'verified': true, 'photo': 'https://i.pravatar.cc/200?img=9'},
        {'email': 'info@skyloungelnyc.com', 'pass': 'Test1234!', 'name': 'Sky Lounge NYC', 'airline': null, 'position': 'Airport Lounge', 'airport': 'JFK', 'city': 'New York', 'state': 'NY', 'bio': 'Premium airport lounge at JFK Terminal 4. Relax, dine and unwind before your flight.', 'role': 'business', 'matchType': 'all', 'hobbies': <String>[], 'stamps': <String>[], 'verified': true, 'photo': 'https://picsum.photos/seed/lounge/200'},
      ];

      final uids = <String>[];
      for (final u in users) {
        try {
          final cred = await auth.createUserWithEmailAndPassword(
            email: u['email'] as String, password: u['pass'] as String);
          await cred.user!.updateDisplayName(u['name'] as String);
          uids.add(cred.user!.uid);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            final cred = await auth.signInWithEmailAndPassword(
              email: u['email'] as String, password: u['pass'] as String);
            uids.add(cred.user!.uid);
          } else {
            uids.add('fallback_${uids.length}');
          }
        }
        // Sign out so we can create next user
        await auth.signOut();
      }

      // Write user docs
      for (int i = 0; i < users.length; i++) {
        final u = users[i];
        await db.collection('users').doc(uids[i]).set({
          'name': u['name'], 'email': u['email'], 'photoUrl': u['photo'],
          'bio': u['bio'], 'airline': u['airline'], 'airport': u['airport'],
          'position': u['position'], 'city': u['city'], 'state': u['state'],
          'hobbies': u['hobbies'], 'passportStamps': u['stamps'],
          'travelHistory': <String>[], 'matchType': u['matchType'],
          'followerCount': (i + 1) * 100 + 34, 'followingCount': (i + 1) * 50,
          'postCount': i * 3 + 2, 'role': u['role'],
          'isVerified': u['verified'], 'isBanned': false,
          'createdAt': Timestamp.fromDate(now.subtract(Duration(days: 180 + i * 30))),
          'lastSeen': Timestamp.fromDate(now.subtract(Duration(minutes: i * 15))),
        });
      }

      // ── 2. Create posts ──────────────────────────────────────
      setState(() => _status = 'Creating posts...');
      final posts = [
        {'author': 0, 'caption': 'First solo transatlantic crossing as PIC! London to JFK. 7 hours of pure sky.', 'media': ['https://picsum.photos/seed/sky/800/600'], 'location': 'Over the Atlantic', 'likes': 621},
        {'author': 1, 'caption': 'Layover in Tokyo! Found the most amazing ramen spot near Shinjuku station.', 'media': ['https://picsum.photos/seed/tokyo/800/600'], 'location': 'Tokyo, Japan', 'likes': 142},
        {'author': 5, 'caption': 'Morning views from 35,000ft. Nothing beats a clear day over the Rockies.', 'media': ['https://picsum.photos/seed/clouds/800/600'], 'location': 'Over Colorado, USA', 'likes': 289},
        {'author': 2, 'caption': 'Just got my ATP certificate! After 3 years of grinding, dream achieved!', 'media': ['https://picsum.photos/seed/pilot/800/600'], 'location': 'Chicago, IL', 'likes': 534},
        {'author': 3, 'caption': 'Delayed flight turned into an impromptu book club with passengers. Best gate B42 moment!', 'media': ['https://picsum.photos/seed/airport/800/600'], 'location': 'Boston Logan Airport', 'likes': 198},
        {'author': 4, 'caption': 'After 6 years on the ramp, finally heading inside. New chapter begins!', 'media': ['https://picsum.photos/seed/ramp/800/600'], 'location': 'Dallas Love Field', 'likes': 412},
        {'author': 1, 'caption': 'Singapore Airlines Changi lounge is on another level. The infinity pool, sushi bar, the spa...', 'media': ['https://picsum.photos/seed/lounge/800/600'], 'location': 'Singapore Changi Airport', 'likes': 767},
        {'author': 0, 'caption': 'Tokyo layover — 24 hours in the city. Hit Shibuya crossing at midnight — absolutely wild.', 'media': [], 'location': 'Tokyo, Japan', 'likes': 438},
        {'author': 0, 'caption': '12 years flying and I still get this feeling every single takeoff. Never gets old.', 'media': [], 'location': 'JFK International Airport', 'likes': 892},
      ];

      for (int i = 0; i < posts.length; i++) {
        final p = posts[i];
        final authorIdx = p['author'] as int;
        final u = users[authorIdx];
        await db.collection('posts').doc('post_${i + 1}').set({
          'authorId': uids[authorIdx], 'authorName': u['name'], 'authorPhotoUrl': u['photo'],
          'caption': p['caption'], 'mediaUrls': p['media'],
          'mediaType': (p['media'] as List).isNotEmpty ? 'image' : 'text',
          'location': p['location'], 'likeCount': p['likes'], 'commentCount': i * 3 + 5,
          'isReported': false, 'reportCount': 0,
          'createdAt': Timestamp.fromDate(now.subtract(Duration(hours: i * 4 + 1))),
        });
      }

      // ── 3. Create events ─────────────────────────────────────
      setState(() => _status = 'Creating events...');
      final events = [
        {'title': 'Airport Crew Meetup — NYC', 'desc': 'Monthly gathering for all JFK/LGA/EWR based crew. Food, drinks, and great conversations.', 'loc': 'The Sky Lounge, Queens, NY', 'days': 5, 'time': '7:00 PM', 'creator': 0, 'rsvp': 47, 'approved': true, 'featured': true},
        {'title': 'Pilot Social — Chicago', 'desc': 'Casual evening for pilots and co-pilots based at ORD and MDW.', 'loc': "O'Hare Marriott, Chicago", 'days': 12, 'time': '6:30 PM', 'creator': 2, 'rsvp': 28, 'approved': true, 'featured': false},
        // Trimmed to 2 well-configured events for initial client testing.
      ];

      for (int i = 0; i < events.length; i++) {
        final e = events[i];
        await db.collection('events').doc('evt_${i + 1}').set({
          'title': e['title'], 'description': e['desc'], 'location': e['loc'],
          'date': Timestamp.fromDate(now.add(Duration(days: e['days'] as int))),
          'time': e['time'], 'createdBy': uids[e['creator'] as int],
          'rsvpCount': e['rsvp'], 'rsvpList': <String>[],
          'isApproved': e['approved'], 'isFeatured': e['featured'],
          'requirements': <String>[], 'createdAt': Timestamp.fromDate(now.subtract(Duration(days: i + 2))),
        });
      }

      // ── 4. Create groups ─────────────────────────────────────
      setState(() => _status = 'Creating groups...');
      final groups = [
        {'name': 'Delta Crew NYC', 'desc': 'Official group for all Delta employees based in the New York area.', 'creator': 0, 'members': [0, 1, 2], 'count': 342, 'tags': ['Delta', 'NYC', 'Aviation'], 'pinned': true},
        {'name': 'Layover Adventures', 'desc': 'For crew who love exploring cities during layovers.', 'creator': 5, 'members': [0, 5, 3], 'count': 1247, 'tags': ['Travel', 'Layover', 'Food'], 'pinned': true},
        // Trimmed to 2 well-configured groups for initial client testing.
      ];

      for (int i = 0; i < groups.length; i++) {
        final g = groups[i];
        final memberUids = (g['members'] as List<int>).map((idx) => uids[idx]).toList();
        await db.collection('groups').doc('grp_${i + 1}').set({
          'name': g['name'], 'description': g['desc'],
          'createdBy': uids[g['creator'] as int],
          'members': memberUids, 'admins': [uids[g['creator'] as int]],
          'memberCount': g['count'], 'isPublic': true,
          'tags': g['tags'], 'isPinned': g['pinned'],
          'createdAt': Timestamp.fromDate(now.subtract(Duration(days: 60 + i * 40))),
        });
      }

      // ── 5. Create promotions ─────────────────────────────────
      setState(() => _status = 'Creating promotions...');
      final promos = [
        {'title': 'Welcome Drink on Us', 'desc': 'Enjoy a complimentary welcome drink when you visit Sky Lounge at JFK Terminal 4.', 'discount': 20, 'days': 30, 'max': 100, 'current': 34, 'views': 892, 'saves': 145},
        {'title': 'Priority Lane Access', 'desc': 'Skip the queue with our priority security lane. Available at all major terminals.', 'discount': 15, 'days': 14, 'max': 50, 'current': 12, 'views': 445, 'saves': 67},
        {'title': 'Crew Spa Package', 'desc': 'Exclusive 30% off spa treatments for FlyConnect members. Relax between flights.', 'discount': 30, 'days': 45, 'max': 75, 'current': 8, 'views': 234, 'saves': 89},
      ];

      for (int i = 0; i < promos.length; i++) {
        final p = promos[i];
        await db.collection('promotions').doc('promo_${i + 1}').set({
          'businessId': uids[6], 'businessName': 'Sky Lounge NYC',
          'title': p['title'], 'description': p['desc'],
          'imageUrl': 'https://picsum.photos/seed/promo${i + 1}/800/400',
          'discountPercent': p['discount'],
          'validFrom': Timestamp.fromDate(now),
          'validTo': Timestamp.fromDate(now.add(Duration(days: p['days'] as int))),
          'maxRedemptions': p['max'], 'currentRedemptions': p['current'],
          'views': p['views'], 'saves': p['saves'], 'isActive': true, 'isApproved': true,
        });
      }

      // ── 6. Create notifications ──────────────────────────────
      setState(() => _status = 'Creating notifications...');
      if (uids.isNotEmpty && uids[0] != 'fallback_0') {
        final notifs = [
          {'type': 'like', 'title': 'Maria Chen liked your post', 'body': '"First solo transatlantic crossing..."', 'mins': 10},
          {'type': 'comment', 'title': 'James Wright commented', 'body': '"Congrats on the ATP! Well deserved"', 'mins': 25},
          {'type': 'follow', 'title': 'Priya Patel started following you', 'body': 'Flight Attendant at Alaska Airlines', 'mins': 60},
          {'type': 'match', 'title': 'New match!', 'body': 'You matched with Sara Lim', 'mins': 180},
          {'type': 'event', 'title': 'Event reminder', 'body': 'Crew Trivia Night is in 3 days!', 'mins': 360},
          {'type': 'safecheck', 'title': 'SafeCheck Alert', 'body': 'Mike Torres needs help near JFK Terminal B', 'mins': 45},
        ];

        for (int i = 0; i < notifs.length; i++) {
          final n = notifs[i];
          await db.collection('notifications').doc('notif_${i + 1}').set({
            'userId': uids[0], 'type': n['type'], 'title': n['title'], 'body': n['body'],
            'isRead': i > 2, 'createdAt': Timestamp.fromDate(now.subtract(Duration(minutes: n['mins'] as int))),
          });
        }
      }

      // ── 7. Create SafeCheck entries ──────────────────────────
      setState(() => _status = 'Creating SafeCheck entries...');
      final checks = [
        {'user': 1, 'status': 'safe', 'msg': 'Landed safely at LAX!', 'city': 'New York', 'lat': 40.7158, 'lng': -74.0020, 'mins': 120},
        {'user': 2, 'status': 'unsure', 'msg': 'Flight delayed, stuck at ORD', 'city': 'New York', 'lat': 40.7100, 'lng': -74.0100, 'mins': 60},
        {'user': 4, 'status': 'need_help', 'msg': 'Wallet stolen at terminal', 'city': 'New York', 'lat': 40.7090, 'lng': -74.0150, 'mins': 30},
        {'user': 3, 'status': 'safe', 'msg': null, 'city': 'New York', 'lat': 40.7180, 'lng': -73.9980, 'mins': 300},
      ];

      for (int i = 0; i < checks.length; i++) {
        final c = checks[i];
        final u = users[c['user'] as int];
        final createdAt = now.subtract(Duration(minutes: c['mins'] as int));
        await db.collection('safeChecks').doc('sc_${i + 1}').set({
          'userId': uids[c['user'] as int], 'userName': u['name'], 'userPhotoUrl': u['photo'],
          'status': c['status'], 'message': c['msg'], 'city': c['city'],
          'lat': c['lat'], 'lng': c['lng'],
          'createdAt': Timestamp.fromDate(createdAt),
          'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(hours: 24))),
        });
      }

      // ── 8. Create trips ──────────────────────────────────────
      setState(() => _status = 'Creating trips...');
      final trips = [
        {'user': 0, 'dest': 'Tokyo', 'code': 'JP', 'desc': 'Amazing layover — explored Shinjuku and Harajuku', 'daysAgo': 30},
        {'user': 0, 'dest': 'London', 'code': 'GB', 'desc': 'Pub crawl in Shoreditch, Borough Market food tour', 'daysAgo': 60},
        {'user': 0, 'dest': 'Paris', 'code': 'FR', 'desc': 'Eiffel Tower at sunset, best croissants of my life', 'daysAgo': 90},
        {'user': 1, 'dest': 'Bangkok', 'code': 'TH', 'desc': 'Street food paradise, temple hopping', 'daysAgo': 45},
        {'user': 5, 'dest': 'Osaka', 'code': 'JP', 'desc': 'Best takoyaki ever, Dotonbori at night', 'daysAgo': 20},
      ];

      for (int i = 0; i < trips.length; i++) {
        final t = trips[i];
        await db.collection('trips').doc('trip_${i + 1}').set({
          'userId': uids[t['user'] as int], 'destination': t['dest'],
          'countryCode': t['code'], 'description': t['desc'], 'photoUrls': <String>[],
          'startDate': Timestamp.fromDate(now.subtract(Duration(days: t['daysAgo'] as int))),
          'endDate': Timestamp.fromDate(now.subtract(Duration(days: (t['daysAgo'] as int) - 2))),
          'createdAt': Timestamp.fromDate(now.subtract(Duration(days: (t['daysAgo'] as int) - 2))),
        });
      }

      setState(() => _status = 'Done! Seeded 7 users, 9 posts, 2 events, 2 groups, 3 promotions, 6 notifications, 4 SafeChecks, 5 trips');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
    setState(() => _running = false);
  }
}
