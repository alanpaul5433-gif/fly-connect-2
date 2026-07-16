import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Tests for EventProvider.updateEvent/removeAttendee.
///
/// EventProvider hardcodes `FirebaseFirestore.instance` (no constructor DI),
/// so these tests can't instantiate the real provider — they seed a
/// FakeFirebaseFirestore and replay the exact read/write shape each method
/// performs, asserting against the fake db. Matches the existing convention
/// in test/providers/promotion_provider_test.dart.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('updateEvent', () {
    // Mirrors EventProvider.updateEvent's partial-update + no-op guard.
    Future<void> updateEventMirror(
      String eventId, {
      String? title,
      String? description,
      String? location,
      String? imageUrl,
    }) async {
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (description != null) updates['description'] = description;
      if (location != null) updates['location'] = location;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;
      if (updates.isEmpty) return;
      await db.collection('events').doc(eventId).update(updates);
    }

    test('writes only the provided field (title only)', () async {
      await db.collection('events').doc('evt-1').set({
        'title': 'Old title',
        'description': 'Old description',
        'location': 'Old location',
      });

      await updateEventMirror('evt-1', title: 'New title');

      final data = (await db.collection('events').doc('evt-1').get()).data()!;
      expect(data['title'], 'New title');
      expect(data['description'], 'Old description');
      expect(data['location'], 'Old location');
    });

    test('writes multiple provided fields together', () async {
      await db.collection('events').doc('evt-1').set({
        'title': 'Old title',
        'description': 'Old description',
        'location': 'Old location',
      });

      await updateEventMirror('evt-1',
          title: 'New title', location: 'New location');

      final data = (await db.collection('events').doc('evt-1').get()).data()!;
      expect(data['title'], 'New title');
      expect(data['description'], 'Old description');
      expect(data['location'], 'New location');
    });

    test('all-null args is a true no-op (no write happens)', () async {
      await db.collection('events').doc('evt-1').set({'title': 'Unchanged'});

      await updateEventMirror('evt-1');

      final data = (await db.collection('events').doc('evt-1').get()).data()!;
      expect(data['title'], 'Unchanged');
      expect(data.length, 1);
    });

    test('M-7: writes imageUrl for the cover-image edit path', () async {
      await db.collection('events').doc('evt-1').set({'title': 'Meetup', 'imageUrl': null});

      await updateEventMirror('evt-1', imageUrl: 'https://example.com/cover.png');

      final data = (await db.collection('events').doc('evt-1').get()).data()!;
      expect(data['imageUrl'], 'https://example.com/cover.png');
      expect(data['title'], 'Meetup');
    });
  });

  group('removeAttendee', () {
    // Mirrors EventProvider.removeAttendee.
    Future<void> removeAttendeeMirror(String eventId, String uid) async {
      await db.collection('events').doc(eventId).collection('rsvps').doc(uid).delete();
      await db.collection('events').doc(eventId).update({
        'rsvpList': FieldValue.arrayRemove([uid]),
        'rsvpCount': FieldValue.increment(-1),
      });
    }

    test('deletes the rsvps/{uid} subdocument', () async {
      await db.collection('events').doc('evt-1').set({
        'rsvpList': ['user-1'],
        'rsvpCount': 1,
      });
      await db
          .collection('events')
          .doc('evt-1')
          .collection('rsvps')
          .doc('user-1')
          .set({'status': 'approved'});

      await removeAttendeeMirror('evt-1', 'user-1');

      final rsvpDoc = await db
          .collection('events')
          .doc('evt-1')
          .collection('rsvps')
          .doc('user-1')
          .get();
      expect(rsvpDoc.exists, false);
    });

    test('removes uid from rsvpList via arrayRemove and decrements rsvpCount',
        () async {
      await db.collection('events').doc('evt-1').set({
        'rsvpList': ['user-1', 'user-2'],
        'rsvpCount': 2,
      });
      await db
          .collection('events')
          .doc('evt-1')
          .collection('rsvps')
          .doc('user-1')
          .set({'status': 'approved'});

      await removeAttendeeMirror('evt-1', 'user-1');

      final data = (await db.collection('events').doc('evt-1').get()).data()!;
      expect(data['rsvpList'], ['user-2']);
      expect(data['rsvpCount'], 1);
    });

    test('performs both writes (subdoc delete + parent update)', () async {
      await db.collection('events').doc('evt-1').set({
        'rsvpList': ['user-1'],
        'rsvpCount': 1,
      });
      await db
          .collection('events')
          .doc('evt-1')
          .collection('rsvps')
          .doc('user-1')
          .set({'status': 'pending'});

      await removeAttendeeMirror('evt-1', 'user-1');

      final rsvpSnap = await db.collection('events').doc('evt-1').collection('rsvps').get();
      final eventData = (await db.collection('events').doc('evt-1').get()).data()!;
      expect(rsvpSnap.docs, isEmpty);
      expect(eventData['rsvpCount'], 0);
    });
  });

  group('addEvent', () {
    // Mirrors EventProvider.addEvent (M-5: now awaited so a rules rejection
    // or offline failure propagates to the caller instead of being silently
    // dropped after the UI already reported success).
    Future<void> addEventMirror(Map<String, dynamic> data) async {
      await db.collection('events').doc().set(data);
    }

    test('writes a new doc to the events collection', () async {
      await addEventMirror({'title': 'Layover meetup', 'createdBy': 'biz-1'});

      final snap = await db.collection('events').get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.first.data()['title'], 'Layover meetup');
    });

    test('M-7: a cover imageUrl set on the model round-trips into the doc', () async {
      await addEventMirror({
        'title': 'Layover meetup', 'createdBy': 'biz-1',
        'imageUrl': 'https://example.com/cover.png',
      });

      final snap = await db.collection('events').get();
      expect(snap.docs.first.data()['imageUrl'], 'https://example.com/cover.png');
    });
  });
}
