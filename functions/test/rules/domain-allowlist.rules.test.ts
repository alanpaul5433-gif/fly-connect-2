import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import { readFileSync } from 'fs';
import { resolve } from 'path';

/**
 * RulesTestContext.firestore() hands back a COMPAT Firestore instance, so the
 * admin SDK's FieldValue is rejected as "a custom ServerTimestampTransform
 * object". The rules require `addedAt == request.time`, which only a real
 * server timestamp satisfies — a client-side `new Date()` must fail, and W5
 * asserts exactly that.
 */
const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();

/**
 * Rules coverage for the signup email-domain allowlist.
 *
 * This is the actual security boundary for the feature. The Flutter check in
 * signup_screen.dart is UX only — the Firebase API key ships inside the APK, so
 * anyone can POST to the Identity Toolkit accounts:signUp endpoint and then
 * write their own users/{uid} document straight from the REST API. If R-series
 * below passes and the client check is bypassed, the gate still holds.
 *
 * Two cases here are real bypasses rather than tidiness:
 *   • notdelta.com must not match delta.com (endsWith)
 *   • delta.com.evil.com must not match delta.com (contains) — and the attacker
 *     owns evil.com, so registering that subdomain is free.
 *
 * The E-series is the grandfathering guarantee: enforcement lives on `create`,
 * so a user whose document already exists is never re-checked.
 */
let testEnv: RulesTestEnvironment;

const ADMIN = 'admin-1';
const EXISTING = 'existing-user';
const NEWBIE = 'new-user';

/** The token claims drive request.auth.token.email — that is the whole gate. */
const asUser = (uid: string, email: string) =>
  testEnv.authenticatedContext(uid, { email, email_verified: false }).firestore();

const newCrewDoc = {
  name: 'Alex',
  role: 'user',
  isBanned: false,
  isVerified: false,
};

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
    await db.doc(`users/${ADMIN}`).set({ role: 'admin', isBanned: false });
    // A user who signed up before the gate existed, on a domain that is not
    // and never will be on the allowlist.
    await db.doc(`users/${EXISTING}`)
      .set({ role: 'user', isBanned: false, isVerified: false, name: 'Old Timer' });

    await db.doc('app_config/signup_gate').set({ enforced: true });
    await db.doc('allowed_domains/delta.com')
      .set({ domain: 'delta.com', enabled: true, addedBy: ADMIN, addedAt: new Date() });
    await db.doc('allowed_domains/legacyair.com')
      .set({ domain: 'legacyair.com', enabled: false, addedBy: ADMIN, addedAt: new Date() });
  });
});

