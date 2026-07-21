# Manual Smoke Test — Android

**Purpose:** verify that a signed release build works end-to-end on a real Android device before promoting to any testing track.

**Prerequisites:**
- Signed release AAB/APK installed on device (see `docs/release-build-guide.md`)
- Physical Android phone (Pixel or equivalent) with Android 13 or higher
- Wi-Fi connection
- Test account credentials:
  - Crew: `alex@delta.com` / `Test1234!`
  - Business: `info@skyloungelnyc.com` / `Test1234!`
  - Admin: `alan123@gmail.com` / `Admin@1234`

**How to use:** work through each section in order. Check the box on pass. If any step fails, stop, log the issue, do not promote the build.

---

## 1. First-run experience

- [ ] 1.1 App icon appears on home screen with the name "FlyConnect" (not "flyconnect" lowercase)
- [ ] 1.2 App launches to splash screen
- [ ] 1.3 Splash transitions to login screen within 3 seconds
- [ ] 1.4 No "flutter logo" or debug banner visible

## 2. Permissions (Android 13+)

- [ ] 2.1 On first post-create, camera permission prompt appears with clear "Allow" / "Don't allow"
- [ ] 2.2 On permission denial, app does not crash and shows a message
- [ ] 2.3 On first chat, notification permission prompt appears
- [ ] 2.4 On first Nearby visit, location permission prompt appears
- [ ] 2.5 Each permission respects system "Ask every time" setting

## 3. Authentication

### 3.1 Signup
- [ ] Tap "Sign up" → signup screen appears
- [ ] Trying to continue without filling fields → toast "Please fill in all required fields"
- [ ] Enter invalid email → toast "Please enter a valid email address"
- [ ] Enter password < 8 chars → toast "Password must be at least 8 characters"
- [ ] Fill valid info but NOT tick Terms checkbox → toast "Please agree to the Terms of Service and Privacy Policy"
- [ ] Tick Terms → "Continue" advances to step 2
- [ ] Complete signup → lands on home feed

### 3.2 Login
- [ ] Enter invalid email format → inline error
- [ ] Enter wrong password → Firebase error shown gracefully (not a crash)
- [ ] Login with seeded `alex@delta.com` → lands on home feed
- [ ] Login as `info@skyloungelnyc.com` → lands on business dashboard (`/dashboard`)
- [ ] Login as `alan123@gmail.com` → lands on admin dashboard (`/admin/dashboard`)

### 3.3 Google Sign-In
- [ ] Tap "G" button on login → Google account picker appears
- [ ] Select an account → returns to app authenticated
- [ ] Fresh Google account → Firestore user doc auto-created with role="user"

### 3.4 Forgot password
- [ ] Tap "Forgot password?" → forgot password screen
- [ ] Empty email → inline error
- [ ] Unknown email → "User not found" error from Firebase
- [ ] Known email → "Check your email" success state
- [ ] Real email actually receives a password-reset email within 1 minute

### 3.5 Logout
- [ ] Tap Logout in drawer → confirmation dialog appears
- [ ] Tap Cancel → nothing happens (stays logged in)
- [ ] Tap Sign out → returns to login screen
- [ ] After logout, pressing back does not return to home

### 3.6 Account deletion (critical — Play Store requirement)
- [ ] Settings → Delete Account → typed dialog appears
- [ ] Without typing "DELETE" → delete button is disabled
- [ ] Type "DELETE" → button enables
- [ ] Tap Delete permanently → loading spinner → success toast → routes to login
- [ ] Try to log back in with same credentials → fails ("User not found")
- [ ] Check Firebase Console: user no longer in Auth, user doc gone from Firestore

## 4. Home feed

