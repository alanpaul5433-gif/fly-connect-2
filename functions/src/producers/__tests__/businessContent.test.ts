import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  db: { collection: jest.fn() },
  createNotificationIdempotent: jest.fn(),
  actorName: jest.fn(),
}));
jest.mock('../../lib/blocked', () => ({ isBlocked: jest.fn() }));
jest.mock('../../lib/rateLimit', () => ({ shouldFanOut: jest.fn() }));

import { db, createNotificationIdempotent, actorName } from '../../lib/firestore';
import { isBlocked } from '../../lib/blocked';
import { shouldFanOut } from '../../lib/rateLimit';
import { onPromotionApproved, onEventApproved, onGroupCreated } from '../businessContent';

const test = functionsTest();

/** Wires `db.collection('users').doc(businessId).collection('followers').get()`. */
function mockFollowers(followerIds: string[]) {
  (db.collection as jest.Mock).mockImplementation((name: string) => {
    if (name !== 'users') throw new Error(`unexpected top-level collection ${name}`);
    return {
      doc: () => ({
        collection: (sub: string) => {
          if (sub !== 'followers') throw new Error(`unexpected subcollection ${sub}`);
          return { get: async () => ({ docs: followerIds.map((id) => ({ id })) }) };
        },
      }),
    };
  });
}

describe('businessContent producers', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (isBlocked as jest.Mock).mockResolvedValue(false);
    (actorName as jest.Mock).mockResolvedValue('Sky Lounge NYC');
    (shouldFanOut as jest.Mock).mockResolvedValue(true);
  });

  afterAll(() => test.cleanup());

  describe('onPromotionApproved', () => {
    const wrapped = test.wrap(onPromotionApproved);

    it('fans out to followers on an isApproved false -> true transition', async () => {
      mockFollowers(['follower-1', 'follower-2']);

      await wrapped({
        params: { promoId: 'promo-1' },
        data: {
          before: { isApproved: false, businessId: 'biz-1', title: '20% off drinks' },
          after: { isApproved: true, businessId: 'biz-1', title: '20% off drinks' },
        },
      });

      expect(createNotificationIdempotent).toHaveBeenCalledTimes(2);
      expect(createNotificationIdempotent).toHaveBeenCalledWith(
        'promo_promo-1_follower-1',
        expect.objectContaining({
          userId: 'follower-1',
          type: 'promotion',
          actorId: 'biz-1',
          promotionId: 'promo-1',
          deepLink: '/promotions/promo-1',
        }),
      );
    });

    it('does not fan out on an already-approved -> approved no-op', async () => {
      mockFollowers(['follower-1']);

      await wrapped({
        params: { promoId: 'promo-1' },
        data: {
          before: { isApproved: true, businessId: 'biz-1' },
          after: { isApproved: true, businessId: 'biz-1' },
        },
      });

      expect(createNotificationIdempotent).not.toHaveBeenCalled();
    });

    it('does not fan out on a create (no prior isApproved:false -> true edge)', async () => {
      mockFollowers(['follower-1']);

      await wrapped({
        params: { promoId: 'promo-1' },
        data: {
          before: { isApproved: false, businessId: 'biz-1' },
          after: { isApproved: false, businessId: 'biz-1' },
        },
      });

      expect(createNotificationIdempotent).not.toHaveBeenCalled();
    });

    it('is throttled by shouldFanOut', async () => {
      (shouldFanOut as jest.Mock).mockResolvedValue(false);
      mockFollowers(['follower-1']);

      await wrapped({
        params: { promoId: 'promo-1' },
        data: {
          before: { isApproved: false, businessId: 'biz-1' },
          after: { isApproved: true, businessId: 'biz-1' },
        },
      });

      expect(shouldFanOut).toHaveBeenCalledWith('biz-1', 'promotion', expect.any(Number));
      expect(createNotificationIdempotent).not.toHaveBeenCalled();
    });

    it('skips a follower who has blocked the business (or vice versa)', async () => {
      mockFollowers(['follower-1', 'follower-2']);
      (isBlocked as jest.Mock).mockImplementation(
        async (_actor: string, recipient: string) => recipient === 'follower-2',
      );

      await wrapped({
        params: { promoId: 'promo-1' },
        data: {
          before: { isApproved: false, businessId: 'biz-1' },
          after: { isApproved: true, businessId: 'biz-1' },
        },
      });

      expect(createNotificationIdempotent).toHaveBeenCalledTimes(1);
      expect(createNotificationIdempotent).toHaveBeenCalledWith(
        'promo_promo-1_follower-1',
        expect.anything(),
      );
    });
  });

  describe('onEventApproved', () => {
    const wrapped = test.wrap(onEventApproved);

    it('fans out to followers on an isApproved false -> true transition', async () => {
      mockFollowers(['follower-1']);

      await wrapped({
        params: { eventId: 'event-1' },
        data: {
          before: { isApproved: false, createdBy: 'biz-1', title: 'Layover Meetup' },
          after: { isApproved: true, createdBy: 'biz-1', title: 'Layover Meetup' },
        },
      });

      expect(createNotificationIdempotent).toHaveBeenCalledWith(
        'event_new_event-1_follower-1',
        expect.objectContaining({
          userId: 'follower-1',
          type: 'event',
          actorId: 'biz-1',
          eventId: 'event-1',
          deepLink: '/events/event-1',
        }),
      );
    });

    it('does not fan out when isApproved does not transition to true', async () => {
      mockFollowers(['follower-1']);

      await wrapped({
        params: { eventId: 'event-1' },
        data: {
          before: { isApproved: false, createdBy: 'biz-1' },
          after: { isApproved: false, createdBy: 'biz-1' },
        },
      });

      expect(createNotificationIdempotent).not.toHaveBeenCalled();
    });
  });

  describe('onGroupCreated', () => {
    const wrapped = test.wrap(onGroupCreated);

    it('fans out to followers immediately on create (groups have no approval gate)', async () => {
      mockFollowers(['follower-1']);

      await wrapped({
        params: { groupId: 'group-1' },
        data: { createdBy: 'biz-1', name: 'Layover Crew' },
      });

      expect(createNotificationIdempotent).toHaveBeenCalledWith(
        'group_new_group-1_follower-1',
        expect.objectContaining({
          userId: 'follower-1',
          type: 'group',
          actorId: 'biz-1',
          groupId: 'group-1',
          deepLink: '/groups/group-1',
        }),
      );
    });

    it('does nothing when the group has no creator', async () => {
      mockFollowers(['follower-1']);

      await wrapped({ params: { groupId: 'group-1' }, data: { name: 'Layover Crew' } });

      expect(shouldFanOut).not.toHaveBeenCalled();
      expect(createNotificationIdempotent).not.toHaveBeenCalled();
    });

    it('never notifies the business itself even if it somehow follows itself', async () => {
      mockFollowers(['biz-1', 'follower-1']);

      await wrapped({
        params: { groupId: 'group-1' },
        data: { createdBy: 'biz-1', name: 'Layover Crew' },
      });

      expect(createNotificationIdempotent).toHaveBeenCalledTimes(1);
      expect(createNotificationIdempotent).toHaveBeenCalledWith(
        'group_new_group-1_follower-1',
        expect.anything(),
      );
    });
  });
});
