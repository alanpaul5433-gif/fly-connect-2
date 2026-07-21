import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';

if (getApps().length === 0) {
  initializeApp();
}

export const db = getFirestore();

/**
 * Every producer's Firestore trigger is at-least-once, not exactly-once —
 * writing via `.doc(id).create()` with a deterministic id (see each
 * producer's `notificationId` helper) makes a retried invocation hit
 * ALREADY_EXISTS instead of a duplicate doc. That's expected, not an error.
 */
export async function createNotificationIdempotent(
  id: string,
  data: Record<string, unknown>,
): Promise<void> {
  try {
    await db.collection('notifications').doc(id).create(data);
  } catch (err) {
    const code = (err as { code?: number | string }).code;
    if (code === 6 || code === 'already-exists') {
      logger.info(`notification ${id} already exists — at-least-once retry, no-op`);
      return;
    }
    throw err;
  }
}

/** Best-effort display name for a notification body; never throws. */
export async function actorName(actorId: string): Promise<string | null> {
  try {
    const snap = await db.collection('users').doc(actorId).get();
    if (!snap.exists) return null;
    const name = snap.data()?.name;
    return typeof name === 'string' && name.trim() ? name : null;
  } catch (err) {
    logger.warn(`actorName lookup failed for ${actorId}`, err);
    return null;
  }
}
