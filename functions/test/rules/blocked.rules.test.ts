import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * Security-rule coverage for reading "who blocked me" (H10).
 *
 * The rule was `match /blocked/{blockedId} { allow read, write: if
 * isOwner(userId); }` — only the owner could read their own block list. But
 * nearby_users_screen.dart runs a "who blocked me" query to hide users who
 * blocked *me*, and the call site swallowed the failure with
 * `catch (_) {/* fail open *\/}`, leaving the protection silently dead since
 * it shipped. The feed and match candidates never even attempted it.
 *
 * Two separate defects had to be fixed, and the order matters:
 *
 *   1. The original query was
 *        collectionGroup('blocked').where(FieldPath.documentId, '==', myUid)
 *      which is INVALID, not merely denied: on a collection group query
 *      documentId() is compared against a full document path, so a bare uid
 *      throws client-side before rules are consulted. The blocked uid lived
 *      only as the document *id*, and collection group queries cannot filter
 *      on ids. So `blockUser` now also denormalises it into a `blockedUid`
 *      field, which is what makes the query expressible at all.
 *   2. Only then can a rule admit it, keyed off that same field.
 *
 * Enforced shape:
 *   • the owner keeps full read/write over their own block list
 *   • anyone may read a `blocked` doc whose blockedUid is their own uid,
 *     because that is exactly the fact "this user blocked me"
 *   • nobody may read a `blocked` doc belonging to a third party, so the list
 *     itself stays private; you can learn that X blocked you, never who else
 *     X blocked
 *   • writes stay owner-only: being blocked must not let you un-block yourself
 */
let testEnv: RulesTestEnvironment;

const BLOCKER = 'blocker';
const VICTIM = 'victim';     // the uid BLOCKER blocked
const THIRD = 'third-party'; // also blocked by BLOCKER, unrelated to VICTIM

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
    for (const uid of [BLOCKER, VICTIM, THIRD]) {
      await db.doc(`users/${uid}`).set({ name: uid, isBanned: false, isVerified: false });
    }
    await db.doc(`users/${BLOCKER}/blocked/${VICTIM}`)
      .set({ blockedAt: new Date(), blockedUid: VICTIM });
    await db.doc(`users/${BLOCKER}/blocked/${THIRD}`)
      .set({ blockedAt: new Date(), blockedUid: THIRD });
  });
});

describe('blocked — owner access is unchanged', () => {
  test('owner can read a single doc in their own block list', async () => {
    const db = testEnv.authenticatedContext(BLOCKER).firestore();
    await assertSucceeds(db.doc(`users/${BLOCKER}/blocked/${VICTIM}`).get());
  });

  test('owner can list their whole block list', async () => {
    const db = testEnv.authenticatedContext(BLOCKER).firestore();
    await assertSucceeds(db.collection(`users/${BLOCKER}/blocked`).get());
  });

  test('owner can block and unblock', async () => {
    const db = testEnv.authenticatedContext(BLOCKER).firestore();
    await assertSucceeds(db.doc(`users/${BLOCKER}/blocked/newtarget`)
      .set({ blockedAt: new Date(), blockedUid: 'newtarget' }));
    await assertSucceeds(db.doc(`users/${BLOCKER}/blocked/${THIRD}`).delete());
  });
});

describe('blocked — learning that someone blocked me', () => {
  test('victim can read the doc that blocks them', async () => {
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertSucceeds(db.doc(`users/${BLOCKER}/blocked/${VICTIM}`).get());
  });

  test('victim can run the collectionGroup query constrained to their own uid', async () => {
    // This is the exact query nearby/feed/matches use to build "blockedMe".
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    const snap = await assertSucceeds(
      db.collectionGroup('blocked').where('blockedUid', '==', VICTIM).get());
    expect(snap.docs.map((d: any) => d.ref.parent.parent.id)).toEqual([BLOCKER]);
  });

  test('legacy docs without blockedUid stay unreadable by the blocked user', async () => {
    // Documents written before blockedUid existed carry the uid only in their
    // id, which no collection group query can filter on. They are invisible to
    // the "who blocked me" path until backfilled — a gap that hides people
    // rather than exposing them, so it fails in the safe direction.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`users/${THIRD}/blocked/${VICTIM}`)
        .set({ blockedAt: new Date() });
    });
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(db.doc(`users/${THIRD}/blocked/${VICTIM}`).get());
  });
});

describe('blocked — the list itself stays private', () => {
  test('victim cannot read a doc keyed by a third party', async () => {
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(db.doc(`users/${BLOCKER}/blocked/${THIRD}`).get());
  });

  test('victim cannot list another user\'s whole block list', async () => {
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(db.collection(`users/${BLOCKER}/blocked`).get());
  });

  test('an unconstrained collectionGroup scan is denied', async () => {
    // Without pinning documentId to your own uid there is no proof the query
    // stays inside what the rule admits, so Firestore must reject it whole.
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(db.collectionGroup('blocked').get());
  });

  test('a collectionGroup query pinned to someone else\'s uid is denied', async () => {
    // The sharp edge: the query must pin blockedUid to your OWN uid. Pinning
    // it to anyone else's proves nothing the rule allows, so it fails whole.
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(
      db.collectionGroup('blocked').where('blockedUid', '==', THIRD).get());
  });
});

describe('blocked — being blocked grants no write power', () => {
  test('victim cannot delete the doc that blocks them', async () => {
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(db.doc(`users/${BLOCKER}/blocked/${VICTIM}`).delete());
  });

  test('victim cannot overwrite the doc that blocks them', async () => {
    const db = testEnv.authenticatedContext(VICTIM).firestore();
    await assertFails(
      db.doc(`users/${BLOCKER}/blocked/${VICTIM}`).set({ blockedAt: new Date() }));
  });

  test('an unauthenticated reader is denied outright', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.doc(`users/${BLOCKER}/blocked/${VICTIM}`).get());
  });
});
