import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { db } from './lib/firestore';

/**
 * H20 (real growth): a business's Growth % needs a follower time-series, which
 * we don't keep. This snapshots each business's followerCount daily into
 * `users/{uid}/dailyStats/{yyyy-mm-dd}`, so the analytics screen can compute a
 * real "today vs 30 days ago" figure. Until it accrues history, growth reads
 * empty rather than fabricated.
 */

/** UTC yyyy-mm-dd — the snapshot document id, stable and sortable. */
export function statsDocId(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Growth as a fraction (0.10 = +10%) from a baseline to the current value.
 * Returns null when there's no usable baseline — the caller shows "—", never a
 * fabricated number.
 */
export function growthFraction(current: number, baseline: number | null): number | null {
  if (baseline === null || baseline <= 0) return null;
  return (current - baseline) / baseline;
}

const BATCH_LIMIT = 400;

/** Daily at 03:00 UTC: snapshot every business's followerCount. */
export const snapshotBusinessStats = onSchedule(
  { schedule: '0 3 * * *', timeZone: 'UTC', maxInstances: 1 },
  async () => {
    const today = statsDocId(new Date());
    const businesses = await db.collection('users').where('role', '==', 'business').get();

    let written = 0;
    let batch = db.batch();
    let pending = 0;
    for (const doc of businesses.docs) {
      const followerCount = (doc.get('followerCount') as number | undefined) ?? 0;
      batch.set(
        doc.ref.collection('dailyStats').doc(today),
        { followerCount, at: new Date() },
      );
      written += 1;
      if (++pending >= BATCH_LIMIT) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
    logger.info(`snapshotBusinessStats: wrote ${written} business stats for ${today}`);
  },
);
