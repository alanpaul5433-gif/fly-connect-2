# Integration tests (Firestore + Functions emulator)

Real trigger wiring against the Firestore + Functions emulators — catches a
wrong collection path or field-name typo that the mocked-Admin-SDK unit tests
under `src/**/__tests__` structurally cannot (a mock happily answers a call
to the wrong path).

Requires a JDK 21+ on `PATH` (the Firestore emulator needs it) and network
access on first run to download the emulator jars.

Run from the repo root or from `functions/`:

```bash
npm run test:integration
```

This builds the functions, then wraps the whole run in
`firebase emulators:exec --only firestore,functions --project demo-flyconnect-test`,
which starts both emulators, runs `test:integration:run` (plain Jest) against
them, and tears the emulators down automatically on exit — no manual
`emulators:start` process to manage.

There is no FCM emulator in the suite, so the push fan-out (Stage 2) test can
only confirm the trigger runs to completion without crashing the emulator —
not that a real push was delivered. See the design doc's "Known limitations"
(`docs/superpowers/specs/2026-07-15-notification-producer-design.md`).
