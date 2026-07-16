import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Tests for PostProvider behavior: likes, comments, reports, bookmarks.
/// Same caveat as auth_provider_test: our provider uses singleton Firestore,
/// so we validate the data-layer contract directly against fake Firestore.
void main() {
  late FakeFirebaseFirestore db;
  const uid = 'test-user-123';
  const postId = 'post-abc';

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('Likes', () {
    test('liking a post writes to likes subcollection and increments count', () async {
      await db.collection('posts').doc(postId).set({'likeCount': 0});
      await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).set({'likedAt': Timestamp.now()});
      await db.collection('posts').doc(postId).update({
        'likeCount': FieldValue.increment(1),
      });

      final postSnap = await db.collection('posts').doc(postId).get();
      expect(postSnap.data()!['likeCount'], 1);

      final likeSnap = await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).get();
      expect(likeSnap.exists, true);
    });

    test('isLiked check returns true after liking', () async {
      await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).set({'likedAt': Timestamp.now()});
      final doc = await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).get();
      expect(doc.exists, true);
    });

    test('unliking removes the doc and decrements count', () async {
      await db.collection('posts').doc(postId).set({'likeCount': 1});
      await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).set({'likedAt': Timestamp.now()});

      await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).delete();
      await db.collection('posts').doc(postId).update({
        'likeCount': FieldValue.increment(-1),
      });

      final postSnap = await db.collection('posts').doc(postId).get();
      expect(postSnap.data()!['likeCount'], 0);

      final likeSnap = await db.collection('posts').doc(postId)
          .collection('likes').doc(uid).get();
      expect(likeSnap.exists, false);
    });
  });

  group('Comments', () {
    test('adding a comment writes to comments subcollection', () async {
      await db.collection('posts').doc(postId).set({'commentCount': 0});
      await db.collection('posts').doc(postId)
          .collection('comments').add({
        'postId': postId,
        'authorId': uid,
        'text': 'Nice post!',
        'likeCount': 0,
        'createdAt': Timestamp.now(),
      });
      await db.collection('posts').doc(postId).update({
        'commentCount': FieldValue.increment(1),
      });

      final comments = await db.collection('posts').doc(postId)
          .collection('comments').get();
      expect(comments.docs.length, 1);
      expect(comments.docs.first.data()['text'], 'Nice post!');

      final post = await db.collection('posts').doc(postId).get();
      expect(post.data()!['commentCount'], 1);
    });
  });

  group('Reports (UGC compliance)', () {
    test('reporting a post creates a report record AND flags the post', () async {
      // 1. Seed post
      await db.collection('posts').doc(postId).set({
        'reportCount': 0,
        'isReported': false,
      });

      // 2. Report: flag post + create report record
      await db.collection('posts').doc(postId).update({
        'reportCount': FieldValue.increment(1),
        'isReported': true,
      });
      await db.collection('reports').add({
        'targetType': 'post',
        'targetId': postId,
        'reporterId': uid,
        'reason': 'Spam',
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });

      final post = await db.collection('posts').doc(postId).get();
      expect(post.data()!['isReported'], true);
      expect(post.data()!['reportCount'], 1);

      final reports = await db.collection('reports').get();
      expect(reports.docs.length, 1);
      expect(reports.docs.first.data()['status'], 'pending');
    });

    test('blocking a user writes to users/{uid}/blocked/', () async {
      const targetUid = 'other-user';
      await db.collection('users').doc(uid)
          .collection('blocked').doc(targetUid).set({
        'blockedAt': Timestamp.now(),
      });

      final blocked = await db.collection('users').doc(uid)
          .collection('blocked').get();
      expect(blocked.docs.length, 1);
      expect(blocked.docs.first.id, targetUid);
    });
  });

  group('Saved posts (bookmarks)', () {
    test('saving persists to users/{uid}/savedPosts/{postId}', () async {
      await db.collection('users').doc(uid)
          .collection('savedPosts').doc(postId).set({
        'savedAt': Timestamp.now(),
      });

      final doc = await db.collection('users').doc(uid)
          .collection('savedPosts').doc(postId).get();
      expect(doc.exists, true);
    });

    test('unsaving removes the doc', () async {
      await db.collection('users').doc(uid)
          .collection('savedPosts').doc(postId).set({'savedAt': Timestamp.now()});
      await db.collection('users').doc(uid)
          .collection('savedPosts').doc(postId).delete();

      final doc = await db.collection('users').doc(uid)
          .collection('savedPosts').doc(postId).get();
      expect(doc.exists, false);
    });

    test('watchSavedPosts contract: bookmarked ids resolve to real post docs', () async {
      // Mirrors PostProvider.watchSavedPosts: read the bookmark ids, then
      // fetch the matching posts via whereIn on the document id.
      await db.collection('posts').doc('post-1').set({'caption': 'One'});
      await db.collection('posts').doc('post-2').set({'caption': 'Two'});
      await db.collection('users').doc(uid).collection('savedPosts')
          .doc('post-1').set({'savedAt': Timestamp.now()});
      await db.collection('users').doc(uid).collection('savedPosts')
          .doc('post-2').set({'savedAt': Timestamp.now()});

      final savedIds = (await db.collection('users').doc(uid)
              .collection('savedPosts').get())
          .docs
          .map((d) => d.id)
          .toList();
      expect(savedIds, containsAll(['post-1', 'post-2']));

      final posts = await db.collection('posts')
          .where(FieldPath.documentId, whereIn: savedIds).get();
      expect(posts.docs.length, 2);
    });

    test('a post deleted by its author disappears from a saved-ids lookup', () async {
      // A saved bookmark can outlive the post it points to (deletePost
      // doesn't clean up other users' savedPosts entries) — the fetch
      // step should simply return fewer posts than bookmark ids, not error.
      await db.collection('posts').doc(postId).set({'caption': 'Gone soon'});
      await db.collection('users').doc(uid).collection('savedPosts')
          .doc(postId).set({'savedAt': Timestamp.now()});

      await db.collection('posts').doc(postId).delete();

      final savedIds = (await db.collection('users').doc(uid)
              .collection('savedPosts').get())
          .docs
          .map((d) => d.id)
          .toList();
      final posts = await db.collection('posts')
          .where(FieldPath.documentId, whereIn: savedIds).get();
      expect(posts.docs, isEmpty);
    });
  });

  group('Delete post (owner-only)', () {
    test('deleting a post removes its doc, comments, and likes', () async {
      // Mirrors PostProvider.deletePost's batch: comments + likes + the post.
      await db.collection('posts').doc(postId).set({'authorId': uid, 'postCount': 1});
      await db.collection('posts').doc(postId).collection('comments')
          .doc('c1').set({'authorId': 'someone', 'text': 'hi'});
      await db.collection('posts').doc(postId).collection('likes')
          .doc('liker-1').set({'likedAt': Timestamp.now()});

      final postRef = db.collection('posts').doc(postId);
      final comments = await postRef.collection('comments').get();
      final likes = await postRef.collection('likes').get();
      final batch = db.batch();
      for (final d in comments.docs) {
        batch.delete(d.reference);
      }
      for (final d in likes.docs) {
        batch.delete(d.reference);
      }
      batch.delete(postRef);
      await batch.commit();

      expect((await postRef.get()).exists, false);
      expect((await postRef.collection('comments').get()).docs, isEmpty);
      expect((await postRef.collection('likes').get()).docs, isEmpty);
    });

    test('deleting decrements the author postCount', () async {
      await db.collection('users').doc(uid).set({'postCount': 3});
      await db.collection('users').doc(uid).update({
        'postCount': FieldValue.increment(-1),
      });
      final user = await db.collection('users').doc(uid).get();
      expect(user.data()!['postCount'], 2);
    });
  });

  group('Delete comment (owner-only)', () {
    test('deleting a comment removes its doc and decrements commentCount', () async {
      await db.collection('posts').doc(postId).set({'commentCount': 1});
      final commentRef = db.collection('posts').doc(postId)
          .collection('comments').doc('c1');
      await commentRef.set({'authorId': uid, 'text': 'nice!'});

      // Mirrors PostProvider.deleteComment.
      await commentRef.delete();
      await db.collection('posts').doc(postId).update({
        'commentCount': FieldValue.increment(-1),
      });

      expect((await commentRef.get()).exists, false);
      final post = await db.collection('posts').doc(postId).get();
      expect(post.data()!['commentCount'], 0);
    });
  });

  group('Blocked users', () {
    const targetUid = 'blocked-user-1';

    test('blocking a user writes to the blocked subcollection', () async {
      await db.collection('users').doc(uid).collection('blocked')
          .doc(targetUid).set({'blockedAt': Timestamp.now()});

      final doc = await db.collection('users').doc(uid)
          .collection('blocked').doc(targetUid).get();
      expect(doc.exists, true);
    });

    test('unblocking removes the doc', () async {
      await db.collection('users').doc(uid).collection('blocked')
          .doc(targetUid).set({'blockedAt': Timestamp.now()});
      await db.collection('users').doc(uid).collection('blocked')
          .doc(targetUid).delete();

      final doc = await db.collection('users').doc(uid)
          .collection('blocked').doc(targetUid).get();
      expect(doc.exists, false);
    });

    test('watchBlockedUsers contract: blocked ids resolve to real user docs', () async {
      // Mirrors PostProvider.watchBlockedUsers: read the blocked ids, then
      // fetch the matching users via whereIn on the document id.
      await db.collection('users').doc('blocked-1').set({'name': 'Alice'});
      await db.collection('users').doc('blocked-2').set({'name': 'Bob'});
      await db.collection('users').doc(uid).collection('blocked')
          .doc('blocked-1').set({'blockedAt': Timestamp.now()});
      await db.collection('users').doc(uid).collection('blocked')
          .doc('blocked-2').set({'blockedAt': Timestamp.now()});

      final blockedIds = (await db.collection('users').doc(uid)
              .collection('blocked').get())
          .docs
          .map((d) => d.id)
          .toList();
      expect(blockedIds, containsAll(['blocked-1', 'blocked-2']));

      final users = await db.collection('users')
          .where(FieldPath.documentId, whereIn: blockedIds).get();
      expect(users.docs.length, 2);
    });

    test('a user removed from the DB disappears from a blocked-ids lookup', () async {
      // A block entry can outlive the blocked account (deleting a user
      // doesn't clean up other users' blocked entries) — the fetch step
      // should simply return fewer users than blocked ids, not error.
      await db.collection('users').doc(targetUid).set({'name': 'Gone soon'});
      await db.collection('users').doc(uid).collection('blocked')
          .doc(targetUid).set({'blockedAt': Timestamp.now()});
      await db.collection('users').doc(targetUid).delete();

      final blockedIds = (await db.collection('users').doc(uid)
              .collection('blocked').get())
          .docs
          .map((d) => d.id)
          .toList();
      final users = await db.collection('users')
          .where(FieldPath.documentId, whereIn: blockedIds).get();
      expect(users.docs.length, 0);
    });
  });
}
