import * as admin from 'firebase-admin';

/**
 * Runs against the real (emulated) Firestore + Functions emulators started by
 * `firebase emulators:exec` (see package.json's `test:integration` script) —
 * NOT the mocked-Admin-SDK unit tests in src/**\/__tests__. This is the layer
 * that catches a wrong collection path or field-name typo, which the mocked
 * unit tests structurally cannot (they'd happily mock a call to the wrong path).
 *
 * `emulators:exec` sets FIRESTORE_EMULATOR_HOST and GCLOUD_PROJECT in the
 * child process it spawns — no explicit host/port wiring needed here.
 */
if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-flyconnect-test' });
}

export const db = admin.firestore();

/** Polls until `check` resolves truthy, or throws after `timeoutMs` — Firestore triggers fire asynchronously. */
export async function waitFor<T>(
  check: () => Promise<T | null | undefined | false>,
  { timeoutMs = 10000, intervalMs = 250 }: { timeoutMs?: number; intervalMs?: number } = {},
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const result = await check();
    if (result) return result;
    if (Date.now() > deadline) throw new Error(`waitFor() timed out after ${timeoutMs}ms`);
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}

let counter = 0;
/** A per-test-run-unique id suffix so parallel/sequential tests never collide on deterministic notification ids. */
export function uniq(prefix: string): string {
  counter += 1;
  return `${prefix}-${Date.now()}-${counter}`;
}