- [ ] Posts load within 2 seconds
- [ ] Scrolling is smooth (no jank)
- [ ] Pull-to-refresh triggers a reload
- [ ] Filter chips ("Feed", "Deals", "Groups", "Events", "Matches") navigate correctly
- [ ] "Your Story" + "Nearby" appear at the top
- [ ] Crew Deals horizontal strip appears with real promotions
- [ ] Tapping a post opens details screen
- [ ] Like button toggles and persists after reopening the post
- [ ] Bookmark button toggles and persists
- [ ] Share button copies link to clipboard (paste in notes app to confirm)
- [ ] Options menu → Report post → reason sheet → select → toast "Report submitted"

## 5. Create post

- [ ] Tap compose icon → create post screen
- [ ] Empty submit → button is disabled or does nothing
- [ ] Add caption only → publishes
- [ ] Add photo from gallery → thumbnail appears
- [ ] Add photo from camera → thumbnail appears
- [ ] Change audience to "Only me" → saved with that audience
- [ ] Select a group → post appears in that group's feed
- [ ] Share → returns to feed → new post appears at top

## 6. Chat

- [ ] Chat tab loads DM list
- [ ] Tap a conversation → messages load
- [ ] Typing indicator shows "Online" / "typing…"
- [ ] Send message → appears immediately
- [ ] Call button → "Voice calls coming soon" sheet
- [ ] More menu → Mute shows coming-soon message (honest)
- [ ] More menu → Report user → reason sheet → submits
- [ ] More menu → Block user → confirmation toast → user's content hidden

## 7. Match / swipe

- [ ] Match screen shows swipe cards
- [ ] Swipe right → "LIKE" banner animates
- [ ] Swipe left → "PASS" banner animates
- [ ] Tap star/profile button → opens user profile
- [ ] Matches persist across app restarts
- [ ] Location banner says "approximate" (honest)

## 8. Groups

- [ ] Groups list loads
- [ ] Tap a group → group detail screen
- [ ] Join → member count updates
- [ ] Leave → confirmation dialog → member count decrements
- [ ] More menu → Share copies group link
- [ ] More menu → Report group → reason sheet → submits

## 9. Events

- [ ] Events screen loads
- [ ] Tap an event → event details
- [ ] RSVP → RSVP count increments
- [ ] Share event → link copied

## 10. Deals (Crew promotions)

- [ ] `/offers` loads all active promotions
- [ ] Search filters by business name and title
- [ ] Tap a promotion → detail screen
- [ ] Expired promotion → shows 404 "Not found" screen (not a wrong promo)

## 11. SafeCheck

- [ ] Nearby screen FAB → SafeCheck sheet
- [ ] Submit "safe" check-in → saves to Firestore
- [ ] Location banner is honest about approximate coords
- [ ] SafeCheck history shows previous check-ins

## 12. Admin Dashboard (only for admin account)

- [ ] Login as `alan123@gmail.com` → auto-routes to `/admin/dashboard`
- [ ] All 7 pages load: Dashboard, Users, Content, SafeCheck, Events, Analytics, Notifications
- [ ] Users → ban → confirmation dialog → target user's `isBanned = true` in Firestore
- [ ] Content → remove post → confirmation → post deleted
- [ ] Notifications → compose → send to all users → toast with recipient count
- [ ] Logout → confirmation dialog → returns to login

## 13. Settings

- [ ] Change password → re-auth flow → success
- [ ] Change password with wrong current password → specific error message
- [ ] App Version displays a real version (e.g., "1.0.0 (1)"), not "1.0.0" hardcoded
- [ ] Toggle notifications → persists across app restart
- [ ] Privacy Policy / Terms → either open URL in browser OR show "hosted at flyconnect.app/..."
- [ ] Delete Account works end-to-end (see 3.6)

## 14. Push notifications

- [ ] Send a test push from Firebase Console → FCM → Compose notification → "Send test message"
- [ ] Paste the FCM token from `users/{uid}.fcmToken`
- [ ] Notification arrives on device within 30 seconds
- [ ] Tap the notification → app opens to correct deep link (if set)

