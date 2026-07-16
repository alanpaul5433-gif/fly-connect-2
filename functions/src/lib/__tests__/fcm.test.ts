/**
 * The review's headline blocker for this file: Stage 2 must read
 * `users/{userId}/private/data.fcmToken`, never the stale flat
 * `users/{userId}.fcmToken` the Dart UserModel still carries for backward
 * compatibility. Getting this path wrong means every push silently no-ops.
 */
function mockMakeFakeDb() {
  const store = new Map<string, any>();
  function ref(path: string): any {
    return {
      get: async () => ({ exists: store.has(path), data: () => store.get(path) }),
      doc: (id: string) => ref(`${path}/${id}`),
      collection: (name: string) => ref(`${path}/${name}`),
    };
  }
  return { collection: (name: string) => ref(name), __store: store };
}

let mockDbInstance: ReturnType<typeof mockMakeFakeDb>;
const mockSend = jest.fn();

jest.mock('firebase-admin/app', () => ({ getApps: () => [{}], initializeApp: jest.fn() }));
jest.mock('firebase-admin/firestore', () => ({
  getFirestore: () => (mockDbInstance = mockMakeFakeDb()),
}));
jest.mock('firebase-admin/messaging', () => ({ getMessaging: () => ({ send: mockSend }) }));

import { getFcmToken, sendPush } from '../fcm';

describe('getFcmToken', () => {
  beforeEach(() => mockDbInstance.__store.clear());

  it('reads the token from users/{uid}/private/data.fcmToken', async () => {
    mockDbInstance.__store.set('users/u1/private/data', { fcmToken: 'real-token' });
    await expect(getFcmToken('u1')).resolves.toBe('real-token');
  });

  it('does NOT fall back to the stale flat users/{uid}.fcmToken field', async () => {
    // Seed only the flat (legacy) location — private/data has nothing.
    mockDbInstance.__store.set('users/u1', { fcmToken: 'stale-flat-token' });
    await expect(getFcmToken('u1')).resolves.toBeNull();
  });

  it('returns null when private/data has no fcmToken at all', async () => {
    mockDbInstance.__store.set('users/u1/private/data', { email: 'a@b.com' });
    await expect(getFcmToken('u1')).resolves.toBeNull();
  });
});

describe('sendPush', () => {
  beforeEach(() => mockSend.mockClear());

  it('calls messaging().send() with the given token/title/body/data', async () => {
    mockSend.mockResolvedValue('message-id');
    await sendPush('tok-1', { title: 'T', body: 'B', data: { type: 'event' } });

    expect(mockSend).toHaveBeenCalledWith({
      token: 'tok-1',
      notification: { title: 'T', body: 'B' },
      data: { type: 'event' },
    });
  });

  it('catches and logs a send failure rather than throwing', async () => {
    mockSend.mockRejectedValue(new Error('registration-token-not-registered'));
    await expect(
      sendPush('expired-tok', { title: 'T', body: 'B', data: {} }),
    ).resolves.toBeUndefined();
  });
});
