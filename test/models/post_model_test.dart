import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression coverage for M-7 post edit: a post gains an `editedAt`
/// timestamp only once it's been edited, and it round-trips through
/// Firestore as a proper DateTime (not left as a raw Timestamp).
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  PostModel buildPost({DateTime? editedAt}) => PostModel(
        id: 'p1',
        authorId: 'u1',
        authorName: 'Alex',
        caption: 'hello',
        createdAt: DateTime(2026, 1, 1),
        editedAt: editedAt,
      );

  group('PostModel.editedAt round-trip', () {
    test('a never-edited post round-trips with editedAt null', () async {
      final post = buildPost();
      await db.collection('posts').doc('p1').set(post.toFirestore());

      final snap = await db.collection('posts').doc('p1').get();
      final parsed = PostModel.fromFirestore(snap);

      expect(parsed.editedAt, isNull);
    });

    test('an edited post round-trips editedAt as a DateTime', () async {
      final post = buildPost(editedAt: DateTime(2026, 7, 16, 12, 0));
      await db.collection('posts').doc('p1').set(post.toFirestore());

      final snap = await db.collection('posts').doc('p1').get();
      final parsed = PostModel.fromFirestore(snap);

      expect(parsed.editedAt, DateTime(2026, 7, 16, 12, 0));
    });
  });
}
