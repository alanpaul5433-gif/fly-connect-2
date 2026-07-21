import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  db: { collection: jest.fn() },
  createNotificationIdempotent: jest.fn(),
  actorName: jest.fn(),
}));

import { db, createNotificationIdempotent, actorName } from '../../lib/firestore';
import { onChatMessageCreated } from '../messages';

const test = functionsTest();

function mockChat(participants: string[], mutedBy: string[] = []) {
  (db.collection as jest.Mock).mockImplementation((name: string) => {
    if (name !== 'chats') throw new Error(`unexpected collection ${name}`);
    return { doc: () => ({ get: async () => ({ exists: true, data: () => ({ participants, mutedBy }) }) }) };
  });
}

describe('onChatMessageCreated', () => {
  const wrapped = test.wrap(onChatMessageCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (actorName as jest.Mock).mockResolvedValue('Dana Kim');
  });

  afterAll(() => test.cleanup());

  it('notifies the other participant in a 2-person DM', async () => {
    mockChat(['sender-1', 'recipient-1']);

    await wrapped({
      params: { chatId: 'chat-1', messageId: 'msg-1' },
      data: { senderId: 'sender-1' },
    });

    expect(createNotificationIdempotent).toHaveBeenCalledTimes(1);
    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'message_msg-1_recipient-1',
      expect.objectContaining({
        userId: 'recipient-1',
        type: 'message',
        actorId: 'sender-1',
        chatId: 'chat-1',
        deepLink: '/conversation/chat-1',
      }),
    );
  });

  it('notifies exactly N-1 participants in a group chat, never the sender', async () => {
    const participants = ['sender-1', 'p2', 'p3', 'p4'];
    mockChat(participants);

    await wrapped({
      params: { chatId: 'chat-1', messageId: 'msg-1' },
      data: { senderId: 'sender-1' },
    });

    expect(createNotificationIdempotent).toHaveBeenCalledTimes(3);
    const notifiedIds = (createNotificationIdempotent as jest.Mock).mock.calls.map((c) => c[0]);
    expect(notifiedIds).toEqual(
      expect.arrayContaining(['message_msg-1_p2', 'message_msg-1_p3', 'message_msg-1_p4']),
    );
    expect(notifiedIds).not.toContain('message_msg-1_sender-1');
  });

  it('caps fan-out at the first 50 participants', async () => {
    const participants = ['sender-1', ...Array.from({ length: 60 }, (_, i) => `p${i}`)];
    mockChat(participants);

    await wrapped({
      params: { chatId: 'chat-1', messageId: 'msg-1' },
      data: { senderId: 'sender-1' },
    });

    // 50 participants total in the cap, minus the sender who is among them.
    expect(createNotificationIdempotent).toHaveBeenCalledTimes(49);
  });

  it('does not notify a recipient who has muted the conversation (M-7)', async () => {
    mockChat(['sender-1', 'recipient-1', 'recipient-2'], ['recipient-1']);

    await wrapped({
      params: { chatId: 'chat-1', messageId: 'msg-1' },
      data: { senderId: 'sender-1' },
    });

    expect(createNotificationIdempotent).toHaveBeenCalledTimes(1);
    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'message_msg-1_recipient-2',
      expect.objectContaining({ userId: 'recipient-2' }),
    );
  });

  it('skips entirely if every other participant has muted the conversation', async () => {
    mockChat(['sender-1', 'recipient-1'], ['recipient-1']);

    await wrapped({
      params: { chatId: 'chat-1', messageId: 'msg-1' },
      data: { senderId: 'sender-1' },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips entirely if the chat no longer exists', async () => {
    (db.collection as jest.Mock).mockImplementation(() => ({
      doc: () => ({ get: async () => ({ exists: false, data: () => undefined }) }),
    }));

    await wrapped({
      params: { chatId: 'chat-1', messageId: 'msg-1' },
      data: { senderId: 'sender-1' },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });
});
