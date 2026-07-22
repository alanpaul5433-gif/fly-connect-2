import functionsTest from 'firebase-functions-test';

jest.mock('../lib/fcm', () => ({
  getFcmToken: jest.fn(),
  getUserSettings: jest.fn(),
  sendPush: jest.fn(),
}));

import { getFcmToken, getUserSettings, sendPush } from '../lib/fcm';
import { onNotificationCreated, isPushAllowed, pushSettingKeyForType } from '../pushFanout';

const test = functionsTest();

describe('push preference gating (H16 — the six settings toggles)', () => {
  it('maps each notification type to its settings toggle', () => {
    expect(pushSettingKeyForType('comment')).toBe('pushComments');
    expect(pushSettingKeyForType('match')).toBe('pushMatches');
    expect(pushSettingKeyForType('message')).toBe('pushMessages');
    expect(pushSettingKeyForType('event')).toBe('pushEvents');
    expect(pushSettingKeyForType('admin_safecheck')).toBe('pushSafeCheck');
    expect(pushSettingKeyForType('like')).toBe('pushLikes');
  });

  it('types with no user toggle are always allowed', () => {
    // follow / group / promotion / admin have no settings switch.
    expect(pushSettingKeyForType('admin')).toBeNull();
    expect(isPushAllowed('admin', { pushComments: false })).toBe(true);
    expect(isPushAllowed('promotion', {})).toBe(true);
  });

  it('a toggle explicitly false blocks that type', () => {
    expect(isPushAllowed('message', { pushMessages: false })).toBe(false);
    expect(isPushAllowed('comment', { pushComments: false })).toBe(false);
  });

  it('missing or true means allowed (default on)', () => {
    expect(isPushAllowed('message', {})).toBe(true);
    expect(isPushAllowed('message', { pushMessages: true })).toBe(true);
    // A different toggle being off does not affect this type.
    expect(isPushAllowed('message', { pushComments: false })).toBe(true);
  });
});

describe('onNotificationCreated (Stage 2 push fan-out)', () => {
  const wrapped = test.wrap(onNotificationCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (getFcmToken as jest.Mock).mockResolvedValue('a-token');
    (getUserSettings as jest.Mock).mockResolvedValue({}); // default: all push on
  });

  it('does not send when the matching push toggle is off (H16)', async () => {
    (getUserSettings as jest.Mock).mockResolvedValue({ pushComments: false });
    await wrapped({
      params: { id: 'comment_c1' },
      data: { userId: 'author-1', type: 'comment', title: 'New comment', body: 'x', postId: 'post-1' },
    });
    expect(sendPush).not.toHaveBeenCalled();
  });

  it('still sends when a DIFFERENT toggle is off', async () => {
    (getUserSettings as jest.Mock).mockResolvedValue({ pushMessages: false });
    await wrapped({
      params: { id: 'comment_c1' },
      data: { userId: 'author-1', type: 'comment', title: 'New comment', body: 'x', postId: 'post-1' },
    });
    expect(sendPush).toHaveBeenCalled();
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

  it('sends group notifications with groupId in the data payload', async () => {
    await wrapped({
      params: { id: 'group_new_g1_u1' },
      data: { userId: 'u1', type: 'group', title: 'New group', body: 'x', groupId: 'g1' },
    });

    expect(sendPush).toHaveBeenCalledWith(
      'a-token',
      expect.objectContaining({ data: { type: 'group', groupId: 'g1' } }),
    );
  });

  it('sends promotion notifications as new_promotion with promotionId in the data payload', async () => {
    await wrapped({
      params: { id: 'promo_p1_u1' },
      data: { userId: 'u1', type: 'promotion', title: 'New deal', body: 'x', promotionId: 'p1' },
    });

    expect(sendPush).toHaveBeenCalledWith(
      'a-token',
      expect.objectContaining({ data: { type: 'new_promotion', promotionId: 'p1' } }),
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
