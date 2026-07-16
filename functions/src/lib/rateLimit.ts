import { FieldValue } from 'firebase-admin/firestore';
import type { Timestamp } from 'firebase-admin/firestore';
import { db } from './firestore';

/**
 * A business publishing several promotions/events/groups in a short window
 * shouldn't fan out a push to every follower each time — this throttles the
 * follower fan-out per business per content type. The content itself still
 * becomes visible normally; this only gates the notification side-effect.
 */
export async function shouldFanOut(
  businessId: string,
  type: string,
  cooldownMs: number,
): Promise<boolean> {
  const ref = db.collection('notificationRateLimits').doc(`${businessId}_${type}`);
  const snap = await ref.get();
  const lastSentAt = snap.data()?.lastSentAt as Timestamp | undefined;

  if (lastSentAt && Date.now() - lastSentAt.toMillis() < cooldownMs) {
    return false;
  }

  await ref.set({ lastSentAt: FieldValue.serverTimestamp() });
  return true;
}
