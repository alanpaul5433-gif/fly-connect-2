import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { db, createNotificationIdempotent, actorName } from '../lib/firestore';
import { isBlocked } from '../lib/blocked';

export const onEventRsvpCreated = onDocumentCreated(
  'events/{eventId}/rsvps/{uid}',
  async (event) => {
    const { eventId, uid } = event.params;

    const evt = await db.collection('events').doc(eventId).get();
    if (!evt.exists) return;
    const createdBy = evt.data()?.createdBy as string | undefined;
    if (!createdBy) return;

    if (uid === createdBy) return; // self-notify guard
    if (await isBlocked(uid, createdBy)) return;

    const name = await actorName(uid);
    const notificationId = `rsvp_${eventId}_${uid}`;

    await createNotificationIdempotent(notificationId, {
      userId: createdBy,
      type: 'event',
      title: 'New RSVP',
      body: name ? `${name} RSVP'd to your event` : 'Someone RSVP\'d to your event',
      deepLink: `/events/${eventId}`,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      actorId: uid,
      eventId,
    });
  },
);
