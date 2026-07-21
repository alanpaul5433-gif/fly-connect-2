# Business ↔ User Flow — Test Plan

**Scope:** every Business-role feature (dashboard, deals, events, groups, analytics, profile) and how business actions reflect into the regular crew-facing app.
**Companion to:** `docs/QA_AUDIT_REPORT.md` (overall readiness) and `docs/manual-smoke-test.md` (release smoke script — see its new §19 "Business Dashboard Walkthrough").
**Status:** all 5 Critical/High bugs below are **fixed** (code + 22 new automated tests, `flutter analyze` clean, 352/352 Flutter tests + 68/68 Cloud Functions tests passing). Both reflection gaps (organizer/verified-badge surfacing, business-content notification fan-out) are **implemented**.

---

## 1. Architecture note

There is no `BusinessModel` — a business is a `UserModel` with `role == 'business'` plus an admin-controlled `isVerified` bool. All three creation screens (`create_promotion_screen.dart`, `create_event_screen.dart`, `create_group_screen.dart`) independently gate on `role=='business' && !isVerified` client-side; `firestore.rules`'s `isVerifiedBusiness()` enforces the same rule server-side (M-3). Test accounts (see `real_providers.dart`'s mock-credentials table, usable with `isMock:true`):

| Account | Role | Verified | Purpose |
|---|---|:---:|---|
| `business@flyconnect.com` / `business123` | business | ✅ | Sky Lounge NYC — primary business test account |
| `emirates@flyconnect.com` / `emirates123` | business | ✅ | Emirates Business Lounge — second business, for cross-tenant tests |
| `newbiz@flyconnect.com` / `newbiz123` | business | ❌ | **New** — added to exercise the pending-verification gate, which no mock account could previously reach |
| `user@flyconnect.com` / `user123` | user | — | Plain crew account |

---

## 2. Per-feature test matrix

Each of the 14 business screens/actions gets: Happy Path / Unverified-Business Block / Non-Business-Role Block, plus a regression case where a bug was found.

| # | Feature | File | Cases |
|---|---|---|---|
| 1 | Dashboard shell + role-gated nav | `business_shell.dart`, `app_router.dart` | Non-business deep-link to `/dashboard`, `/promotions`, `/business-events`, `/promotions/create`, `/analytics`, `/business-profile` → redirected home (**A5**, `test/routing/business_route_guards_test.dart` — see §4) |
| 2 | Create Deal | `create_promotion_screen.dart` | Happy path (verified); unverified → snackbar, no write; **A1 regression**: verified business cannot force `isApproved:true`/`isActive:true` on create (rules-level, see §4) |
| 3 | Crew Deals list (own) | `promotions_screen.dart` | **A3 regression**: Business A's Active/Expired tabs show only Business A's promotions, never Business B's |
| 4 | Promotion detail + analytics | `promotion_detail_screen.dart` | Existing coverage: `test/features/promotion_detail_access_test.dart` (owner/crew/admin/signed-out access gating) — unchanged |
| 5 | Create Event | `create_event_screen.dart` | Happy path; unverified block; **A2 regression**: event stays out of the public feed until admin-approved (see §4) |
| 6 | Business Events list (own) | `business_events_screen.dart` | **A3 regression**: same cross-tenant scoping as #3, for events |
| 7 | Event Management (edit/approve/decline/remove/broadcast) | `event_management_screen.dart` | **A4 regression**: non-owner sees a permission-denied screen, not the roster (`test/features/event_management_screen_test.dart`); approve/decline failure now shows an error toast |
| 8 | Create Group | `create_group_screen.dart` | Happy path; unverified block — existing coverage |
| 9 | Group Management | `group_management_screen.dart` | Existing coverage (`_canManage` guard was already correct — this is the pattern A4 now mirrors) |
| 10 | Analytics | `analytics_screen.dart` | `followerCount` and Deal/Event lists are real; growth/reach/bar-chart are hardcoded demo constants (labeled "Demo chart" in the UI) — **not a bug**, don't mistake for live data in a screenshot or demo |
| 11 | Business Profile (owner) | `business_profile_screen.dart` | Verified badge now uses the shared `VerifiedBadge` widget; **known limitation** — Followers/Events/Groups stats and the Follow button remain hardcoded/non-persisting (out of scope for this pass, not one of the 5 fixed bugs) |
| 12 | Route guards | `app_router.dart` | See #1 — **A5** |
| 13 | Admin verification/promotion/event moderation | `admin_business_verification_page.dart`, `admin_promotions_page.dart`, `admin_events_page.dart` | Existing coverage; **known gap** — no in-app flow ever writes `verificationStatus`/`ein`/`licenseNumber` (signup never sets them), so the admin "Pending" queue can't be reached organically. Out of scope for this pass — flagged for a future ticket |
| 14 | Signup → business role selection | `signup_screen.dart` | Existing coverage |

---

## 3. Business → User Reflection

How business actions surface in the regular crew-facing app — the original motivating question for this test plan.