// ── D: the gate itself ────────────────────────────────────────────────
describe('users create — domain gate', () => {
  test('D1 allows an exact match on an enabled domain', async () => {
    const db = asUser(NEWBIE, 'pilot@delta.com');
    await assertSucceeds(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D2 denies a domain that is not on the list', async () => {
    const db = asUser(NEWBIE, 'pilot@spirit.com');
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D3 denies a listed domain whose enabled flag is false', async () => {
    // Proves the soft delete actually enforces, rather than being cosmetic.
    const db = asUser(NEWBIE, 'pilot@legacyair.com');
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D4 is case-insensitive on the domain', async () => {
    const db = asUser(NEWBIE, 'PILOT@DELTA.COM');
    await assertSucceeds(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D5 BYPASS: does not match a domain merely ending in an allowed one', async () => {
    const db = asUser(NEWBIE, 'pilot@notdelta.com');
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D6 BYPASS: does not match an allowed domain used as a subdomain', async () => {
    const db = asUser(NEWBIE, 'pilot@delta.com.evil.com');
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D7 does not expand subdomains implicitly', async () => {
    const db = asUser(NEWBIE, 'pilot@mail.delta.com');
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D8 denies a token with no email claim (phone auth)', async () => {
    // hasTokenEmail() must DENY here, not error — an eval error and a deny look
    // the same from outside, but only one of them is intentional.
    const db = testEnv.authenticatedContext(NEWBIE).firestore();
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D9 denies a malformed email claim rather than erroring', async () => {
    await assertFails(asUser(NEWBIE, 'no-at-sign').doc(`users/${NEWBIE}`).set(newCrewDoc));
    await assertFails(asUser(NEWBIE, 'a@b@delta.com').doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D10 denies an Apple private-relay address', async () => {
    // Encodes the product decision. Flip to assertSucceeds only if you
    // deliberately allowlist the relay — which would admit any Apple ID.
    const db = asUser(NEWBIE, 'a1b2c3@privaterelay.appleid.com');
    await assertFails(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('D11 still enforces the pre-existing create guards', async () => {
    const db = asUser(NEWBIE, 'pilot@delta.com');
    // Allowed domain must not become a licence to self-promote.
    await assertFails(db.doc(`users/${NEWBIE}`).set({ ...newCrewDoc, role: 'admin' }));
    await assertFails(db.doc(`users/${NEWBIE}`).set({ ...newCrewDoc, isVerified: true }));
    await assertFails(db.doc(`users/${NEWBIE}`).set({ ...newCrewDoc, isBanned: true }));
    // Still cannot create someone else's document.
    await assertFails(db.doc('users/somebody-else').set(newCrewDoc));
  });
});

// ── B: business accounts are exempt ───────────────────────────────────
describe('users create — business exemption', () => {
  const newBusinessDoc = {
    name: 'Airport Lounge',
    role: 'business',
    isBanned: false,
    isVerified: false,
    verificationStatus: 'pending',
  };

  test('B1 allows a business signup on an unlisted domain', async () => {
    // Hotels and lounges will never hold an airline email. They are gated by
    // admin approval (verificationStatus), not by the domain allowlist.
    const db = asUser(NEWBIE, 'owner@somehotel.com');
    await assertSucceeds(db.doc(`users/${NEWBIE}`).set(newBusinessDoc));
  });

  test('B2 allows a business signup on a gmail address', async () => {
    const db = asUser(NEWBIE, 'owner@gmail.com');
    await assertSucceeds(db.doc(`users/${NEWBIE}`).set(newBusinessDoc));
  });

  test('B3 does not let business bypass the isVerified guard', async () => {
    const db = asUser(NEWBIE, 'owner@somehotel.com');
    await assertFails(
      db.doc(`users/${NEWBIE}`).set({ ...newBusinessDoc, isVerified: true }));
  });
});

// ── G: the kill switch ────────────────────────────────────────────────
describe('signup gate switch', () => {
  test('G1 allows any domain while the gate is off', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('app_config/signup_gate').set({ enforced: false });
    });
    const db = asUser(NEWBIE, 'anyone@anywhere.com');
    await assertSucceeds(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('G2 fails OPEN when the config document is missing', async () => {
    // Deliberate. Deploying these rules before seeding the config must not
    // deny every signup on the platform — that is a silent outage, reported to
    // users as "check your connection".
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('app_config/signup_gate').delete();
    });
    const db = asUser(NEWBIE, 'anyone@anywhere.com');
    await assertSucceeds(db.doc(`users/${NEWBIE}`).set(newCrewDoc));
  });

  test('G3 is publicly gettable but not listable', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(anon.doc('app_config/signup_gate').get());
    await assertFails(anon.collection('app_config').get());
  });

  test('G4 is writable only by an admin, with a validated shape', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(admin.doc('app_config/signup_gate').set({
      enforced: true, updatedBy: ADMIN, updatedAt: serverTimestamp(),
    }));
    await assertFails(admin.doc('app_config/signup_gate').set({
      enforced: 'yes', updatedBy: ADMIN, updatedAt: serverTimestamp(),
    }));
    const user = asUser(EXISTING, 'old@timer.com');
    await assertFails(user.doc('app_config/signup_gate').set({
      enforced: false, updatedBy: EXISTING, updatedAt: serverTimestamp(),
    }));
  });
});

// ── A: allowed_domains access — the leak boundary ─────────────────────
describe('allowed_domains access', () => {
  test('A1 an unauthenticated client can GET one domain (the pre-flight)', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(anon.doc('allowed_domains/delta.com').get());
  });

  test('A2 an unauthenticated client cannot LIST the domains', async () => {
    // The most important assertion in this file: a list would hand over the
    // entire airline-customer roster in one request.
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(anon.collection('allowed_domains').get());
  });

  test('A3 a signed-in non-admin cannot list either', async () => {
    const db = asUser(EXISTING, 'old@timer.com');
    await assertFails(db.collection('allowed_domains').get());
  });

  test('A4 an admin can list', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(admin.collection('allowed_domains').get());
  });
});

