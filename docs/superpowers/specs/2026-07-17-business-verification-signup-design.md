# Business Verification Signup Gap — Design

**Date:** 2026-07-17
**Status:** Approved for planning
**Related:** M-3 (`docs/QA_AUDIT_REPORT.md`), `docs/business-user-flow-test-plan.md` §2 row 13

## Problem

`admin_business_verification_page.dart` is fully built to review business
applications — it reads `ein`, `licenseNumber`, `verificationDocs`, and
`verificationStatus` off each business's user doc, and filters into
Pending/Verified/Rejected tabs. But nothing in the app ever writes those
fields. Signup only ever sets `role: 'business'`, so every business lands
with no `verificationStatus` at all (the admin page's own fallback treats
this as `'none'`, not `'pending'`). The admin's Pending queue is permanently
empty no matter how many businesses sign up — it can only be exercised with
hand-seeded test data.

Separately, while reading the `/users/{userId}` Firestore rule to plan this
fix, found: the `create` rule only validates `role` and `isBanned` — nothing
stops a client from setting `isVerified: true` (or `verificationStatus:
'verified'`) in the same write that creates the account, which would fully
bypass M-3's admin-approval gate. This is fixed as part of the same rule
edit below since it's the exact rule this change touches.

## Explicit scope boundaries

Two things were considered and **cut** from this change (raised and declined
during brainstorming):

- **Document upload** (photo of business license, etc.) — the admin card
  shows a "No documents submitted" warning when `verificationDocs` is empty,
  but treats it as advisory, not a block on approval. Out of scope; a
  follow-up ticket if the business ever wants to enforce document review.
- **Resubmission flow for existing businesses** — today, if admin rejects or
  requests more info, there's no in-app place for that business to see the
  status or resubmit. Out of scope; this change only fixes new signups.

## Design

### 1. Data model

No `UserModel` changes. `AuthProvider.signup()` gains two new optional
params: `String? ein, String? licenseNumber`. These follow the function's
existing convention exactly — `dob` is already a raw param that only reaches
the private subdoc, and `termsAcceptedAt` is already added directly to the
main-doc write map without being a model field:

- `ein` / `licenseNumber` → written into `users/{uid}/private/data`
  (alongside `email`/`phone`/`dob`), never onto the broadly-readable main
  doc.
- `verificationStatus: 'pending'` → added directly to `docData` (the main
  doc write), only when `role == 'business'`. Plain user signups get no
  `verificationStatus` field, matching today's behavior.

### 2. Signup UI (`signup_screen.dart`)

Two new optional text fields in the existing business step (alongside
Business Name / Category / Website / Bio): "EIN" and "License Number".
Both optional. No strict format validation in v1 (a US-style EIN regex
would incorrectly block legitimate non-US businesses; this app has no
stated US-only scope) — the exact validation strictness is called out in
the implementation plan as a judgment call rather than decided here.

### 3. Firestore rules (`firestore.rules`, `/users/{userId}` create)

```
allow create: if isOwner(userId)
  && request.resource.data.role in ['user', 'business']
  && request.resource.data.isBanned == false
  && request.resource.data.isVerified == false
  && (!('verificationStatus' in request.resource.data)
      || request.resource.data.verificationStatus in ['none', 'pending']);
```

No change to `private/{docId}` — already owner-write-only with no field
allowlist, so `ein`/`licenseNumber` are automatically covered.

### 4. Admin page (`admin_business_verification_page.dart`)

`_fetchBusinesses()` gets one extra read per business row —
`users/{id}/private/data` — merged into the existing raw map before
`_filteredBusinesses`/`_buildBusinessCard` see it. Mirrors the pattern
already used in `admin_users_page.dart` for the same email/phone situation
(one extra read per row, accepted precedent in this codebase). No UI
changes needed — the card already conditionally renders `ein`/
`licenseNumber` when present.

### 5. Testing

- Extend `test/widgets/signup_screen_test.dart`: EIN/License fields render
  only for the business role step; `signup()` is called with them when
  filled in.
- New/extended `AuthProvider` test: business signup writes
  `verificationStatus: 'pending'` to the main doc and `ein`/`licenseNumber`
  to the private subdoc; user signup writes neither.
- New `test/features/admin_business_verification_page_test.dart`: a pending
  business (with private EIN/license) surfaces under the "Pending" filter
  with those values displayed.
- No automated Firestore-rules test harness exists in this repo (a known
  gap noted in the QA audit's L-3 entry). Validate the new create-rule
  clause via the `firebase_validate_security_rules` MCP tool plus manual
  reasoning — the same process used to validate M-3's original rule.

## Out of scope (explicitly deferred, not forgotten)

- Document upload at signup.
- In-app resubmission flow for rejected / info-requested businesses.
- Any change to `isVerifiedBusiness()`'s actual authorization logic — this
  change only makes the *Pending queue* reachable; the real capability gate
  (`isVerified == true`, set only by admin approval) is unchanged.
