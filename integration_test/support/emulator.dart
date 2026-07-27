/// Test-side emulator helpers.
///
/// The running app connects the DEFAULT Firebase singletons to the emulator
/// itself, inside `app.main()` (see `lib/core/config/emulator_config.dart`),
/// because every test is launched with
/// `--dart-define=USE_FIREBASE_EMULATOR=true`. So test code that reads back
/// through `FirebaseFirestore.instance` / `FirebaseAuth.instance` is already
/// pointed at the emulator with no extra wiring — this file deliberately stays
/// tiny and just re-exports the app's own flag/host for assertions and logging.
library;

export 'package:flyconnect/core/config/emulator_config.dart'
    show useEmulator, emulatorHost;
