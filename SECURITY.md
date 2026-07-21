# Security Policy

## Supported Versions

We patch the latest released version of FlyConnect. Older versions
are not maintained — please update to the latest App Store / Play
Store release before reporting.

## Reporting a Vulnerability

If you discover a security issue, please **do not** open a public
GitHub issue or post about it on social media. We follow a 90-day
coordinated-disclosure window.

Email: **security@flyconnect.co** *(placeholder — replace with your real
inbox before launch)*

Please include:

1. A description of the issue
2. Steps to reproduce
3. The version + platform where you found it
4. Your assessment of impact (data exposed, privilege escalation, etc.)
5. Whether you'd like credit in the eventual disclosure

We aim to:

- Acknowledge receipt within **3 business days**
- Provide an initial assessment within **10 business days**
- Patch and release within **90 days** of confirmation
- Publish a coordinated disclosure with credit (if requested) after the
  fix has rolled out to the majority of users

## Scope

In scope:

- The FlyConnect Android, iOS, and web clients
- The FlyConnect Admin web console
- Firestore security rules and Cloud Functions (when deployed)
- Authentication flows (Email, Google, Apple)

Out of scope:

- Issues that require a rooted/jailbroken device
- Social engineering of staff
- Physical attacks
- Self-XSS or DoS via the client
- Third-party vendor issues (Firebase, Google Play Services, etc.) —
  please report those upstream

## Safe Harbor

We will not pursue legal action against researchers who:

- Make a good-faith effort to follow this policy
- Stop testing as soon as harm is observed
- Do not access, modify, or destroy data beyond what is necessary to
  demonstrate the issue
- Do not publicly disclose the issue before we've had a reasonable
  window to fix it

## PGP / Signed Email

If you require encrypted communication, request our public key at the
above email address.
