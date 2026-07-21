/**
 * Exercises the real `createNotificationIdempotent`/`actorName` against a
 * fake Firestore double with a `.create()` that mimics the real Admin SDK's
 * ALREADY_EXISTS behavior (grpc code 6) on a duplicate deterministic id.
 */
function mockMakeFakeDb() {
  const store = new Map<string, any>();
  function ref(path: string): any {
    return {
      get: async () => ({ exists: store.has(path), data: () => store.get(path) }),
      doc: (id: string) => ref(`${path}/${id}`),
      collection: (name: string) => ref(`${path}/${name}`),
      set: async (data: unknown) => {
        store.set(path, data);
      },
      create: async (data: any) => {
        if (data?.__forceErrorCode) {
          const err = new Error('forced') as Error & { code: number };
          err.code = data.__forceErrorCode;
          throw err;
        }
        if (store.has(path)) {
          const err = new Error('ALREADY_EXISTS') as Error & { code: number };
          err.code = 6;
          throw err;
        }
        store.set(path, data);
      },
    };
  }
  return { collection: (name: string) => ref(name), __store: store };
}

let mockDbInstance: ReturnType<typeof mockMakeFakeDb>;

jest.mock('firebase-admin/app', () => ({ getApps: () => [{}], initializeApp: jest.fn() }));
jest.mock('firebase-admin/firestore', () => ({
  getFirestore: () => (mockDbInstance = mockMakeFakeDb()),
}));

import { createNotificationIdempotent, actorName } from '../firestore';

describe('createNotificationIdempotent', () => {
  it('writes the notification on first call', async () => {
    await createNotificationIdempotent('id-1', { userId: 'u1' });
    expect(mockDbInstance.__store.get('notifications/id-1')).toEqual({ userId: 'u1' });
  });

  it('treats a duplicate write (ALREADY_EXISTS) as a no-op, not an error', async () => {
    await createNotificationIdempotent('id-1', { userId: 'u1' });
    await expect(createNotificationIdempotent('id-1', { userId: 'different' })).resolves.toBeUndefined();
    // the second, duplicate attempt must not clobber the first write
    expect(mockDbInstance.__store.get('notifications/id-1')).toEqual({ userId: 'u1' });
  });

  it('rethrows any other (non-ALREADY_EXISTS) error', async () => {
    await expect(
      createNotificationIdempotent('id-3', { __forceErrorCode: 13 }),
    ).rejects.toThrow('forced');
  });
});

describe('actorName', () => {
  it('returns the name when the actor doc exists', async () => {
    mockDbInstance.__store.set('users/actor-1', { name: 'Priya Nair' });
    await expect(actorName('actor-1')).resolves.toBe('Priya Nair');
  });

  it('returns null when the actor doc is missing (GDPR-deleted account, etc.)', async () => {
    await expect(actorName('ghost-uid')).resolves.toBeNull();
  });
});
