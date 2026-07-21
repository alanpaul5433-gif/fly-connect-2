import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { db, createNotificationIdempotent, actorName } from '../lib/firestore';
import { isBlocked } from '../lib/blocked';

export const onPostCommentCreated = onDocumentCreated(
  'posts/{postId}/comments/{commentId}',
  async (event) => {
    const { postId, commentId } = event.params;
    const comment = event.data?.data();
    if (!comment) return;
    const commenterId = comment.authorId as string | undefined;
    if (!commenterId) return;

    const post = await db.collection('posts').doc(postId).get();
    if (!post.exists) return;
    const authorId = post.data()?.authorId as string | undefined;
    if (!authorId) return;

    if (commenterId === authorId) return; // self-notify guard
    if (await isBlocked(commenterId, authorId)) return;

    const name = await actorName(commenterId);
    const notificationId = `comment_${commentId}`;

    await createNotificationIdempotent(notificationId, {
      userId: authorId,
      type: 'comment',
      title: 'New comment',
      body: name ? `${name} commented on your post` : 'Someone commented on your post',
      deepLink: `/posts/${postId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: commenterId,
      postId,
    });
  },
);
