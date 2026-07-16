import functionsTest from 'firebase-functions-test';

jest.mock('../lib/fcm', () => ({
  getFcmToken: jest.fn(),
  sendPush: jest.fn(),
}));

import { getFcmToken, sendPush } from '../lib/fcm';
import { onNotificationCreated } from '../pushFanout';

const test = functionsTest();

describe('onNotificationCreated (Stage 2 push fan-out)', () => {
  const wrapped = test.wrap(onNotificationCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (getFcmToken as jest.Mock).mockResolvedValue('a-token');
  });

  afterAll(() => test.cleanup());

  it('never calls messaging().send() for type == like', async () => {
    await wrapped({
      params: { id: 'like_post-1_liker-1' },
      data: { userId: 'author-1', type: 'like', title: 'New like', body: 'x' },
    });

    expect(getFcmToken).not.toHaveBeenCalled();
    expect(sendPush).not.toHaveBeenCalled();
  });

  it('sends when a token is present, reading users/{userId}/private/data.fcmToken', async () => {
    await wrapped({
      params: { id: 'comment_c1' },
      data: { userId: 'author-1', type: 'comment', title: 'New comment', body: 'Sam commented', postId: 'post-1' },
    });

    expect(getFcmToken).toHaveBeenCalledWith('author-1');
    expect(sendPush).toHaveBeenCalledWith('a-token', {
      title: 'New comment',
      body: 'Sam commented',
      data: { type: 'post_comment', postId: 'post-1' },
    });
  });

  it('does not send when the token is absent (never falls back to the flat field)', async () => {
    (getFcmToken as jest.Mock).mockResolvedValue(null);

    await wrapped({
      params: { id: 'comment_c1' },
      data: { userId: 'author-1', type: 'comment', title: 'New comment', body: 'Sam commented', postId: 'post-1' },
    });

    expect(sendPush).not.toHaveBeenCalled();
  });

  it('uses a generic title/body for type == match, not the doc content', async () => {
    await wrapped({
      params: { id: 'match_m1_a1' },
      data: { userId: 'a1', type: 'match', title: "It's a match!", body: 'You matched with Alex', actorId: 'b1' },
    });

    expect(sendPush).toHaveBeenCalledWith('a-token', {
      title: 'You have a new match',
      body: 'You have a new match',
      data: { type: 'match' },
    });
  });

  it('uses a generic title/body for type == message, not the doc content', async () => {
    await wrapped({
      params: { id: 'message_msg1_r1' },
      data: { userId: 'r1', type: 'message', title: 'New message', body: 'Dana Kim sent you a message', chatId: 'chat-1' },
    });

    expect(sendPush).toHaveBeenCalledWith('a-token', {
      title: 'New message',
      body: 'New message',
      data: { type: 'message', chatId: 'chat-1' },
    });
  });

  it('renames follow_request data.userId to the doc\'s actorId, not the doc\'s own userId', async () => {
    await wrapped({
      params: { id: 'follow_target-1_follower-1' },
      data: { userId: 'target-1', type: 'follow', title: 'New follower', body: 'x', actorId: 'follower-1' },
    });

    expect(sendPush).toHaveBeenCalledWith(
      'a-token',
      expect.objectContaining({ data: { type: 'follow_request', userId: 'follower-1' } }),
    );
  });

  it('sends event notifications with eventId in the data payload', async () => {
    await wrapped({
      params: { id: 'rsvp_e1_u1' },
      data: { userId: 'organizer-1', type: 'event', title: 'New RSVP', body: 'x', eventId: 'event-1' },
    });

    expect(sendPush).toHaveBeenCalledWith(
      'a-token',
      expect.objectContaining({ data: { type: 'event', eventId: 'event-1' } }),
    );
  });

  it('sends admin broadcasts with no data payload (falls through to notifications on tap)', async () => {
    await wrapped({
      params: { id: 'admin-broadcast-1' },
      data: { userId: 'u1', type: 'admin', title: 'Announcement', body: 'x' },
    });

    expect(sendPush).toHaveBeenCalledWith('a-token', { title: 'Announcement', body: 'x', data: {} });
  });

  it('sends admin_safecheck broadcasts with a safe_check data type', async () => {
    await wrapped({
      params: { id: 'admin-safecheck-1' },
      data: { userId: 'u1', type: 'admin_safecheck', title: 'Safety alert', body: 'x' },
    });

    expect(sendPush).toHaveBeenCalledWith(
      'a-token',
      expect.objectContaining({ data: { type: 'safe_check' } }),
    );
  });
});
