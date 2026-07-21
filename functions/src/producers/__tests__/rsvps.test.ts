import functionsTest from 'firebase-functions-test';

jest.mock('../../lib/firestore', () => ({
  db: { collection: jest.fn() },
  createNotificationIdempotent: jest.fn(),
  actorName: jest.fn(),
}));
jest.mock('../../lib/blocked', () => ({ isBlocked: jest.fn() }));

import { db, createNotificationIdempotent, actorName } from '../../lib/firestore';
import { isBlocked } from '../../lib/blocked';
import { onEventRsvpCreated } from '../rsvps';

const test = functionsTest();

function mockEvent(exists: boolean, createdBy?: string) {
  (db.collection as jest.Mock).mockImplementation((name: string) => {
    if (name !== 'events') throw new Error(`unexpected collection ${name}`);
    return {
      doc: () => ({
        get: async () => ({ exists, data: () => (exists ? { createdBy } : undefined) }),
      }),
    };
  });
}

describe('onEventRsvpCreated', () => {
  const wrapped = test.wrap(onEventRsvpCreated);

  beforeEach(() => {
    jest.clearAllMocks();
    (isBlocked as jest.Mock).mockResolvedValue(false);
    (actorName as jest.Mock).mockResolvedValue('Jordan Lee');
  });

  afterAll(() => test.cleanup());

  it('writes an RSVP notification keyed by eventId + uid', async () => {
    mockEvent(true, 'organizer-1');

    await wrapped({ params: { eventId: 'event-1', uid: 'attendee-1' } });

    expect(createNotificationIdempotent).toHaveBeenCalledWith(
      'rsvp_event-1_attendee-1',
      expect.objectContaining({
        userId: 'organizer-1',
        type: 'event',
        actorId: 'attendee-1',
        eventId: 'event-1',
        deepLink: '/events/event-1',
      }),
    );
  });

  it('skips when the organizer RSVPs to their own event', async () => {
    mockEvent(true, 'same-uid');

    await wrapped({ params: { eventId: 'event-1', uid: 'same-uid' } });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips when blocked in either direction', async () => {
    mockEvent(true, 'organizer-1');
    (isBlocked as jest.Mock).mockResolvedValue(true);

    await wrapped({ params: { eventId: 'event-1', uid: 'attendee-1' } });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });

  it('skips silently when the event no longer exists', async () => {
    mockEvent(false);

    await wrapped({ params: { eventId: 'event-1', uid: 'attendee-1' } });

    expect(createNotificationIdempotent).not.toHaveBeenCalled();
  });
});
