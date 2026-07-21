import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * Security-rule coverage for post audience (B2).
 *
 * The bug: createPost wrote an `audience` field (Everyone | Only me) and the
 * feed query applied no filter, while the rule was `allow read: if isAuth()`.
 * A post marked "Only me" was readable by every signed-in user.
 *
 * Firestore evaluates rules per document and fails the WHOLE query if any
 * matched document is denied — rules cannot silently filter rows. So the
 * enforceable contract is: a reader may only run queries that are provably
 * within what the rules allow (audience == 'Everyone', or their own posts,
 * or admin).
 */
let testEnv: RulesTestEnvironment;

const ALICE = 'alice';
const BOB = 'bob';
const ADMIN = 'root';

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
  // Seed with rules disabled.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ALICE}`).set({ name: 'Alice', role: 'user' });
    await db.doc(`users/${BOB}`).set({ name: 'Bob', role: 'user' });
    await db.doc(`users/${ADMIN}`).set({ name: 'Root', role: 'admin' });

    await db.doc('posts/public1').set({
      authorId: ALICE, caption: 'public', audience: 'Everyone', createdAt: new Date(),
    });
    await db.doc('posts/private1').set({
      authorId: ALICE, caption: 'secret', audience: 'Only me', createdAt: new Date(),
    });
    await db.doc('posts/group1').set({
      authorId: ALICE, caption: 'group only', audience: 'Everyone',
      groupId: 'g1', createdAt: new Date(),
    });
  });
});

const as = (uid: string) => testEnv.authenticatedContext(uid).firestore();

describe('posts read rules — audience', () => {
  it('a stranger cannot read a post marked "Only me"', async () => {
    await assertFails(as(BOB).doc('posts/private1').get());
  });

  it('the author can still read their own "Only me" post', async () => {
    await assertSucceeds(as(ALICE).doc('posts/private1').get());
  });

  it('anyone signed in can read an "Everyone" post', async () => {
    await assertSucceeds(as(BOB).doc('posts/public1').get());
  });

  it('an admin can read a private post (moderation)', async () => {
    await assertSucceeds(as(ADMIN).doc('posts/private1').get());
  });

  it('a legacy post with no audience field is NOT readable by others', async () => {
    // Documents the migration requirement: `audience` missing fails the
    // Everyone check, so pre-existing posts vanish for everyone but their
    // author until scripts/backfill-post-audience.js has been run.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('posts/legacy1').set({
        authorId: ALICE, caption: 'written before audience existed',
        createdAt: new Date(),
      });
    });

    await assertFails(as(BOB).doc('posts/legacy1').get());
    await assertSucceeds(as(ALICE).doc('posts/legacy1').get());
  });

  it('an unauthenticated reader gets nothing', async () => {
    await assertFails(testEnv.unauthenticatedContext().firestore()
      .doc('posts/public1').get());
  });
});

describe('posts query rules — the feed must be constrained', () => {
  it('an unconstrained feed query is rejected', async () => {
    // This is the query that shipped. It would return private1.
    await assertFails(as(BOB).collection('posts').orderBy('createdAt', 'desc').get());
  });

  it('a feed query constrained to audience == "Everyone" is allowed', async () => {
    await assertSucceeds(
      as(BOB).collection('posts')
        .where('audience', '==', 'Everyone')
        .orderBy('createdAt', 'desc')
        .get());
  });

  it('a user may query their own posts regardless of audience', async () => {
    await assertSucceeds(
      as(ALICE).collection('posts').where('authorId', '==', ALICE).get());
  });

  it('a user may NOT query someone else\'s posts by authorId', async () => {
    await assertFails(
      as(BOB).collection('posts').where('authorId', '==', ALICE).get());
  });

  it('an admin may run an unconstrained query (moderation console)', async () => {
    await assertSucceeds(as(ADMIN).collection('posts').get());
  });
});
