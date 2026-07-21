#!/usr/bin/env node
/**
 * Backfill `audience: 'Everyone'` onto every post that predates the field.
 *
 * WHY THIS IS MANDATORY
 * ---------------------
 * The posts read rule (firestore.rules) admits a document only when
 * `resource.data.audience == 'Everyone'`, the reader is the author, or the
 * reader is an admin. A post written before the field existed has no
 * `audience`, so the first condition is false and the post becomes invisible
 * to everyone except its author.
 *
 * Run this BEFORE deploying the new rules, not after:
 *
 *   1. node scripts/backfill-post-audience.js --dry-run     # inspect
 *   2. node scripts/backfill-post-audience.js               # apply
 *   3. firebase deploy --only firestore:rules,firestore:indexes
 *
 * Auth: uses Application Default Credentials. Either
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 * or run `gcloud auth application-default login` first.
 *
 * Safe to re-run: only documents genuinely missing the field are written.
 */
'use strict';

const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'flyconnect-ab4f2';
const BATCH_SIZE = 400; // Firestore caps a batch at 500 writes.

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function main() {
  console.log(
    `${DRY_RUN ? '[dry-run] ' : ''}Backfilling posts.audience on "${PROJECT_ID}"`
  );

  let scanned = 0;
  let needing = 0;
  let written = 0;
  let cursor = null;

  // Paginate by document id so the scan is stable and resumable, rather than
  // holding every post in memory at once.
  for (;;) {
    let q = db.collection('posts').orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    const stale = snap.docs.filter((d) => d.get('audience') === undefined);
    scanned += snap.size;
    needing += stale.length;

    if (stale.length && !DRY_RUN) {
      const batch = db.batch();
      for (const doc of stale) {
        batch.update(doc.ref, { audience: 'Everyone' });
      }
      await batch.commit();
      written += stale.length;
    }

    process.stdout.write(
      `\r  scanned ${scanned}  missing ${needing}  written ${written}`
    );

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < BATCH_SIZE) break;
  }

  console.log('\nDone.');
  console.log(`  posts scanned:            ${scanned}`);
  console.log(`  missing audience:         ${needing}`);
  console.log(
    DRY_RUN
      ? '  written:                  0 (dry run — re-run without --dry-run to apply)'
      : `  written:                  ${written}`
  );

  if (!DRY_RUN && needing > 0) {
    console.log('\nNow deploy the rules:');
    console.log('  firebase deploy --only firestore:rules,firestore:indexes');
  }
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error('\nBackfill failed:', err);
    process.exit(1);
  }
);
