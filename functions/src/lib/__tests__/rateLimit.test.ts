/**
 * Exercises the real `db` wiring against a fake Firestore double (same
 * convention as blocked.test.ts) since shouldFanOut's whole job is a
 * real read + conditional write through `db`.
 */
function mockMakeFakeDb() {
  const seed: Record<string, any> = {};
  function ref(path: string): any {
    return {
      get: async () => ({ exists: path in seed, data: () => seed[path] }),
      set: async (data: any) => {
        seed[path] = data;
      },
      doc: (id: string) => ref(`${path}/${id}`),
      collection: (name: string) => ref(`${path}/${name}`),
    };
  }
  return { collection: (name: string) => ref(name), __seed: seed };
}

jest.mock('firebase-admin/app', () => ({ getApps: () => [{}], initializeApp: jest.fn() }));
jest.mock('firebase-admin/firestore', () => ({
  getFirestore: () => mockMakeFakeDb(),
  FieldValue: { serverTimestamp: () => ({ __serverTimestamp: true, toMillis: () => Date.now() }) },
}));

import { shouldFanOut } from '../rateLimit';

describe('shouldFanOut', () => {
  it('allows the first fan-out for a business+type pair', async () => {
    await expect(shouldFanOut('biz-1', 'promotion', 6 * 60 * 60 * 1000)).resolves.toBe(true);
  });

  it('blocks a second fan-out within the cooldown window', async () => {
    await shouldFanOut('biz-2', 'event', 6 * 60 * 60 * 1000);
    await expect(shouldFanOut('biz-2', 'event', 6 * 60 * 60 * 1000)).resolves.toBe(false);
  });

  it('scopes the cooldown independently per content type for the same business', async () => {
    await shouldFanOut('biz-3', 'promotion', 6 * 60 * 60 * 1000);
    await expect(shouldFanOut('biz-3', 'group', 6 * 60 * 60 * 1000)).resolves.toBe(true);
  });

  it('scopes the cooldown independently per business for the same type', async () => {
    await shouldFanOut('biz-4', 'promotion', 6 * 60 * 60 * 1000);
    await expect(shouldFanOut('biz-5', 'promotion', 6 * 60 * 60 * 1000)).resolves.toBe(true);
  });

  it('allows fan-out again once the cooldown has elapsed', async () => {
    await shouldFanOut('biz-6', 'event', 0);
    await expect(shouldFanOut('biz-6', 'event', 0)).resolves.toBe(true);
  });
});