## 15. Deep links

- [ ] Open `https://flyconnect.app/posts/{existing-post-id}` in browser → app opens post
- [ ] Open `flyconnect://conversation/{chat-id}?name=Alex&group=false` via adb → opens DM
- [ ] Open a promotion link for a deleted promotion → lands on NotFoundScreen (not a wrong promo)

## 16. Offline behavior

- [ ] Turn Wi-Fi off
- [ ] Open app → shows cached feed (via Firestore persistence)
- [ ] Try to create post → gets queued; when Wi-Fi comes back, posts

## 17. Configuration changes

- [ ] Rotate device → UI re-lays out without crashing
- [ ] Background and foreground the app → resumes to same screen
- [ ] Receive a phone call during chat → chat state preserved

## 18. Performance spot checks

- [ ] Scrolling feed for 30 seconds → Android Studio Profiler shows < 16ms frame time most of the time
- [ ] Memory usage after 5 min of browsing < 300 MB
- [ ] No Firestore listeners leaking (Firebase Console → Firestore usage → not growing exponentially)

## 19. Business Dashboard Walkthrough

Requires **two** business accounts (e.g. `info@skyloungelnyc.com` plus a second seeded business account) and one plain crew account — see `docs/business-user-flow-test-plan.md` for full detail on every fix this section verifies.

**Cross-tenant scoping (A3/A4):**
- [ ] Business A creates a deal and an event
- [ ] Business B logs in → their own "Crew Deals" and "Events" tabs show **zero** of Business A's items
- [ ] Business B cannot reach Business A's event via any "Manage" button (none should be visible)

**Ownership guard (A4):**
- [ ] Deep-link Business B into Business A's event management screen (if reachable at all) → permission-denied message, not the attendee roster

**Moderation gate (A1/A2):**
- [ ] Business A creates an event → does **not** appear in the crew-facing Events tab yet
- [ ] Admin approves it → now appears in the crew-facing Events tab
- [ ] Business A's own "Business Events" tab shows the pending event throughout (before and after approval)

**Route guards (A5):**
- [ ] Logged in as the plain crew account, deep-link to `/promotions/create`, `/analytics`, `/business-profile` → redirected to home, screens never render

**Business → user reflection (B1):**
- [ ] As the crew account, open an event created by a verified business → a "Hosted by [Business Name] ✓" row appears above the description, tappable to the business's profile
- [ ] Same check for a group
- [ ] Tap through to the business's profile from anywhere (post, event, group, search) → shows a ✓ verified badge and a business-style pill instead of "airline · position" — previously this always showed a completely generic profile with no indication of a business account

**Notifications (B2):**
- [ ] As the crew account, follow Business A
- [ ] Business A publishes a new deal, gets admin-approved → the crew account receives a notification ("Sky Lounge NYC posted [deal title]"), tapping it opens the deal
- [ ] Repeat for an event and a group
- [ ] Business A publishes a second deal within a few hours → **no** second notification (6-hour cooldown) — confirm the deal itself is still visible/live, only the push is throttled

---

## Exit criteria

**Block the release** if any of the following:
- Any section 1, 2, or 3 step fails
- Any "critical — Play Store requirement" step fails (3.6 Delete Account, Section 2 permissions, Section 11 report/block)
- Crash on any core flow (login, feed, create post, chat)
- Crashlytics spike within 15 minutes of install

**Ship ready** when:
- All sections pass
- Zero Crashlytics crashes in the first 15 minutes of manual use
- Pre-launch report has no Critical issues

---

## Sign-off

```
Tester name:           ___________________
Device:                ___________________
Android version:       ___________________
Build version:         ___________________
Date:                  ___________________
All steps passed:      ☐ Yes  ☐ No
Blocker issues (if any):
  _______________________________________
Signature:             ___________________
```

File a completed copy in the team drive at `releases/{version}/smoke-test.md` for every release.
