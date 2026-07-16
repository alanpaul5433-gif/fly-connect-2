import { getMessaging } from 'firebase-admin/messaging';
import * as logger from 'firebase-functions/logger';
import { db } from './firestore';

/**
 * The FCM token lives in `users/{userId}/private/data.fcmToken` (moved there
 * as PII alongside the rest of H-2's work) — NOT `users/{userId}.fcmToken`,
 * a stale flat field the Dart `UserModel` still carries for backward
 * compatibility but `notification_service.dart` no longer writes to.
 * Reading the wrong path means every push silently no-ops.
 */
export async function getFcmToken(userId: string): Promise<string | null> {
  const snap = await db.collection('users').doc(userId).collection('private').doc('data').get();
  const token = snap.data()?.fcmToken;
  return typeof token === 'string' && token.trim() ? token : null;
}

/** Sends one push; catches and logs send failures (invalid/expired token, etc.) rather than throwing. */
export async function sendPush(
  token: string,
  payload: { title: string; body: string; data: Record<string, string> },
): Promise<void> {
  try {
    await getMessaging().send({
      token,
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
    });
  } catch (err) {
    logger.warn(`push send failed for token ${token.slice(0, 12)}…`, err);
  }
}
