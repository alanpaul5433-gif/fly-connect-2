import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { db, createNotificationIdempotent, actorName } from '../lib/firestore';

/** Matches the new `firestore.rules` chat-creation cap — see the C-3 design's "Rules changes". */
const MAX_PARTICIPANTS = 50;

/**
 * No blocked-user check here (unlike the other five producers) — chat
 * participants already had to mutually exist in the chat to message at all,
 * a different, pre-existing trust boundary (chat creation/invites) than the
 * one this pass closes. Mirrors the exact sender-exclusion loop already used
 * by `sendMessage`'s `unreadCount` increment for H-3.
 */
export const onChatMessageCreated = onDocumentCreated(
  'chats/{chatId}/messages/{messageId}',
  async (event) => {
    const { chatId, messageId } = event.params;
    const message = event.data?.data();
    if (!message) return;
    const senderId = message.senderId as string | undefined;
    if (!senderId) return;

    const chat = await db.collection('chats').doc(chatId).get();
    if (!chat.exists) return;
    const participants = (chat.data()?.participants as string[] | undefined) ?? [];

    let capped = participants;
    if (participants.length > MAX_PARTICIPANTS) {
      logger.warn(`chat ${chatId} has ${participants.length} participants — capping at ${MAX_PARTICIPANTS}`);
      capped = participants.slice(0, MAX_PARTICIPANTS);
    }

    const recipients = capped.filter((uid) => uid !== senderId);
    if (recipients.length === 0) return;

    const name = await actorName(senderId);
    const body = name ? `${name} sent you a message` : 'You have a new message';

    await Promise.all(
      recipients.map((recipient) =>
        createNotificationIdempotent(`message_${messageId}_${recipient}`, {
          userId: recipient,
          type: 'message',
          title: 'New message',
          body,
          deepLink: `/conversation/${chatId}`,
          isRead: false,
          createdAt: FieldValue.serverTimestamp(),
          actorId: senderId,
          chatId,
        }),
      ),
    );
  },
);