// ── W: allowed_domains writes ─────────────────────────────────────────
describe('allowed_domains writes', () => {
  const entry = (domain: string, extra: Record<string, unknown> = {}) => ({
    domain,
    enabled: true,
    addedBy: ADMIN,
    addedAt: serverTimestamp(),
    ...extra,
  });

  test('W1 an admin can add a valid domain', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(
      admin.doc('allowed_domains/united.com').set(entry('united.com')));
  });

  test('W2 a non-admin cannot add one', async () => {
    const db = asUser(EXISTING, 'old@timer.com');
    await assertFails(db.doc('allowed_domains/united.com').set(entry('united.com')));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(anon.doc('allowed_domains/united.com').set(entry('united.com')));
  });

  test('W3 rejects ids that would make the gate a no-op or never match', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    for (const bad of [
      'DELTA.COM',      // uppercase — would never match the lowercased token
      '*.delta.com',    // wildcards are not supported by signupDomainAllowed()
      'com',            // single label
      '-delta.com',
      'delta.com-',
      'delta..com',
      'a.b',            // under the 4-char floor
    ]) {
      await assertFails(admin.doc(`allowed_domains/${bad}`).set(entry(bad)));
    }
  });

  test('W4 rejects a domain field that disagrees with the document id', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(
      admin.doc('allowed_domains/united.com').set(entry('delta.com')));
  });

  test('W5 rejects forged provenance', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(admin.doc('allowed_domains/united.com')
      .set(entry('united.com', { addedBy: 'someone-else' })));
    // addedAt must be the server's clock, not the client's.
    await assertFails(admin.doc('allowed_domains/united.com')
      .set({ ...entry('united.com'), addedAt: new Date() }));
  });

  test('W6 rejects unknown fields and missing required ones', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(admin.doc('allowed_domains/united.com')
      .set(entry('united.com', { backdoor: true })));
    await assertFails(admin.doc('allowed_domains/united.com')
      .set({ domain: 'united.com', enabled: true }));
  });

  test('W7 an admin can soft-delete by flipping enabled', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertSucceeds(admin.doc('allowed_domains/delta.com').update({
      enabled: false, updatedBy: ADMIN, updatedAt: serverTimestamp(),
    }));
  });

  test('W8 provenance is immutable', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(admin.doc('allowed_domains/delta.com').update({
      addedBy: 'someone-else', updatedBy: ADMIN, updatedAt: serverTimestamp(),
    }));
    await assertFails(admin.doc('allowed_domains/delta.com').update({
      domain: 'hijacked.com', updatedBy: ADMIN, updatedAt: serverTimestamp(),
    }));
  });

  test('W9 hard delete is refused even for an admin', async () => {
    const admin = testEnv.authenticatedContext(ADMIN).firestore();
    await assertFails(admin.doc('allowed_domains/delta.com').delete());
  });
});

// ── E: grandfathering ─────────────────────────────────────────────────
describe('existing users are grandfathered', () => {
  test('E1 an existing user on an unlisted domain can still update their profile', async () => {
    const db = asUser(EXISTING, 'old@timer.com');
    await assertSucceeds(db.doc(`users/${EXISTING}`).update({ bio: 'still here' }));
  });

  test('E2 an existing user on an unlisted domain can still read', async () => {
    const db = asUser(EXISTING, 'old@timer.com');
    await assertSucceeds(db.doc(`users/${ADMIN}`).get());
  });

  test('E3 an existing user can still delete their own account', async () => {
    // Play and the App Store both require this; the gate must not break it.
    const db = asUser(EXISTING, 'old@timer.com');
    await assertSucceeds(db.doc(`users/${EXISTING}`).delete());
  });

  test('E4 removing a domain does not retroactively lock anyone out', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('allowed_domains/delta.com')
        .set({ domain: 'delta.com', enabled: false, addedBy: ADMIN, addedAt: new Date() });
    });
    const db = asUser(EXISTING, 'crew@delta.com');
    await assertSucceeds(db.doc(`users/${EXISTING}`).update({ bio: 'unaffected' }));
  });
});
