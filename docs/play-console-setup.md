# Google Play Console — End-to-End Setup Guide

This guide walks you from "no Play Console account" to "app live in Internal Testing" for **FlyConnect**. Do not skip steps — Play Console's UI expects certain fields before it lets you advance.

---

## Part 1 — One-time account setup

### 1.1 Create a Google Play Console developer account

1. Go to https://play.google.com/console/signup
2. Sign in with the Google account that will own the developer profile
3. Accept the Developer Distribution Agreement
4. Pay the **$25 USD one-time registration fee**
5. Choose account type: **Organization** (since this will be published by AppCurb Technologies)
6. Fill out organization verification:
   - Legal business name
   - Business address
   - Business phone (must be reachable — Google calls to verify)
   - DUNS number (if you have one; optional)
7. Upload a photo ID of a responsible director for verification

**Wait time:** Organization verification can take **2–14 business days**. Plan around this.

### 1.2 Set up your developer profile

- **Developer name:** `AppCurb Technologies` — this appears next to your app in the Play Store
- **Website:** `https://appcurb.com` (or your company site)
- **Support email:** `support@flyconnect.co`
- **Support phone/URL:** optional

### 1.3 Enable two-step verification

Required by Play Console for the Google account. Use a hardware key (YubiKey) if possible; otherwise Google Authenticator.

---

## Part 2 — Create the app

### 2.1 Create a new app

Play Console → **All apps → Create app**.

| Field | Value |
|-------|-------|
| App name | `FlyConnect` |
| Default language | `English (United States) – en-US` |
| App or game | `App` |
| Free or paid | `Free` |
| Declarations | ✅ Developer Program Policies, ✅ US export laws |

Click **Create app**.

### 2.2 App category & store listing (Main)

Play Console → your app → **Grow → Store presence → Main store listing**.

Copy/paste from `docs/store-listing.md`:

- App name, Short description, Full description
- Graphic assets (see `docs/app-assets-guide.md`)
- App icon, feature graphic, phone screenshots (min 2), 7" + 10" tablet screenshots (if targeting tablets — recommended)
- Category: **Social**
- Tags: aviation, crew, travel
- Contact email, website, privacy policy URL

### 2.3 Set pricing & distribution

**Monetization → Subscriptions and products:** skip for now (no IAP).
**Countries/regions:** select target markets or "All available".
**Device categories:** Phone, Tablet. (Wear OS / TV / Auto / ChromeOS — not applicable.)

---

## Part 3 — Policy & compliance

### 3.1 Privacy Policy

Your privacy policy **must be hosted at a public URL** before you can publish. See `docs/privacy-policy.md` for the content.

Host on Firebase Hosting (simplest — free tier):

```bash
npm install -g firebase-tools
firebase login
firebase init hosting  # choose flyconnect-ab4f2 project
```

Put the policy HTML in `public/privacy/index.html`, then:

```bash
firebase deploy --only hosting
```

Final URL: `https://flyconnect-ab4f2.web.app/privacy` (or a custom domain like `https://flyconnect.app/privacy` — set up in Firebase Hosting → Custom domain).

Paste the URL in **Play Console → App content → Privacy Policy**.

### 3.2 App access

If parts of the app require a login, Play reviewers need test credentials:

**Play Console → App content → App access → Manage:**

- Select "All or some functionality is restricted"
- Add a test account:
  - Username: `alex@delta.com`
  - Password: `Test1234!`
  - Instructions: "Standard crew-member account. Use Settings → Switch account to try Business role with `info@skyloungelnyc.com`."

### 3.3 Ads declaration

**App content → Ads:** select **No, my app does not contain ads.**

### 3.4 Content ratings (IARC)

**App content → Content ratings → Start questionnaire.**

Complete the IARC questionnaire. For FlyConnect, typical answers:

| Question | Answer |
|----------|--------|
| Does your app contain violence? | No |
| Does your app contain sexual content or nudity? | No |
| Does your app contain profanity or crude humor? | No — **but user-generated content can vary** (see next) |
| Does your app include **user-generated content** and allow **unrestricted communication** between users? | **Yes** |
| Does your app allow users to meet each other in the physical world? | Yes (Match / meetups) |
| Does your app share user location with other users? | Yes (optional) |

The UGC + communication flag will likely give you a **Teen** rating globally (13+ in US; 16+ in EU). This is normal for social apps.

### 3.5 Target audience and content

**App content → Target audience and content:**