| Content type | Business action | Where it surfaces to users | Status |
|---|---|---|---|
| Promotion | Create → admin approves | Home feed "Crew Deals" rail, `/offers` browse screen, detail screen | ✅ Working. **New:** followers of the business get a notification once approved (B2) |
| Event | Create → admin approves (now actually gates visibility, A2) | `events_screen.dart` list, `event_details_screen.dart` detail | ✅ Now shows a "Hosted by [name] [✓ if verified]" row (B1), tappable to the organizer's profile. Followers get a notification once approved (B2) |
| Group | Create (no approval concept) | `groups_screen.dart` list, `group_details_screen.dart` detail | ✅ Now shows the same "Hosted by" row (B1). Followers get a notification on create (B2) |
| Profile | A user taps a business's name (post author, event/group organizer, search result) | Routes to `/users/:userId` → `profile_screen.dart` | ✅ Now role-aware — shows a `VerifiedBadge` next to the name and a business pill instead of "airline · position" for `role=='business'`. Previously this route showed a completely generic layout with zero indication the account was a business at all — the purpose-built `business_profile_screen.dart` (which *did* show a badge) was only ever reachable by the business itself |

### Regression tests added

- `test/features/event_details_screen_test.dart` (new file, 3 tests) — organizer row + verified badge
- `test/features/group_details_screen_test.dart` (extended, +2 tests) — same, for groups
- `test/features/profile_screen_test.dart` (new file, 2 tests) — role-aware header, own-profile path only (see limitation below)
- `functions/src/producers/__tests__/businessContent.test.ts` (new file, 10 tests) — the 3 new fan-out producers
- `functions/src/lib/__tests__/rateLimit.test.ts` (new file, 5 tests) — cooldown logic
- `functions/src/__tests__/pushFanout.test.ts` (extended, +2 tests) — `group`/`promotion` push payloads
- `test/services/notification_route_test.dart` (extended, +2 tests) — `promotion`/`new_promotion` deep-link resolution

**Known test-harness limitation:** the third-party profile view (`ProfileScreen(isOwner:false)`) calls raw `FirebaseFirestore.instance` inside `_checkBlockedRelationship` with no mocked plugin channel — same pre-existing limitation documented in `event_management_screen_test.dart`'s `_settle` helper for `_loadAttendees`. That path is covered by the manual walkthrough (`docs/manual-smoke-test.md` §19) instead of an automated widget test.

---

## 4. Bugs found and fixed

| ID | Severity | Description | Fix |
|---|:---:|---|---|
| **A1** | 🔴 Critical | A verified business could set `isApproved:true`/`isActive:true` directly on a promotion create, bypassing admin moderation entirely — the client always sent `false`/`false`, but `firestore.rules` never enforced it. | `firestore.rules`: `promotions` create rule now requires `isApproved==false && isActive==false` unless the writer is an admin. |
| **A2** | 🔴 Critical | Events were visible to all users immediately on creation regardless of `isApproved` — the admin "Pending" queue never actually gated the public feed. | Added `EventProvider.visibleEvents` (approved-only, for `events_screen.dart`) and `EventProvider.myEvents(uid)` (ownership-only, so a business still sees its own pending event). |
| **A3** | 🟠 High | Cross-tenant data leak: a business's own "Crew Deals"/"Events" dashboard tabs showed every business's content, not just their own — including a "Manage" button into a competitor's event. | Added `PromotionProvider.myPromotions(uid)` / `EventProvider.myEvents(uid)`; `promotions_screen.dart` and `business_events_screen.dart` now scope to the logged-in business. |
| **A4** | 🔴 Critical | `EventManagementScreen` had no ownership guard (unlike `GroupManagementScreen`'s `_canManage`), and the `rsvps/{userId}` read rule was a blanket `allow read: if isAuth()` — a non-owner business could view a competitor's full attendee roster (name, airline, position). Approve/Decline also silently reverted on failure with no error shown. | Added a `_canManage` guard mirroring the group screen; tightened the RSVP read rule to owner/admin/event-creator; added the missing error `SnackBar` to `_approve`/`_decline`. |
| **A5** | 🟠 High | The router's role-redirect gated `/dashboard`, `/promotions`, `/business-events` but not `/promotions/create`, `/analytics`, `/business-profile` — a plain user could deep-link into those screens (writes were still server-blocked, but the screens shouldn't render). | Added the 3 missing paths to the existing redirect condition. |

Two structurally-missing features (not bugs, but blocking the "does it reflect in the user app" question) were also built:

- **B1** — Verified badge / organizer identity: extracted a shared `VerifiedBadge` widget; `profile_screen.dart` is now role-aware; `event_details_screen.dart` / `group_details_screen.dart` resolve `createdBy` via `UserProvider.fetchUser` and show a tappable "Hosted by" row.
- **B2** — Notification fan-out: three new Cloud Functions producers (`onPromotionApproved`, `onEventApproved`, `onGroupCreated`) notify a business's followers, with a 6-hour per-business-per-type cooldown (`lib/rateLimit.ts`) so repeated posting doesn't spam. "Nearby" fan-out is explicitly out of scope for v1 (no geo-index trigger exists) — followers only.

---

## 5. Recommended follow-ups (not in this pass)

- Add the 3 new producers to the live Firestore+Functions emulator integration suite (`functions/test/integration/producers.test.ts`) — currently only unit-tested with a mocked Admin SDK.
- `business_profile_screen.dart`'s hardcoded Followers/Events/Groups stats and non-persisting Follow button (shows a hardcoded "Sky Lounge NYC" snackbar regardless of which business is viewed) — pre-existing, out of scope for this pass.
- No in-app flow ever lets a business submit verification documents (`ein`/`licenseNumber`/`verificationDocs`) — the admin verification page has nothing to review in practice. Needs its own design pass.
- Consider a `rules`-level defense-in-depth constraint on event list-reads (A2's fix is client-side/provider-level; a determined client could still query the `events` collection directly and see unapproved docs, since Firestore rules can't cheaply express "isApproved==true OR createdBy==me OR isAdmin" as a query constraint).
