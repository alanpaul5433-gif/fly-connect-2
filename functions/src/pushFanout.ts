import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as logger from 'firebase-functions/logger';
import { getFcmToken, getUserSettings, sendPush } from './lib/fcm';

/**
 * Push notification payloads render on the lock screen with weaker access
 * control than an authenticated Firestore read — a colleague's name in a
 * "You matched with X" banner, or a message preview, both visible to anyone
 * glancing at the device. `match` and `message` get a generic push
 * title/body instead of the doc's real content; the in-app notification
 * list (the Firestore doc itself) is unchanged and still shows the real text.
 */
const GENERIC_PUSH_BODY: Record<string, string> = {
  match: 'You have a new match',
  message: 'New message',
};

/**
 * H16: the six push toggles in Settings were written to `users/{uid}.settings`
 * and read by nobody — turning off "Messages" changed nothing. This maps a
 * notification `type` to its settings key so the fan-out can honour it.
 *
 * Types with no user-facing switch (follow, group, promotion, admin) return
 * null and are always allowed.
 */
export function pushSettingKeyForType(type: string): string | null {
  switch (type) {
    case 'like': return 'pushLikes';
    case 'comment': return 'pushComments';
    case 'match': return 'pushMatches';
    case 'message': return 'pushMessages';
    case 'event': return 'pushEvents';
    case 'admin_safecheck': return 'pushSafeCheck';
    default: return null;
  }
}

/** Whether a push of [type] is allowed given the user's settings. A toggle is
 * respected only when explicitly `false`; missing/true defaults to on. */
export function isPushAllowed(type: string, settings: Record<string, unknown>): boolean {
  const key = pushSettingKeyForType(type);
  if (key === null) return true;
  return settings[key] !== false;
}

/**
 * Fully-specified in-app `type` → FCM `data.type` lookup table. Not an
 * "etc." — the previous design draft only covered 3 of 8 needed rows, which
 * was a major review finding. `admin` intentionally sends no `data.type`
 * (falls through to `AppRoutes.notifications` on tap, matching today's
 * admin-broadcast intent); `like` never reaches here (see step 1 below).
 */
function buildDataPayload(doc: FirebaseFirestore.DocumentData): Record<string, string> {
  const str = (v: unknown): string => (typeof v === 'string' ? v : '');

  switch (doc.type as string) {
    case 'comment':
      return { type: 'post_comment', postId: str(doc.postId) };
    case 'follow':
      // Rename: the doc's own `userId` is the *recipient*, never the
      // follower — the outgoing payload's `userId` must be `actorId`.
      return { type: 'follow_request', userId: str(doc.actorId) };
    case 'match':
      return { type: 'match' };
    case 'event':
      return { type: 'event', eventId: str(doc.eventId) };
    case 'group':
      return { type: 'group', groupId: str(doc.groupId) };
    case 'promotion':
      return { type: 'new_promotion', promotionId: str(doc.promotionId) };
    case 'message':
      return { type: 'message', chatId: str(doc.chatId) };
    case 'admin_safecheck':
      return { type: 'safe_check' };
    case 'admin':
    default:
      return {};
  }
}

/**
 * Shared fan-out for every `notifications/{id}` doc — including the two
 * existing admin writers (`admin_notifications_page.dart`,
 * `admin_safecheck_page.dart`), which start sending real push automatically
 * with no changes to either admin screen's write logic.
 *
 * `maxInstances: 20` is an explicit, non-infinite ceiling (v2 defaults to
 * effectively unbounded auto-scaling) so a large admin broadcast queues
 * through 20 concurrent invocations instead of an unbounded cost/concurrency
 * spike.
 */
export const onNotificationCreated = onDocumentCreated(
  { document: 'notifications/{id}', maxInstances: 20 },
  async (event) => {
    const doc = event.data?.data();
    if (!doc) return;

    // Likes are the highest-frequency, lowest-signal action in the app —
    // the in-app doc (already written by Stage 1) is sufficient, no push.
    if (doc.type === 'like') return;

    const userId = doc.userId as string | undefined;
    if (!userId) return;

    // H16: honour the recipient's push preference for this notification type.
    const settings = await getUserSettings(userId);
    if (!isPushAllowed(doc.type as string, settings)) {
      logger.info(`push type ${doc.type} disabled by ${userId} — skipping ${event.params.id}`);
      return;
    }

    const token = await getFcmToken(userId);
    if (!token) {
      logger.info(`no fcmToken for ${userId} — skipping push for notification ${event.params.id}`);
      return;
    }

    const generic = GENERIC_PUSH_BODY[doc.type as string];
    const title = generic ?? (doc.title as string | undefined) ?? 'FlyConnect';
    const body = generic ?? (doc.body as string | undefined) ?? '';

    await sendPush(token, { title, body, data: buildDataPayload(doc) });
  },
);
