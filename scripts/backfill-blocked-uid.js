#!/usr/bin/env node
/**
 * Backfill `blockedUid` onto every users/{uid}/blocked/{blockedId} document
 * that predates the field.
 *
 * WHY THIS IS NEEDED
 * ------------------
 * Block documents originally stored only `{blockedAt}` — the blocked user's
 * uid existed solely as the DOCUMENT ID. That is unqueryable in the direction
 * we need: hiding people who blocked *me* requires
 *
 *   collectionGroup('blocked').where('blockedUid', '==', myUid)
 *
 * and a collection group query cannot filter on document ids (documentId()
 * there is compared against a full document path, so passing a bare uid throws
 * rather than returning nothing). firestore.rules also keys its "you may read a
 * block document that names you" allowance off this same field.
 *
 * Until a document is backfilled, the block still works in the direction that
 * matters most — the blocker's own feed, matches and Nearby filter it out by
 * document id — but the blocked user is not hidden from the blocker's view of
 * them. The gap fails toward *under*-hiding, never toward exposing a list.
 *
 * Unlike the posts backfill, this is not a prerequisite for deploying the
 * rules: the new rule only ever grants reads, so shipping it before this runs
 * breaks nothing. Run it soon after, though, or old blocks stay half-enforced.
 *
 *   1. node scripts/backfill-blocked-uid.js --dry-run     # inspect
 *   2. node scripts/backfill-blocked-uid.js               # apply
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
    `${DRY_RUN ? '[dry-run] ' : ''}Backfilling blocked.blockedUid on "${PROJECT_ID}"`
  );

  let scanned = 0;
  let needing = 0;
  let written = 0;
  let mismatched = 0;
  let cursor = null;

  // A collectionGroup scan reaches every user's block list without first
  // enumerating users. Ordering by __name__ keeps it stable and resumable
  // rather than holding the whole collection group in memory.
  for (;;) {
    let q = db.collectionGroup('blocked')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;

    scanned += snap.size;
    const stale = [];
    for (const doc of snap.docs) {
      const existing = doc.get('blockedUid');
      if (existing === undefined) {
        stale.push(doc);
      } else if (existing !== doc.id) {
        // Should never happen: blockUser writes the id and the field together.
        // Report rather than "fix" it — a mismatch means an assumption broke
        // somewhere, and overwriting would destroy the evidence.
        mismatched += 1;
        console.warn(
          `\n  WARNING: ${doc.ref.path} has blockedUid="${existing}" but id "${doc.id}" — left untouched`
        );
      }
    }
    needing += stale.length;

    if (stale.length && !DRY_RUN) {
      const batch = db.batch();
      for (const doc of stale) {
        // The document id IS the blocked uid — that is the whole reason this
        // backfill can be derived rather than reconstructed from elsewhere.
        batch.update(doc.ref, { blockedUid: doc.id });
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
  console.log(`  block docs scanned:       ${scanned}`);
  console.log(`  missing blockedUid:       ${needing}`);
  console.log(
    DRY_RUN
      ? '  written:                  0 (dry run — re-run without --dry-run to apply)'
      : `  written:                  ${written}`
  );
  if (mismatched > 0) {
    console.log(`  id/field mismatches:      ${mismatched}  <-- investigate`);
  }
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error('\nBackfill failed:', err);
    process.exit(1);
  }
);
