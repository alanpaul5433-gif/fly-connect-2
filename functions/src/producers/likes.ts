import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { db, createNotificationIdempotent, actorName } from '../lib/firestore';
import { isBlocked } from '../lib/blocked';

/**
 * Stage 2 never sends a push for `type == 'like'` (highest-frequency,
 * lowest-signal action) — this producer still writes the in-app
 * notification doc, since the bell-icon list is meant to show it.
 */
export const onPostLikeCreated = onDocumentCreated(
  'posts/{postId}/likes/{likerUid}',
  async (event) => {
    const { postId, likerUid } = event.params;

    const post = await db.collection('posts').doc(postId).get();
    if (!post.exists) return;
    const authorId = post.data()?.authorId as string | undefined;
    if (!authorId) return;

    if (likerUid === authorId) return; // self-notify guard
    if (await isBlocked(likerUid, authorId)) return;

    const name = await actorName(likerUid);
    const notificationId = `like_${postId}_${likerUid}`;

    await createNotificationIdempotent(notificationId, {
      userId: authorId,
      type: 'like',
      title: 'New like',
      body: name ? `${name} liked your post` : 'Someone liked your post',
      deepLink: `/posts/${postId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: likerUid,
      postId,
    });
  },
);
