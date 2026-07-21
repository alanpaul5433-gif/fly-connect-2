import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  createNotificationIdempotent: jest.fn(),
}));
jest.mock('../../lib/blocked', () => ({ isBlocked: jest.fn() }));

import { createNotificationIdempotent } from '../../lib/firestore';
import { isBlocked } from '../../lib/blocked';
import { onMatchUpdated } from '../matches';

const test = functionsTest();

describe('onMatchUpdated', () => {
  const wrapped = test.wrap(onMatchUpdated);

  beforeEach(() => {
    jest.clearAllMocks();
    (isBlocked as jest.Mock).mockResolvedValue(false);
  });

  afterAll(() => test.cleanup());

  it('notifies both participants on a pending -> matched transition', async () => {
    await wrapped({
      params: { matchId: 'match-1' },
      data: {
        before: { status: 'pending', userA: 'a1', userB: 'b1' },
        after: { status: 'matched', userA: 'a1', userB: 'b1' },
      },
    });

    expect(createNotificationIdempotent).toHaveBeenCalledTimes(2);
    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'match_match-1_a1',
      expect.objectContaining({ userId: 'a1', actorId: 'b1', type: 'match', deepLink: '/match' }),
    );
    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'match_match-1_b1',
      expect.objectContaining({ userId: 'b1', actorId: 'a1', type: 'match', deepLink: '/match' }),
    );
  });

  it('does not notify on a pending -> passed transition', async () => {
    await wrapped({
      params: { matchId: 'match-1' },
      data: {
        before: { status: 'pending', userA: 'a1', userB: 'b1' },
        after: { status: 'passed', userA: 'a1', userB: 'b1' },
      },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('does not re-notify on a matched -> matched no-op (simulated at-least-once retry)', async () => {
    await wrapped({
      params: { matchId: 'match-1' },
      data: {
        before: { status: 'matched', userA: 'a1', userB: 'b1' },
        after: { status: 'matched', userA: 'a1', userB: 'b1' },
      },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips when the pair is blocked in either direction', async () => {
    (isBlocked as jest.Mock).mockResolvedValue(true);

    await wrapped({
      params: { matchId: 'match-1' },
      data: {
        before: { status: 'pending', userA: 'a1', userB: 'b1' },
        after: { status: 'matched', userA: 'a1', userB: 'b1' },
      },
    });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('produces the same deterministic ids when the same transition is observed twice', async () => {
    // firebase-functions-test's wrap() mutates the object it's given (it
    // deletes `.data` after merging into the generated envelope) — reusing
    // one object reference across two calls would silently break the
    // second invocation, so build a fresh literal per call.
    const makeEvent = () => ({
      params: { matchId: 'match-1' },
      data: {
        before: { status: 'pending', userA: 'a1', userB: 'b1' },
        after: { status: 'matched', userA: 'a1', userB: 'b1' },
      },
    });

    await wrapped(makeEvent());
    await wrapped(makeEvent());

    const ids = (createNotificationIdempotent as jest.Mock).mock.calls.map((c) => c[0]);
    expect(ids).toEqual(['match_match-1_a1', 'match_match-1_b1', 'match_match-1_a1', 'match_match-1_b1']);
  });

  it('scopes notifications independently for two distinct match docs for the same pair', async () => {
    await wrapped({
      params: { matchId: 'match-1' },
      data: {
        before: { status: 'pending', userA: 'a1', userB: 'b1' },
        after: { status: 'matched', userA: 'a1', userB: 'b1' },
      },
    });
    await wrapped({
      params: { matchId: 'match-2' },
      data: {
        before: { status: 'pending', userA: 'a1', userB: 'b1' },
        after: { status: 'matched', userA: 'a1', userB: 'b1' },
      },
    });

    const ids = (createNotificationIdempotent as jest.Mock).mock.calls.map((c) => c[0]);
    expect(ids).toEqual(
      expect.arrayContaining(['match_match-1_a1', 'match_match-1_b1', 'match_match-2_a1', 'match_match-2_b1']),
    );
  });
});
