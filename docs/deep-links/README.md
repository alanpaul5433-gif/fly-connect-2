# Android App Links — flyconnect.co

> **STATUS: DEFERRED for v1.0.** App Links were removed from the manifest for the initial
> Android launch. This runbook is retained as reference for re-enabling deep linking later.

Fixes the Play Console **Deep links → "1 domain not verified / Failed domain checks"**
for `com.urbansyncinnovations.flyconnect`.

## Why it was failing

The App Links intent-filter pointed at `flyconnect.app`, which has **no DNS address
record and no web host** (registered on Cloudflare but nothing is served). Google's
Digital Asset Links crawler could not fetch `/.well-known/assetlinks.json`, so the
domain check failed. We repointed App Links to `flyconnect.co` (the live WordPress
site on Hostinger), path-scoped to the deep-link routes only.

## What must be hosted

Serve `assetlinks.json` (this folder) at exactly:

```
https://flyconnect.co/.well-known/assetlinks.json
```

Requirements Google enforces:
- **HTTPS**, valid cert, **HTTP 200**, **no redirect** on that URL
- `Content-Type: application/json`
- Publicly reachable (no login wall, no bot-challenge)

## Step 1 — Get the SHA-256 fingerprint(s)

Play Console → **Test and release → Setup → App signing**:
- **App signing key certificate → SHA-256** — REQUIRED (Play re-signs your AAB, so this
  is the cert Android sees at runtime). Without it, production installs will NOT verify.
- **Upload key certificate → SHA-256** — recommended too, so locally-signed test builds
  also open deep links.

Paste both (uppercase colon-separated hex, e.g. `AB:CD:...`) into `assetlinks.json`,
replacing the `REPLACE_WITH_*` placeholders. Colons are fine; Google accepts them.

> Tip: the App signing page also shows a ready-made "Digital Asset Links JSON" snippet
> you can copy verbatim — it already contains the correct SHA-256.

## Step 2 — Upload to Hostinger (WordPress)

1. hPanel → **File Manager** → open `public_html/`.
2. Create folder `.well-known` (leading dot). If File Manager hides it, create via the
   "New Folder" dialog typing `.well-known` exactly.
3. Upload the finalized `assetlinks.json` into `public_html/.well-known/`.

WordPress won't intercept it: the default `.htaccess` rewrite only redirects
**non-existent** paths to `index.php` (`RewriteCond %{REQUEST_FILENAME} !-f`), and a
real file short-circuits that. If you still get a WP 404, add to the TOP of `.htaccess`:

```apache
# Serve Android App Links verification file directly
RewriteRule ^\.well-known/assetlinks\.json$ - [L]
```

## Step 3 — Verify it serves correctly

```bash
curl -sS -I https://flyconnect.co/.well-known/assetlinks.json   # want: 200 + content-type json, no redirect
```

Google's tester (authoritative):
```
https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://flyconnect.co&relation=delegate_permission/common.handle_all_urls
```

## Step 4 — Re-verify in Play Console

Play Console → **Grow users → Deep links**. Re-run the domain check (verification can
take minutes to a couple of hours to propagate). On-device, a fresh install triggers
verification automatically; force it with:

```bash
adb shell pm verify-app-links --re-verify com.urbansyncinnovations.flyconnect
adb shell pm get-app-links com.urbansyncinnovations.flyconnect   # want: "verified"
```

## Note — routes that resolve on the web

The app now shares `https://flyconnect.co/{posts,groups,events,promotions}/{id}` links.
For users **without** the app installed, those URLs currently 404 on the WordPress site.
Consider adding a lightweight fallback page (or a redirect to the store) at those paths
so shared links degrade gracefully. Not required for App Links verification.
