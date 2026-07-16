import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { createNotificationIdempotent, actorName } from '../lib/firestore';
import { isBlocked } from '../lib/blocked';

/**
 * `firestore.rules` now also enforces `followerId != targetUid` and writer
 * ownership on `users/{targetUid}/followers/{followerId}` (see the C-3
 * design's "Rules changes") — this guard is defense-in-depth, not the only
 * line of defense.
 */
export const onFollowerCreated = onDocumentCreated(
  'users/{targetUid}/followers/{followerId}',
  async (event) => {
    const { targetUid, followerId } = event.params;

    if (followerId === targetUid) return; // self-notify guard (rules also enforce this)
    if (await isBlocked(followerId, targetUid)) return;

    const name = await actorName(followerId);
    const notificationId = `follow_${targetUid}_${followerId}`;

    await createNotificationIdempotent(notificationId, {
      userId: targetUid,
      type: 'follow',
      title: 'New follower',
      body: name ? `${name} started following you` : 'Someone started following you',
      deepLink: `/users/${followerId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: followerId,
    });
  },
);
