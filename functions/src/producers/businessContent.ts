import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { db, createNotificationIdempotent, actorName } from '../lib/firestore';
import { isBlocked } from '../lib/blocked';
import { shouldFanOut } from '../lib/rateLimit';

/**
 * A business posting repeatedly (several deals/events in a day) shouldn't
 * spam followers with a push each time — the content itself is unaffected,
 * only the follower fan-out is throttled per business per content type.
 */
const FANOUT_COOLDOWN_MS = 6 * 60 * 60 * 1000; // 6 hours

/**
 * Hard ceiling on how many followers get fanned out to in one trigger
 * invocation. A business with a very large follower base is a v2 concern
 * (queued/paginated fan-out); for now, cap and log rather than fan out to an
 * unbounded number of recipients in a single invocation.
 */
const MAX_RECIPIENTS = 2000;
const CHUNK_SIZE = 500;

async function fetchFollowerIds(businessId: string): Promise<string[]> {
  const snap = await db.collection('users').doc(businessId).collection('followers').get();
  let ids = snap.docs.map((d) => d.id);
  if (ids.length > MAX_RECIPIENTS) {
    logger.warn(`business ${businessId} has ${ids.length} followers — capping fan-out at ${MAX_RECIPIENTS}`);
    ids = ids.slice(0, MAX_RECIPIENTS);
  }
  return ids;
}

/** Runs `notify` for each recipient, bounding concurrency to CHUNK_SIZE at a time. */
async function fanOutInChunks(
  recipients: string[],
  notify: (recipient: string) => Promise<void>,
): Promise<void> {
  for (let i = 0; i < recipients.length; i += CHUNK_SIZE) {
    const chunk = recipients.slice(i, i + CHUNK_SIZE);
    await Promise.all(chunk.map(notify));
  }
}

/**
 * Fires only on the `isApproved` false -> true transition — matches the
 * moderation-gate fix that made pre-approval promotions/events invisible to
 * ordinary users. Firing on raw create would notify followers about content
 * nobody else can see yet.
 */
export const onPromotionApproved = onDocumentUpdated('promotions/{promoId}', async (event) => {
  const { promoId } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.isApproved === true || after.isApproved !== true) return;

  const businessId = after.businessId as string | undefined;
  if (!businessId) return;

  if (!(await shouldFanOut(businessId, 'promotion', FANOUT_COOLDOWN_MS))) return;

  const recipients = (await fetchFollowerIds(businessId)).filter((id) => id !== businessId);
  if (recipients.length === 0) return;

  const name = (await actorName(businessId)) ?? 'A business you follow';
  const title = (after.title as string | undefined) ?? 'a new deal';

  await fanOutInChunks(recipients, async (recipient) => {
    if (await isBlocked(businessId, recipient)) return;
    await createNotificationIdempotent(`promo_${promoId}_${recipient}`, {
      userId: recipient,
      type: 'promotion',
      title: 'New deal',
      body: `${name} posted ${title}`,
      deepLink: `/promotions/${promoId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: businessId,
      promotionId: promoId,
    });
  });
});

/** Same false -> true `isApproved` transition as promotions, for the same reason. */
export const onEventApproved = onDocumentUpdated('events/{eventId}', async (event) => {
  const { eventId } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.isApproved === true || after.isApproved !== true) return;

  const businessId = after.createdBy as string | undefined;
  if (!businessId) return;

  if (!(await shouldFanOut(businessId, 'event', FANOUT_COOLDOWN_MS))) return;

  const recipients = (await fetchFollowerIds(businessId)).filter((id) => id !== businessId);
  if (recipients.length === 0) return;

  const name = (await actorName(businessId)) ?? 'A business you follow';
  const title = (after.title as string | undefined) ?? 'a new event';

  await fanOutInChunks(recipients, async (recipient) => {
    if (await isBlocked(businessId, recipient)) return;
    await createNotificationIdempotent(`event_new_${eventId}_${recipient}`, {
      userId: recipient,
      type: 'event',
      title: 'New event',
      body: `${name} posted ${title}`,
      deepLink: `/events/${eventId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: businessId,
      eventId,
    });
  });
});

/**
 * Groups have no `isApproved`/moderation concept at all (confirmed: no such
 * field on GroupModel), so this fires on raw create instead of an approval
 * transition. If group moderation is ever added, this needs revisiting the
 * same way promotions/events were.
 */
export const onGroupCreated = onDocumentCreated('groups/{groupId}', async (event) => {
  const { groupId } = event.params;
  const group = event.data?.data();
  if (!group) return;

  const businessId = group.createdBy as string | undefined;
  if (!businessId) return;

  if (!(await shouldFanOut(businessId, 'group', FANOUT_COOLDOWN_MS))) return;

  const recipients = (await fetchFollowerIds(businessId)).filter((id) => id !== businessId);
  if (recipients.length === 0) return;

  const name = (await actorName(businessId)) ?? 'A business you follow';
  const groupName = (group.name as string | undefined) ?? 'a new group';

  await fanOutInChunks(recipients, async (recipient) => {
    if (await isBlocked(businessId, recipient)) return;
    await createNotificationIdempotent(`group_new_${groupId}_${recipient}`, {
      userId: recipient,
      type: 'group',
      title: 'New group',
      body: `${name} created ${groupName}`,
      deepLink: `/groups/${groupId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: businessId,
      groupId,
    });
  });
});
