#!/usr/bin/env node
/**
 * Backfill `postAuthorId` onto every posts/{postId}/{likes,comments} document
 * that predates the field.
 *
 * WHY THIS IS NEEDED
 * ------------------
 * deletePost cascades: it deletes a post's likes and comments, then the post.
 * firestore.rules now lets the post's author delete engagement they don't own,
 * but only via the denormalised `postAuthorId` field on each like/comment
 * (get() was avoided so a batch cascade doesn't hit the 20-doc-access ceiling).
 *
 * A like/comment written before this field existed has no postAuthorId, so the
 * author-delete clause can't match it. Until backfilled, deleting a post that
 * has OLD foreign engagement still fails — exactly the H13 bug, for legacy
 * data. New engagement already carries the field.
 *
 * This is NOT a deploy prerequisite: the rule only ever GRANTS delete power, so
 * shipping it before this runs breaks nothing that worked before. Run it soon
 * after, though, or old posts stay undeletable.
 *
 *   1. node scripts/backfill-engagement-post-author.js --dry-run   # inspect
 *   2. node scripts/backfill-engagement-post-author.js             # apply
 *
 * Auth: Application Default Credentials. Either
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

// Cache post authorId by postId so a hot post's many likes cost one read.
const authorCache = new Map();
async function authorOf(postId) {
  if (authorCache.has(postId)) return authorCache.get(postId);
  const snap = await db.doc(`posts/${postId}`).get();
  const author = snap.exists ? snap.get('authorId') || null : null;
  authorCache.set(postId, author);
  return author;
}

async function backfillGroup(groupName) {
  let scanned = 0;
  let written = 0;
  let orphaned = 0; // engagement whose post is gone — nothing to derive from
  let cursor = null;

  for (;;) {
    let q = db.collectionGroup(groupName)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);
    if (cursor) q = q.startAfter(cursor);

    const snap = await q.get();
    if (snap.empty) break;
    scanned += snap.size;

    const batch = db.batch();
    let pending = 0;
    for (const doc of snap.docs) {
      if (doc.get('postAuthorId') !== undefined) continue;
      const postId = doc.ref.parent.parent && doc.ref.parent.parent.id;
      const author = postId ? await authorOf(postId) : null;
      if (!author) { orphaned += 1; continue; }
      if (!DRY_RUN) { batch.update(doc.ref, { postAuthorId: author }); pending += 1; }
      written += 1;
    }
    if (!DRY_RUN && pending > 0) await batch.commit();

    process.stdout.write(
      `\r  ${groupName}: scanned ${scanned}  written ${written}  orphaned ${orphaned}`
    );
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < BATCH_SIZE) break;
  }
  console.log('');
  return { scanned, written, orphaned };
}

async function main() {
  console.log(
    `${DRY_RUN ? '[dry-run] ' : ''}Backfilling postAuthorId on likes + comments in "${PROJECT_ID}"`
  );
  const likes = await backfillGroup('likes');
  const comments = await backfillGroup('comments');
  console.log('\nDone.');
  console.log(`  likes    — written ${likes.written}, orphaned ${likes.orphaned}`);
  console.log(`  comments — written ${comments.written}, orphaned ${comments.orphaned}`);
  if (likes.orphaned + comments.orphaned > 0) {
    console.log(
      '\n  Orphaned engagement (post already deleted) was left as-is — its post ' +
      'is gone, so there is no author to derive and nothing to delete against.');
  }
}

main().then(
  () => process.exit(0),
  (err) => { console.error('\nBackfill failed:', err); process.exit(1); }
);
