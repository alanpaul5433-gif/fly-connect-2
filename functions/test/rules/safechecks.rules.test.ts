import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * Security-rule coverage for SafeCheck visibility (H18).
 *
 * SafeCheck Visibility (Everyone / Friends Only / Verified Users) was enforced
 * only in Dart. The collection rule was `allow read: if isAuth() &&
 * isNotBanned()`, so any signed-in user could read every check-in document
 * directly — status, free-text message, city and precise lat/lng — regardless
 * of the author's setting. For a personal-safety feature that is the whole
 * point of the control.
 *
 * Enforced shape:
 *   visibility 'all'      → any signed-in, non-banned user
 *   visibility 'verified' → readers whose own profile has isVerified == true
 *   visibility 'friends'  → readers listed in the doc's denormalised visibleTo
 *   always                → the author
 *
 * No backfill is needed: check-ins carry a 24h expiresAt, so documents written
 * before `visibility` existed age out on their own.
 */
let testEnv: RulesTestEnvironment;

const AUTHOR = 'author';
const FRIEND = 'friend';
const STRANGER = 'stranger';
const VERIFIED = 'verified-user';

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
    for (const uid of [AUTHOR, FRIEND, STRANGER]) {
      await db.doc(`users/${uid}`).set({ name: uid, isBanned: false, isVerified: false });
    }
    await db.doc(`users/${VERIFIED}`).set({ name: 'V', isBanned: false, isVerified: true });

    const base = { userId: AUTHOR, userName: 'Author', status: 'safe',
      city: 'NYC', lat: 40.7, lng: -74.0, createdAt: new Date() };

    await db.doc('safeChecks/open').set({ ...base, visibility: 'all' });
    await db.doc('safeChecks/friendsOnly').set({
      ...base, visibility: 'friends', visibleTo: [FRIEND],
    });
    await db.doc('safeChecks/verifiedOnly').set({ ...base, visibility: 'verified' });
  });
});

const as = (uid: string) => testEnv.authenticatedContext(uid).firestore();

describe('safeChecks read rules — visibility', () => {
  it('a stranger cannot read a "Friends Only" check-in', async () => {
    await assertFails(as(STRANGER).doc('safeChecks/friendsOnly').get());
  });

  it('a listed friend can read a "Friends Only" check-in', async () => {
    await assertSucceeds(as(FRIEND).doc('safeChecks/friendsOnly').get());
  });

  it('an unverified reader cannot read a "Verified Users" check-in', async () => {
    await assertFails(as(STRANGER).doc('safeChecks/verifiedOnly').get());
  });

  it('a verified reader can read a "Verified Users" check-in', async () => {
    await assertSucceeds(as(VERIFIED).doc('safeChecks/verifiedOnly').get());
  });

  it('anyone signed in can read an "Everyone" check-in', async () => {
    await assertSucceeds(as(STRANGER).doc('safeChecks/open').get());
  });

  it('the author can always read their own check-in', async () => {
    await assertSucceeds(as(AUTHOR).doc('safeChecks/friendsOnly').get());
    await assertSucceeds(as(AUTHOR).doc('safeChecks/verifiedOnly').get());
  });

  it('a check-in written before `visibility` existed is not readable by others',
    async () => {
      // Acceptable because check-ins expire in 24h — documented, not silent.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc('safeChecks/legacy').set({
          userId: AUTHOR, status: 'safe', city: 'NYC', createdAt: new Date(),
        });
      });

      await assertFails(as(STRANGER).doc('safeChecks/legacy').get());
    });
});

describe('safeChecks query rules — the nearby feed must be constrained', () => {
  it('an unconstrained scan of every check-in is rejected', async () => {
    // This is the query that shipped: orderBy(createdAt).limit(100).
    await assertFails(
      as(STRANGER).collection('safeChecks').orderBy('createdAt', 'desc').get());
  });

  it('a query limited to visibility == "all" is allowed', async () => {
    await assertSucceeds(
      as(STRANGER).collection('safeChecks')
        .where('visibility', '==', 'all')
        .orderBy('createdAt', 'desc').get());
  });

  it('a friend may query the check-ins that list them in visibleTo', async () => {
    // Both clauses are required: array-contains alone does not prove the
    // `visibility == 'friends'` branch of the rule, so Firestore rejects it.
    await assertSucceeds(
      as(FRIEND).collection('safeChecks')
        .where('visibility', '==', 'friends')
        .where('visibleTo', 'array-contains', FRIEND)
        .orderBy('createdAt', 'desc').get());
  });

  it('array-contains alone is not enough — visibility must also be pinned',
    async () => {
      await assertFails(
        as(FRIEND).collection('safeChecks')
          .where('visibleTo', 'array-contains', FRIEND)
          .orderBy('createdAt', 'desc').get());
    });

  it('a reader cannot query someone else\'s visibleTo bucket', async () => {
    await assertFails(
      as(STRANGER).collection('safeChecks')
        .where('visibleTo', 'array-contains', FRIEND).get());
  });

  it('a user may query their own check-in history', async () => {
    await assertSucceeds(
      as(AUTHOR).collection('safeChecks').where('userId', '==', AUTHOR).get());
  });
});

describe('safeChecks write rules', () => {
  it('a user cannot forge a check-in as someone else', async () => {
    await assertFails(as(STRANGER).collection('safeChecks').add({
      userId: AUTHOR, status: 'safe', city: 'NYC',
      visibility: 'all', createdAt: new Date(),
    }));
  });

  it('a user can write their own check-in', async () => {
    await assertSucceeds(as(STRANGER).collection('safeChecks').add({
      userId: STRANGER, status: 'safe', city: 'NYC',
      visibility: 'all', createdAt: new Date(),
    }));
  });
});
