import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * Security-rule coverage for deleting a post and its engagement (H13).
 *
 * deletePost builds ONE atomic batch that removes every comment and like, then
 * the post. But the subcollection rules only let the OWNER of a like/comment
 * delete it (`allow write: if isOwner(userId)` on likes). The moment another
 * user liked or commented, that user's doc was denied, and Firestore fails the
 * whole batch atomically — so a post anyone else engaged with could never be
 * deleted by its author.
 *
 * Fix (denormalised, no get()): each like/comment carries `postAuthorId`, and
 * the delete rule additionally admits the post's author. get() was avoided on
 * purpose — a cascade batch would blow past Firestore's 20-document-access
 * ceiling for multi-doc operations.
 */
let testEnv: RulesTestEnvironment;

const AUTHOR = 'author';
const LIKER = 'other-liker';
const COMMENTER = 'other-commenter';
const STRANGER = 'stranger';
const POST = 'post1';

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
    for (const uid of [AUTHOR, LIKER, COMMENTER, STRANGER]) {
      await db.doc(`users/${uid}`).set({ name: uid, isBanned: false });
    }
    await db.doc(`posts/${POST}`).set({
      authorId: AUTHOR, audience: 'Everyone', caption: 'hi', createdAt: new Date(),
    });
    // Engagement from OTHER users, each carrying the denormalised postAuthorId.
    await db.doc(`posts/${POST}/likes/${LIKER}`)
      .set({ likedAt: new Date(), postAuthorId: AUTHOR });
    await db.doc(`posts/${POST}/comments/c1`)
      .set({ authorId: COMMENTER, postAuthorId: AUTHOR, text: 'nice', createdAt: new Date() });
  });
});

describe('post author cleaning up engagement they do not own', () => {
  test('can delete another user\'s like on their own post', async () => {
    const db = testEnv.authenticatedContext(AUTHOR).firestore();
    await assertSucceeds(db.doc(`posts/${POST}/likes/${LIKER}`).delete());
  });

  test('can delete another user\'s comment on their own post', async () => {
    const db = testEnv.authenticatedContext(AUTHOR).firestore();
    await assertSucceeds(db.doc(`posts/${POST}/comments/c1`).delete());
  });

  test('can delete the post document itself', async () => {
    const db = testEnv.authenticatedContext(AUTHOR).firestore();
    await assertSucceeds(db.doc(`posts/${POST}`).delete());
  });
});

describe('engagement owners keep their own delete power', () => {
  test('the liker can still delete their own like', async () => {
    const db = testEnv.authenticatedContext(LIKER).firestore();
    await assertSucceeds(db.doc(`posts/${POST}/likes/${LIKER}`).delete());
  });

  test('the commenter can still delete their own comment', async () => {
    const db = testEnv.authenticatedContext(COMMENTER).firestore();
    await assertSucceeds(db.doc(`posts/${POST}/comments/c1`).delete());
  });
});

describe('no wider grant than intended', () => {
  test('a stranger cannot delete a like on someone else\'s post', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(db.doc(`posts/${POST}/likes/${LIKER}`).delete());
  });

  test('a stranger cannot delete a comment on someone else\'s post', async () => {
    const db = testEnv.authenticatedContext(STRANGER).firestore();
    await assertFails(db.doc(`posts/${POST}/comments/c1`).delete());
  });

  test('the liker cannot delete a THIRD party\'s like via postAuthorId', async () => {
    // postAuthorId names the author, not the liker — being a liker grants
    // nothing over other people's likes.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`posts/${POST}/likes/${STRANGER}`)
        .set({ likedAt: new Date(), postAuthorId: AUTHOR });
    });
    const db = testEnv.authenticatedContext(LIKER).firestore();
    await assertFails(db.doc(`posts/${POST}/likes/${STRANGER}`).delete());
  });
});