- **Target age groups:** 16+, 18+. **Do not select any age band under 16** — our ToS prohibits under-16 users.
- **Appeals to children:** No.
- **Google Play Families Policy:** Not enrolled.

### 3.6 News apps

Not a news app → No.

### 3.7 COVID-19 tracing/status apps

Not applicable → No.

### 3.8 Data safety

See `docs/data-safety-form.md` for the complete answer set. This section is mandatory and the most detailed one.

### 3.9 Government apps

Not applicable → No.

### 3.10 Financial features

Not applicable → No.

### 3.11 Health

Not applicable → No (SafeCheck is a social status, not a health feature — but if you ever add first-aid or medical info, revisit).

---

## Part 4 — App bundle upload

### 4.1 App signing

**Setup → App signing:** enroll in **Play App Signing** when prompted. Upload your upload key certificate (extracted from your keystore). See `docs/keystore-setup.md`.

### 4.2 Create internal testing release

**Testing → Internal testing → Create new release**.

- Upload your AAB: `build/app/outputs/bundle/release/app-release.aab`
- Release name: auto-filled to `1.0.0 (1)` based on `pubspec.yaml` version
- Release notes: copy from `docs/store-listing.md` → "What's New"
- **Review → Start rollout to Internal testing**

### 4.3 Add testers

**Testing → Internal testing → Testers tab:**

- Create email list "FlyConnect Core Team"
- Add up to 100 email addresses (yours, team, initial crew testers)
- Share the opt-in URL (shown on the Testers tab) with the list

Each tester must:
1. Click the opt-in URL on the device where they'll install
2. Sign in with the Google account matching their tester email
3. Install from Play Store (link appears after opt-in)

### 4.4 Pre-launch report

Google automatically runs your AAB on ~20 real devices as an automated pre-launch test. Results appear in:

**Testing → Internal testing → (your release) → Pre-launch report details.**

See `docs/pre-launch-report-guide.md` for how to interpret the report.

---

## Part 5 — Review and publish

After validating internal testing for 48–72 hours with no Crashlytics spikes:

1. **Testing → Closed testing:** promote build from Internal → Closed testing track
2. **Testing → Open testing:** promote from Closed → Open testing track (public, but opt-in)
3. **Production:** final review → **Start rollout to Production**

### First production rollout

- Start with a **staged rollout at 1%** for the first 24 hours
- Increase to 5%, 20%, 50%, 100% over 3–5 days
- Monitor Crashlytics and Play Console vitals at each stage

### Google review time

- Internal testing: **instant**
- Closed / Open testing: **a few hours**
- **First-ever production submission:** **up to 7 days** (Google reviews new developers more thoroughly)
- Subsequent production updates: typically **1–3 days**

---

## Part 6 — Post-launch checklist

- [ ] Enable in-app updates: `flutter pub add in_app_update`
- [ ] Wire Play Integrity API (anti-cheat, anti-abuse) — relevant once user base grows
- [ ] Monitor Crashlytics weekly
- [ ] Respond to user reviews within 48h on Play Console
- [ ] Schedule store listing A/B tests (title, screenshots)

---

## Useful Play Console links

- Main dashboard: https://play.google.com/console
- Policy center: https://play.google.com/console/u/0/developers/policy-status
- Developer Program Policies: https://play.google/developer-content-policy
- Store listing best practices: https://developer.android.com/distribute/best-practices/launch/store-listing
- Data safety guide: https://support.google.com/googleplay/android-developer/answer/10787469

---

## Red flags that cause rejection

Based on real FlyConnect-relevant patterns:

| Rejection reason | Root cause | Our mitigation |
|------------------|------------|----------------|
| "Deceptive behavior" | Fake "coming soon" features | We ship with honest "coming soon" labels (voice calls, image chat) |
| "User-generated content policy" | No report/block mechanism | We have both, functional, writing to Firestore |
| "Data safety form mismatch" | Declared vs actual data mismatch | Our docs/data-safety-form.md mirrors what the code actually does |
| "Inadequate account deletion" | Delete button doesn't delete server data | `deleteAccount()` purges Firestore + Auth |
| "Permissions without purpose" | Requesting location without using it | We have usage descriptions + actual runtime use |
| "Metadata policy — sensitive content" | Screenshots show user chat/profile info | Use seeded test accounts for screenshots only |
| "Spam policy" | Low-value / keyword-stuffed description | Our full description is feature-focused, not keyword spam |
