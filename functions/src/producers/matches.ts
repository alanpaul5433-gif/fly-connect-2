import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { createNotificationIdempotent } from '../lib/firestore';
import { isBlocked } from '../lib/blocked';

/**
 * Fires only on a genuine `pending` → `matched` transition — `firestore.rules`
 * now also restricts that transition to the non-initiator (`userB`), so a
 * one-way pending like or a `passed` write never reaches this producer at
 * all (no admirer reveal). One notification doc per participant, both keyed
 * by `matchId` so a retried trigger invocation (or the same transition
 * re-observed) is idempotent per recipient.
 */
export const onMatchUpdated = onDocumentUpdated('matches/{matchId}', async (event) => {
  const { matchId } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.status !== 'pending' || after.status !== 'matched') return;

  const userA = after.userA as string | undefined;
  const userB = after.userB as string | undefined;
  if (!userA || !userB) return;

  if (await isBlocked(userA, userB)) return;

  const recipients: Array<{ recipient: string; other: string }> = [
    { recipient: userA, other: userB },
    { recipient: userB, other: userA },
  ];

  await Promise.all(
    recipients.map(({ recipient, other }) =>
      createNotificationIdempotent(`match_${matchId}_${recipient}`, {
        userId: recipient,
        type: 'match',
        title: "It's a match!",
        body: 'You have a new match',
        deepLink: '/match',
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
        actorId: other,
      }),
    ),
  );
});
