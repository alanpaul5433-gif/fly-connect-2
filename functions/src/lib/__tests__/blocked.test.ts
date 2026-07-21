/**
 * Exercises the real `db` wiring (not a mocked lib/firestore) against a fake
 * Firestore double, since blocked.ts's whole job is composing two real reads
 * through `db` — mocking `../firestore` itself would test nothing.
 */
function mockMakeFakeDb() {
  function ref(path: string): any {
    return {
      get: async () => {
        const seed = (globalThis as any).__seed ?? {};
        return { exists: path in seed, data: () => seed[path] };
      },
      doc: (id: string) => ref(`${path}/${id}`),
      collection: (name: string) => ref(`${path}/${name}`),
    };
  }
  return { collection: (name: string) => ref(name) };
}

jest.mock('firebase-admin/app', () => ({ getApps: () => [{}], initializeApp: jest.fn() }));
jest.mock('firebase-admin/firestore', () => ({
  getFirestore: () => mockMakeFakeDb(),
}));

import { isBlocked } from '../blocked';

describe('isBlocked', () => {
  afterEach(() => {
    (globalThis as any).__seed = {};
  });

  it('returns false when neither direction has blocked the other', async () => {
    (globalThis as any).__seed = {};
    await expect(isBlocked('actor-1', 'recipient-1')).resolves.toBe(false);
  });

  it('returns true when the recipient blocked the actor', async () => {
    (globalThis as any).__seed = { 'users/recipient-1/blocked/actor-1': { blockedAt: 1 } };
    await expect(isBlocked('actor-1', 'recipient-1')).resolves.toBe(true);
  });

  it('returns true when the actor blocked the recipient (the other direction)', async () => {
    (globalThis as any).__seed = { 'users/actor-1/blocked/recipient-1': { blockedAt: 1 } };
    await expect(isBlocked('actor-1', 'recipient-1')).resolves.toBe(true);
  });
});
