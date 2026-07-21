import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * Security-rule coverage for account deletion (B3).
 *
 * Play (since May 2024) and the App Store both require in-app account
 * deletion. Every write the client must perform to honour that has to be
 * permitted by the rules, or "Delete Account" fails halfway with
 * permission-denied — which is exactly what shipped: `users/{uid}` was
 * `allow delete: if isAdmin()`, so a user could never erase their own profile.
 */
let testEnv: RulesTestEnvironment;

const ME = 'me';
const OTHER = 'other';

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
    await db.doc(`users/${ME}`).set({ name: 'Me', role: 'user', isBanned: false });
    await db.doc(`users/${OTHER}`).set({ name: 'Other', role: 'user', isBanned: false });

    await db.doc(`users/${ME}/savedPosts/p1`).set({ savedAt: new Date() });
    await db.doc(`users/${ME}/blocked/${OTHER}`).set({ at: new Date() });
    await db.doc(`users/${ME}/following/${OTHER}`).set({ at: new Date() });
    await db.doc(`users/${ME}/followers/${OTHER}`).set({ at: new Date() });
    await db.doc(`users/${ME}/private/data`).set({ fcmToken: 'tok' });

    await db.doc('trips/t1').set({ userId: ME, destination: 'Tokyo' });
    await db.doc('safeChecks/s1').set({ userId: ME, lat: 1, lng: 2 });
    await db.doc('notifications/n1').set({ userId: ME, type: 'like' });
    await db.doc(`stories/${ME}`).set({ items: [] });
    await db.doc('posts/p1').set({
      authorId: ME, authorName: 'Me', audience: 'Everyone', createdAt: new Date(),
    });
  });
});

const as = (uid: string) => testEnv.authenticatedContext(uid).firestore();

describe('account deletion — every write the client must make', () => {
  it('a user can delete their own profile document', async () => {
    await assertSucceeds(as(ME).doc(`users/${ME}`).delete());
  });

  it('a user still cannot delete someone else\'s profile', async () => {
    await assertFails(as(ME).doc(`users/${OTHER}`).delete());
  });

  it('a user can clear their own followers subcollection', async () => {
    // Needed to erase the account: the follow doc is owned by the follower,
    // but the profile owner must be able to remove it during deletion.
    await assertSucceeds(as(ME).doc(`users/${ME}/followers/${OTHER}`).delete());
  });

  it('a user can clear their own following/blocked/saved/private docs', async () => {
    await assertSucceeds(as(ME).doc(`users/${ME}/following/${OTHER}`).delete());
    await assertSucceeds(as(ME).doc(`users/${ME}/blocked/${OTHER}`).delete());
    await assertSucceeds(as(ME).doc(`users/${ME}/savedPosts/p1`).delete());
    await assertSucceeds(as(ME).doc(`users/${ME}/private/data`).delete());
  });

  it('a user can delete their trips, safe-checks, notifications and story', async () => {
    await assertSucceeds(as(ME).doc('trips/t1').delete());
    await assertSucceeds(as(ME).doc('safeChecks/s1').delete());
    await assertSucceeds(as(ME).doc('notifications/n1').delete());
    await assertSucceeds(as(ME).doc(`stories/${ME}`).delete());
  });

  it('a user can query their own trips/safeChecks/notifications to erase them', async () => {
    await assertSucceeds(as(ME).collection('trips').where('userId', '==', ME).get());
    await assertSucceeds(as(ME).collection('safeChecks').where('userId', '==', ME).get());
    await assertSucceeds(
      as(ME).collection('notifications').where('userId', '==', ME).get());
  });

  it('a user can anonymise their own posts', async () => {
    await assertSucceeds(as(ME).doc('posts/p1').update({
      authorName: '[deleted user]', authorPhotoUrl: null, isDeleted: true,
    }));
  });

  it('a user cannot anonymise someone else\'s post', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('posts/p2').set({
        authorId: OTHER, authorName: 'Other', audience: 'Everyone',
        createdAt: new Date(),
      });
    });

    await assertFails(as(ME).doc('posts/p2').update({ isDeleted: true }));
  });

  it('a departing user can remove their own follow entry on another profile',
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`users/${OTHER}/followers/${ME}`).set({ at: new Date() });
      });

      await assertSucceeds(as(ME).doc(`users/${OTHER}/followers/${ME}`).delete());
    });
});
