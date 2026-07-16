import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  db: { collection: jest.fn() },
  createNotificationIdempotent: jest.fn(),
  actorName: jest.fn(),
}));
jest.mock('../../lib/blocked', () => ({ isBlocked: jest.fn() }));

import { db, createNotificationIdempotent, actorName } from '../../lib/firestore';
import { isBlocked } from '../../lib/blocked';
import { onPostCommentCreated } from '../comments';

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

describe('onPostCommentCreated', () => {
  const wrapped = test.wrap(onPostCommentCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (isBlocked as jest.Mock).mockResolvedValue(false);
    (actorName as jest.Mock).mockResolvedValue('Sam Rivera');
  });

  afterAll(() => test.cleanup());

  it('writes a comment notification keyed by commentId', async () => {
    mockPost(true, 'author-1');

    await wrapped({
      params: { postId: 'post-1', commentId: 'comment-1' },
      data: { authorId: 'commenter-1' },
    });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'comment_comment-1',
      expect.objectContaining({
        userId: 'author-1',
        type: 'comment',
        actorId: 'commenter-1',
        postId: 'post-1',
        deepLink: '/posts/post-1',
      }),
    );
  });

  it('skips when the commenter is the post author', async () => {
    mockPost(true, 'same-uid');

    await wrapped({
      params: { postId: 'post-1', commentId: 'comment-1' },
      data: { authorId: 'same-uid' },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips when blocked in either direction', async () => {
    mockPost(true, 'author-1');
    (isBlocked as jest.Mock).mockResolvedValue(true);

    await wrapped({
      params: { postId: 'post-1', commentId: 'comment-1' },
      data: { authorId: 'commenter-1' },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('falls back to a generic body when the actor doc is missing', async () => {
    mockPost(true, 'author-1');
    (actorName as jest.Mock).mockResolvedValue(null);

    await wrapped({
      params: { postId: 'post-1', commentId: 'comment-1' },
      data: { authorId: 'commenter-1' },
    });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'comment_comment-1',
      expect.objectContaining({ body: 'Someone commented on your post' }),
    );
  });
});
