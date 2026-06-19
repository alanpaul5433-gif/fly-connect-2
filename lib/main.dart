import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:provider/provider.dart';
import 'core/config/firebase_config.dart';
import 'core/services/notification_service.dart';
import 'core/services/version_check_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_router.dart';
import 'features/common/force_update_screen.dart';
import 'shared/providers/real_providers.dart';
import 'shared/widgets/error_boundary.dart';

Future<void> main() async {
  // Wrap in runZonedGuarded so uncaught async errors also go to Crashlytics.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Install the friendly error fallback as early as possible — before
    // Firebase init, in case Firebase itself throws during boot.
    ErrorBoundary.install();
    // Android/iOS auto-initialize the [DEFAULT] app natively from
    // google-services.json / GoogleService-Info.plist (the Gradle / CocoaPods
    // plugins run before any Dart). Calling initializeApp again then throws
    // `duplicate-app`. Swallow exactly that case — the native default app is
    // already live and carries the correct google_app_id, so we inherit it —
    // and rethrow anything else.
    try {
      await Firebase.initializeApp(
        options: FirebaseConfig.currentPlatformOptions,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }

    // Crashlytics wiring (Crashlytics is not supported on web).
    if (!kIsWeb) {
      // Disable in debug to avoid polluting the dashboard with dev crashes.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      // Flutter framework errors -> Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Platform async errors (Isolate, etc.) -> Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    // Analytics: log app_open for install/activation funnel
    try {
      await FirebaseAnalytics.instance.logAppOpen();
    } catch (_) {/* analytics is best-effort */}

    // FCM: permission prompt + token storage + foreground listener
    unawaited(NotificationService.instance.init());

    runApp(const FlyConnectApp());
  }, (error, stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

class FlyConnectApp extends StatelessWidget {
  const FlyConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, UserProvider>(
          create: (_) => UserProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, PostProvider>(
          create: (_) => PostProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, EventProvider>(
          create: (_) => EventProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, GroupProvider>(
          create: (_) => GroupProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, MatchProvider>(
          create: (_) => MatchProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          create: (_) => NotificationProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, TripProvider>(
          create: (_) => TripProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, SearchProvider>(
          create: (_) => SearchProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, PromotionProvider>(
          create: (_) => PromotionProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, SafeCheckProvider>(
          create: (_) => SafeCheckProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
      ],
      child: MaterialApp.router(
        title: 'FlyConnect',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: appRouter,
        builder: (context, child) => _VersionGate(child: child),
      ),
    );
  }
}

/// Runs the Firestore-backed force-update check on first build and
/// either:
///   • shows [ForceUpdateScreen] (blocking) when below `minSupportedBuild`,
///   • shows a one-shot SnackBar (non-blocking) when below `latestBuild`,
///   • renders the app as normal otherwise.
///
/// On any failure (no network, doc missing, etc.) we fail open — never
/// lock the user out due to a transient backend hiccup.
class _VersionGate extends StatefulWidget {
  final Widget? child;
  const _VersionGate({required this.child});

  @override
  State<_VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<_VersionGate> {
  Future<VersionCheckResult>? _future;

  @override
  void initState() {
    super.initState();
    _future = VersionCheckService.instance.check();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VersionCheckResult>(
      future: _future,
      builder: (ctx, snap) {
        // While the check is in flight, render the router as-is so
        // splash / login appear immediately. Force-update only takes
        // effect after the check returns.
        if (!snap.hasData) return widget.child ?? const SizedBox.shrink();
        final result = snap.data!;
        if (result.status == VersionStatus.forceUpdate) {
          return ForceUpdateScreen(result: result);
        }
        return widget.child ?? const SizedBox.shrink();
      },
    );
  }
}
