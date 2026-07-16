#!/usr/bin/env node
/**
 * One-time migration for QA finding H-2 (docs/QA_AUDIT_REPORT.md).
 *
 * Moves `email`, `phone`, `fcmToken`, `dob`, `ageVerifiedAt` off every
 * `users/{uid}` doc (readable by ANY signed-in user per firestore.rules)
 * into the new owner-only `users/{uid}/private/data` subdoc. The app code
 * and firestore.rules already treat that as the source of truth going
 * forward (see AuthProvider._fetchSelfWithPrivate in
 * lib/shared/providers/real_providers.dart) — this script just catches up
 * every user record that was written *before* that change shipped.
 *
 * SAFE BY DEFAULT: runs in --dry-run mode unless you pass --live.
 * IDEMPOTENT: only touches docs that still have one of the PII fields on
 * the main doc; already-migrated docs are skipped automatically, so it's
 * safe to re-run (e.g. after fixing a transient error).
 * NEVER PRINTS PII: logs uids and field *names* touched, never the actual
 * email/phone/dob/token values.
 *
 * Setup:
 *   cd scripts/migrate-pii-to-private
 *   npm install
 *   Download a service-account key for the flyconnect-ab4f2 project
 *   (Firebase Console → Project Settings → Service Accounts → Generate
 *   new private key) and point GOOGLE_APPLICATION_CREDENTIALS at it.
 *
 * Usage:
 *   # 1. Preview what would change — writes nothing.
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node migrate-pii-to-private.js
 *
 *   # 2. Try it against a single known account first.
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node migrate-pii-to-private.js --uid=SOME_UID --live
 *
 *   # 3. Run for real, once you're satisfied with the dry run.
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node migrate-pii-to-private.js --live
 */

const admin = require('firebase-admin');

const PII_FIELDS = ['email', 'phone', 'fcmToken', 'dob', 'ageVerifiedAt'];
const PAGE_SIZE = 200; // users fetched per Firestore page while scanning

function parseArgs(argv) {
  const args = { live: false, uid: null, project: null };
  for (const arg of argv.slice(2)) {
    if (arg === '--live') args.live = true;
    else if (arg.startsWith('--uid=')) args.uid = arg.slice('--uid='.length);
    else if (arg.startsWith('--project=')) args.project = arg.slice('--project='.length);
    else {
      console.error(`Unknown argument: ${arg}`);
      process.exit(1);
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);

  admin.initializeApp(args.project ? { projectId: args.project } : {});
  const db = admin.firestore();

  console.log(`Project: ${admin.app().options.projectId || args.project || '(resolved from service account credentials)'}`);
  console.log(args.live ? '*** LIVE RUN — this will write and delete data. ***' : 'Dry run (no writes). Pass --live to actually migrate.');
  if (args.uid) console.log(`Scoped to single uid: ${args.uid}`);
  console.log('');

  let scanned = 0, migrated = 0, skipped = 0, failed = 0;
  const failures = [];

  if (args.uid) {
    const result = await migrateOne(db, args.uid, args.live);
    scanned = 1;
    if (result === 'migrated') migrated = 1;
    else if (result === 'skipped') skipped = 1;
    else { failed = 1; failures.push({ uid: args.uid, error: result }); }
  } else {
    let query = db.collection('users').orderBy('__name__').limit(PAGE_SIZE);
    let lastDoc = null;

    while (true) {
      const pageQuery = lastDoc ? query.startAfter(lastDoc) : query;
      const snap = await pageQuery.get();
      if (snap.empty) break;

      for (const doc of snap.docs) {
        scanned++;
        const result = await migrateOne(db, doc.id, args.live, doc.data());
        if (result === 'migrated') migrated++;
        else if (result === 'skipped') skipped++;
        else { failed++; failures.push({ uid: doc.id, error: result }); }
        if (scanned % 50 === 0) console.log(`  ...scanned ${scanned}`);
      }

      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.docs.length < PAGE_SIZE) break;
    }
  }

  console.log('');
  console.log('── Summary ──────────────────────────────');
  console.log(`Scanned:  ${scanned}`);
  console.log(`Migrated: ${migrated}`);
  console.log(`Skipped (already clean): ${skipped}`);
  console.log(`Failed:   ${failed}`);
  if (failures.length) {
    console.log('\nFailures (uid + error, no PII):');
    for (const f of failures) console.log(`  ${f.uid}: ${f.error}`);
  }
  if (!args.live && migrated + skipped > 0) {
    console.log('\nThis was a dry run — nothing was written. Re-run with --live to apply.');
  }
}

/**
 * Migrates a single user doc. Returns 'migrated', 'skipped', or an error
 * string. `data` is optional — if omitted (single-uid mode) the doc is
 * fetched fresh.
 */
async function migrateOne(db, uid, live, data) {
  try {
    const userRef = db.collection('users').doc(uid);
    if (!data) {
      const snap = await userRef.get();
      if (!snap.exists) return 'no such user doc';
      data = snap.data();
    }

    const presentFields = PII_FIELDS.filter((f) => Object.prototype.hasOwnProperty.call(data, f));
    if (presentFields.length === 0) return 'skipped';

    console.log(`${live ? '[migrate]' : '[dry-run]'} ${uid}: moving ${presentFields.join(', ')} -> private/data`);
    if (!live) return 'migrated'; // counted as "would migrate" in dry-run

    const privateData = {};
    for (const f of presentFields) privateData[f] = data[f];

    const batch = db.batch();
    batch.set(userRef.collection('private').doc('data'), privateData, { merge: true });
    const deletes = {};
    for (const f of presentFields) deletes[f] = admin.firestore.FieldValue.delete();
    batch.update(userRef, deletes);
    await batch.commit();

    return 'migrated';
  } catch (e) {
    return e.message || String(e);
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('Migration failed:', e);
  process.exit(1);
});
