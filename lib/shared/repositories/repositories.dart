import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../utils/image_compress.dart';

// ─── Post Repository ─────────────────────────────────────────
class PostRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String get _uid => _auth.currentUser!.uid;

  Stream<List<PostModel>> watchFeed() {
    return _db.collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => PostModel.fromFirestore(d)).toList());
  }

  Stream<List<PostModel>> watchUserPosts(String uid) {
    return _db.collection('posts')
        .where('authorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PostModel.fromFirestore(d)).toList());
  }

  Future<PostModel?> getPost(String postId) async {
    final doc = await _db.collection('posts').doc(postId).get();
    if (!doc.exists) return null;
    return PostModel.fromFirestore(doc);
  }

  Future<String?> uploadPostMedia(Uint8List bytes, String type) async {
    final compressed = await compressForUpload(bytes);
    final id = const Uuid().v4();
    final ref = _storage.ref('posts/$_uid/$id.png');
    await ref.putData(compressed,
        SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }

  Future<void> createPost({
    required String caption,
    required String authorName,
    String? authorPhotoUrl,
    List<String> mediaUrls = const [],
    String mediaType = 'text',
    String? location,
    String? groupId,
  }) async {
    final ref = _db.collection('posts').doc();
    final post = PostModel(
      id: ref.id, authorId: _uid, authorName: authorName,
      authorPhotoUrl: authorPhotoUrl, mediaUrls: mediaUrls,
      mediaType: mediaType, caption: caption, location: location,
      groupId: groupId, createdAt: DateTime.now(),
    );
    await ref.set(post.toFirestore());
    await _db.collection('users').doc(_uid).update({
      'postCount': FieldValue.increment(1),
    });
  }

  Future<void> toggleLike(String postId) async {
    final likeRef = _db.collection('posts').doc(postId)
        .collection('likes').doc(_uid);
    final likeDoc = await likeRef.get();
    if (likeDoc.exists) {
      await likeRef.delete();
      await _db.collection('posts').doc(postId).update({
        'likeCount': FieldValue.increment(-1),
      });
    } else {
      await likeRef.set({'likedAt': Timestamp.now()});
      await _db.collection('posts').doc(postId).update({
        'likeCount': FieldValue.increment(1),
      });
    }
  }

  Future<bool> isLiked(String postId) async {
    final doc = await _db.collection('posts').doc(postId)
        .collection('likes').doc(_uid).get();
    return doc.exists;
  }

  Future<void> addComment({
    required String postId,
    required String text,
    required String authorName,
    String? authorPhotoUrl,
  }) async {
    final ref = _db.collection('posts').doc(postId).collection('comments').doc();
    final comment = CommentModel(
      id: ref.id, postId: postId, authorId: _uid, authorName: authorName,
      authorPhotoUrl: authorPhotoUrl, text: text, createdAt: DateTime.now(),
    );
    await ref.set(comment.toFirestore());
    await _db.collection('posts').doc(postId).update({
      'commentCount': FieldValue.increment(1),
    });
  }

  Stream<List<CommentModel>> watchComments(String postId) {
    return _db.collection('posts').doc(postId).collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map((d) => CommentModel.fromFirestore(d)).toList());
  }

  Future<void> reportPost(String postId) async {
    await _db.collection('posts').doc(postId).update({
      'reportCount': FieldValue.increment(1),
      'isReported': true,
    });
  }

  Future<void> deletePost(String postId) async {
    await _db.collection('posts').doc(postId).delete();
    await _db.collection('users').doc(_uid).update({
      'postCount': FieldValue.increment(-1),
    });
  }
}

// ─── Chat Repository ─────────────────────────────────────────

class EventRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String get _uid => _auth.currentUser!.uid;

  Stream<List<EventModel>> watchEvents() {
    return _db.collection('events')
        .where('isApproved', isEqualTo: true)
        .orderBy('date')
        .snapshots()
        .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());
  }

  Future<EventModel?> getEvent(String eventId) async {
    final doc = await _db.collection('events').doc(eventId).get();
    if (!doc.exists) return null;
    return EventModel.fromFirestore(doc);
  }

  Future<void> createEvent(EventModel event) async {
    final ref = _db.collection('events').doc();
    await ref.set({...event.toFirestore(), 'id': ref.id});
  }

  Future<void> rsvpEvent(String eventId) async {
    final rsvpRef = _db.collection('events').doc(eventId)
        .collection('rsvps').doc(_uid);
    final doc = await rsvpRef.get();
    if (doc.exists) {
      await rsvpRef.delete();
      await _db.collection('events').doc(eventId).update({
        'rsvpList': FieldValue.arrayRemove([_uid]),
        'rsvpCount': FieldValue.increment(-1),
      });
    } else {
      await rsvpRef.set({'rsvpAt': Timestamp.now()});
      await _db.collection('events').doc(eventId).update({
        'rsvpList': FieldValue.arrayUnion([_uid]),
        'rsvpCount': FieldValue.increment(1),
      });
    }
  }

  Future<bool> hasRsvped(String eventId) async {
    final doc = await _db.collection('events').doc(eventId)
        .collection('rsvps').doc(_uid).get();
    return doc.exists;
  }
}

// ─── Group Repository ────────────────────────────────────────

class NotificationRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<NotificationModel>> watchNotifications(String uid) =>
      _db.collection('notifications')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) => s.docs.map((d) => NotificationModel.fromFirestore(d)).toList());

  Future<void> markRead(String id) =>
      _db.collection('notifications').doc(id).update({'isRead': true});

  Future<void> markAllRead(String uid) async {
    final snap = await _db.collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}

