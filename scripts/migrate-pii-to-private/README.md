# migrate-pii-to-private

One-time backfill for QA finding **H-2** (`docs/QA_AUDIT_REPORT.md`). The app
code now writes `email`/`phone`/`fcmToken`/`dob`/`ageVerifiedAt` to the
owner-only `users/{uid}/private/data` subdoc instead of the widely-readable
`users/{uid}` doc, but that only applies to *new* writes. This script moves
those fields for every *existing* user record already in production.

## Before you run this

- It mutates every user document in the target Firestore project. **Run the
  dry run first and read the output.**
- It needs a service-account key with Firestore admin access — this is a
  privileged credential, treat it like any other production secret (don't
  commit it, delete it when you're done).
- It never prints actual PII values (email addresses, phone numbers, DOBs,
  tokens) to the console — only uids and which field *names* were touched.

## Setup

```bash
cd scripts/migrate-pii-to-private
npm install
```

Download a service-account key for the `flyconnect-ab4f2` project: Firebase
Console → Project Settings → Service Accounts → Generate new private key.

## Usage

```bash
# 1. Dry run — reports what WOULD change, writes nothing.
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node migrate-pii-to-private.js

# 2. Try it against one known account first.
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node migrate-pii-to-private.js --uid=SOME_UID --live

# 3. Run for real, once the dry run output looks right.
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node migrate-pii-to-private.js --live
```

Flags:
- `--live` — actually write/delete. Omit for a safe dry run.
- `--uid=<uid>` — only touch one user (useful for a spot check before the
  full run).
- `--project=<id>` — override the project id if it isn't picked up from your
  credentials automatically.

## What it does per user

1. Reads `users/{uid}`.
2. If any of `email`/`phone`/`fcmToken`/`dob`/`ageVerifiedAt` are present on
   that doc, copies just those fields into `users/{uid}/private/data`
   (merge — won't clobber anything already migrated there).
3. Deletes those same fields from the main `users/{uid}` doc.
4. Everything else on the doc (name, bio, airline, counts, `settings`, etc.)
   is untouched.

It's idempotent — a user with no PII fields left on the main doc is skipped,
so re-running after fixing a transient error only touches what's left.

## After running

- Delete the service-account key file if you downloaded one just for this.
- Once you're confident the backfill is complete, deploy `firestore.rules`
  (tracked separately as C-1/H-2 in the QA report) so the new restriction is
  actually enforced in production.
