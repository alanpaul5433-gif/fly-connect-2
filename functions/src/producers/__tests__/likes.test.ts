import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  db: { collection: jest.fn() },
  createNotificationIdempotent: jest.fn(),
  actorName: jest.fn(),
}));
jest.mock('../../lib/blocked', () => ({ isBlocked: jest.fn() }));

import { db, createNotificationIdempotent, actorName } from '../../lib/firestore';
import { isBlocked } from '../../lib/blocked';
import { onPostLikeCreated } from '../likes';

const test = functionsTest();

function mockPost(exists: boolean, authorId?: string) {
  (db.collection as jest.Mock).mockImplementation((name: string) => {
    if (name !== 'posts') throw new Error(`unexpected collection ${name}`);
    return {
      doc: () => ({
        get: async () => ({ exists, data: () => (exists ? { authorId } : undefined) }),
      }),
    };
  });
}

describe('onPostLikeCreated', () => {
  const wrapped = test.wrap(onPostLikeCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (isBlocked as jest.Mock).mockResolvedValue(false);
    (actorName as jest.Mock).mockResolvedValue('Maria Chen');
  });

  afterAll(() => test.cleanup());

  it('writes a like notification with a deterministic id', async () => {
    mockPost(true, 'author-1');

    await wrapped({ params: { postId: 'post-1', likerUid: 'liker-1' } });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'like_post-1_liker-1',
      expect.objectContaining({
        userId: 'author-1',
        type: 'like',
        actorId: 'liker-1',
        postId: 'post-1',
        deepLink: '/posts/post-1',
      }),
    );
  });

  it('skips when the liker is the post author (self-notify guard)', async () => {
    mockPost(true, 'same-uid');

    await wrapped({ params: { postId: 'post-1', likerUid: 'same-uid' } });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips when blocked in either direction', async () => {
    mockPost(true, 'author-1');
    (isBlocked as jest.Mock).mockResolvedValue(true);

    await wrapped({ params: { postId: 'post-1', likerUid: 'liker-1' } });

    expect(isBlocked).toHaveBeenCalledWith('liker-1', 'author-1');
    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips silently when the post no longer exists', async () => {
    mockPost(false);

    await wrapped({ params: { postId: 'post-1', likerUid: 'liker-1' } });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('falls back to a generic body when the actor doc is missing', async () => {
    mockPost(true, 'author-1');
    (actorName as jest.Mock).mockResolvedValue(null);

    await wrapped({ params: { postId: 'post-1', likerUid: 'liker-1' } });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'like_post-1_liker-1',
      expect.objectContaining({ body: 'Someone liked your post' }),
    );
  });
});
