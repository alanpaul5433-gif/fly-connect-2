import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * Rules coverage for users/{uid}/dailyStats (H20). Written only by the
 * scheduled Cloud Function (admin SDK, bypasses rules); the business owner
 * reads their own follower-growth history, nobody else, and no client writes.
 */
let testEnv: RulesTestEnvironment;
const OWNER = 'biz-owner';
const OTHER = 'someone-else';

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-flyconnect-test',
    firestore: {
      rules: readFileSync(resolve(__dirname, '../../../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => { await testEnv.cleanup(); });

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${OWNER}`).set({ role: 'business', isBanned: false });
    await db.doc(`users/${OWNER}/dailyStats/2026-07-22`)
      .set({ followerCount: 100, at: new Date() });
  });
});

test('the owner can read their own daily stats', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertSucceeds(db.doc(`users/${OWNER}/dailyStats/2026-07-22`).get());
});

test('another user cannot read a business\'s daily stats', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(db.doc(`users/${OWNER}/dailyStats/2026-07-22`).get());
});

test('no client can write daily stats (function-only, via admin SDK)', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(db.doc(`users/${OWNER}/dailyStats/2026-07-23`)
    .set({ followerCount: 101, at: new Date() }));
});