// ─── Match Repository ─────────────────────────────────────────
class MatchRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<UserModel>> getCandidates(String uid) async {
    final snap = await _db.collection('users')
        .where('role', isEqualTo: 'user')
        .limit(20)
        .get();
    return snap.docs
        .map(UserModel.fromFirestore)
        .where((u) => u.uid != uid)
        .toList();
  }

  Stream<List<MatchModel>> watchMatches(String uid) =>
      _db.collection('matches')
          .where('userA', isEqualTo: uid)
          .where('status', isEqualTo: 'matched')
          .snapshots()
          .map((s) => s.docs.map(MatchModel.fromFirestore).toList());

  Future<void> likeUser(String uid, String targetUid, String matchType) async {
    final existingSnap = await _db.collection('matches')
        .where('userA', isEqualTo: targetUid)
        .where('userB', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .get();
    if (existingSnap.docs.isNotEmpty) {
      await existingSnap.docs.first.reference.update({'status': 'matched', 'matchedAt': FieldValue.serverTimestamp()});
    } else {
      await _db.collection('matches').add({
        'userA': uid, 'userB': targetUid, 'status': 'pending',
        'matchType': matchType, 'likedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> passUser(String uid, String targetUid) async {
    await _db.collection('matches').add({
      'userA': uid, 'userB': targetUid, 'status': 'passed',
      'matchType': 'none', 'likedAt': FieldValue.serverTimestamp(),
    });
  }
}

// ─── Trip Repository ──────────────────────────────────────────
class TripRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<TripModel>> watchTrips(String uid) =>
      _db.collection('trips')
          .where('userId', isEqualTo: uid)
          .orderBy('startDate', descending: true)
          .snapshots()
          .map((s) => s.docs.map(TripModel.fromFirestore).toList());

  Future<void> addTrip(TripModel trip) =>
      _db.collection('trips').doc(trip.id).set(trip.toFirestore());

  Future<void> deleteTrip(String id) =>
      _db.collection('trips').doc(id).delete();
}

// ─── Group Repository ─────────────────────────────────────────
class GroupRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<GroupModel>> watchGroups() =>
      _db.collection('groups')
          .orderBy('memberCount', descending: true)
          .limit(30)
          .snapshots()
          .map((s) => s.docs.map(GroupModel.fromFirestore).toList());

  Stream<List<GroupModel>> watchMyGroups(String uid) =>
      _db.collection('groups')
          .where('members', arrayContains: uid)
          .snapshots()
          .map((s) => s.docs.map(GroupModel.fromFirestore).toList());

  Future<void> joinGroup(String groupId, String uid) async {
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([uid]),
      'memberCount': FieldValue.increment(1),
    });
  }

  Future<void> leaveGroup(String groupId, String uid) async {
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([uid]),
      'memberCount': FieldValue.increment(-1),
    });
  }

  Future<List<GroupModel>> searchGroups(String query) async {
    final snap = await _db.collection('groups')
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(10)
        .get();
    return snap.docs.map(GroupModel.fromFirestore).toList();
  }
}

// ─── Event Repository extension ───────────────────────────────
extension EventSearchExt on EventRepository {
  Future<List<EventModel>> searchEvents(String query) async {
    final db = FirebaseFirestore.instance;
    final snap = await db.collection('events')
        .where('title', isGreaterThanOrEqualTo: query)
        .where('title', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(10)
        .get();
    return snap.docs.map(EventModel.fromFirestore).toList();
  }
}

// ─── Chat Repository ──────────────────────────────────────────
class ChatRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<ChatModel>> watchChats(String uid) =>
      _db.collection('chats')
          .where('participants', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ChatModel.fromFirestore).toList());

  Stream<List<MessageModel>> watchMessages(String chatId) =>
      _db.collection('chats').doc(chatId).collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((s) => s.docs.map(MessageModel.fromFirestore).toList());

  Future<void> sendMessage(String chatId, String text, {String? mediaUrl, String mediaType = 'text'}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final msgRef = _db.collection('chats').doc(chatId).collection('messages').doc();
    final batch = _db.batch();
    batch.set(msgRef, {
      'senderId': user.uid, 'senderName': user.displayName ?? 'User',
      'senderPhotoUrl': user.photoURL, 'text': text,
      'mediaUrl': mediaUrl, 'mediaType': mediaType,
      'readBy': [user.uid], 'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('chats').doc(chatId), {
      'lastMessage': text, 'lastMessageSenderId': user.uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> markAsRead(String chatId, String uid) =>
      _db.collection('chats').doc(chatId).update({'unreadCount.$uid': 0});

  Future<String> getOrCreateDm(String uid, String otherUid) async {
    final snap = await _db.collection('chats')
        .where('type', isEqualTo: 'dm')
        .where('participants', arrayContains: uid)
        .get();
    for (final doc in snap.docs) {
      final chat = ChatModel.fromFirestore(doc);
      if (chat.participants.contains(otherUid)) return doc.id;
    }
    final docs = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('users').doc(otherUid).get(),
    ]);
    final ref = _db.collection('chats').doc();
    await ref.set({
      'type': 'dm', 'participants': [uid, otherUid],
      'participantNames': ChatModel.namesMap(
        meUid: uid, meName: docs[0].data()?['name'] as String?,
        otherUid: otherUid, otherName: docs[1].data()?['name'] as String?),
      'createdBy': uid, 'unreadCount': {}, 'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setTyping(String chatId, String uid, bool isTyping) =>
      _db.collection('chats').doc(chatId).collection('typing').doc(uid)
          .set({'isTyping': isTyping, 'at': FieldValue.serverTimestamp()});

  Stream<Map<String, bool>> watchTyping(String chatId) =>
      _db.collection('chats').doc(chatId).collection('typing')
          .snapshots()
          .map((s) => Map.fromEntries(
              s.docs.map((d) => MapEntry(d.id, d.data()['isTyping'] as bool? ?? false))));
}
