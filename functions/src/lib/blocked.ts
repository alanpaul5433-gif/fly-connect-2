import { db } from './firestore';

/**
 * Checks both directions of the block relationship — a blocked user's
 * continued activity must not resurface as a push to whoever blocked them,
 * regardless of which of the two blocked the other.
 */
export async function isBlocked(actorId: string, recipientId: string): Promise<boolean> {
  const [recipientBlockedActor, actorBlockedRecipient] = await Promise.all([
    db.collection('users').doc(recipientId).collection('blocked').doc(actorId).get(),
    db.collection('users').doc(actorId).collection('blocked').doc(recipientId).get(),
  ]);
  return recipientBlockedActor.exists || actorBlockedRecipient.exists;
}
