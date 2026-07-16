import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  createNotificationIdempotent: jest.fn(),
  actorName: jest.fn(),
}));
jest.mock('../../lib/blocked', () => ({ isBlocked: jest.fn() }));

import { createNotificationIdempotent, actorName } from '../../lib/firestore';
import { isBlocked } from '../../lib/blocked';
import { onFollowerCreated } from '../follows';

const test = functionsTest();

describe('onFollowerCreated', () => {
  const wrapped = test.wrap(onFollowerCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (isBlocked as jest.Mock).mockResolvedValue(false);
    (actorName as jest.Mock).mockResolvedValue('Priya Nair');
  });

  afterAll(() => test.cleanup());

  it('writes a follow notification keyed by targetUid + followerId', async () => {
    await wrapped({ params: { targetUid: 'target-1', followerId: 'follower-1' } });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'follow_target-1_follower-1',
      expect.objectContaining({
        userId: 'target-1',
        type: 'follow',
        actorId: 'follower-1',
        deepLink: '/users/follower-1',
      }),
    );
  });

  it('skips a (rules-should-prevent-this) self-follow', async () => {
    await wrapped({ params: { targetUid: 'same-uid', followerId: 'same-uid' } });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips when blocked in either direction', async () => {
    (isBlocked as jest.Mock).mockResolvedValue(true);

    await wrapped({ params: { targetUid: 'target-1', followerId: 'follower-1' } });

    expect(isBlocked).toHaveBeenCalledWith('follower-1', 'target-1');
    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('falls back to a generic body when the actor doc is missing', async () => {
    (actorName as jest.Mock).mockResolvedValue(null);

    await wrapped({ params: { targetUid: 'target-1', followerId: 'follower-1' } });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'follow_target-1_follower-1',
      expect.objectContaining({ body: 'Someone started following you' }),
    );
  });
});
