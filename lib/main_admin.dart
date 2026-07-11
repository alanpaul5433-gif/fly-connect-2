// ════════════════════════════════════════════════════════════════
// FLYCONNECT ADMIN — SEPARATE WEB TARGET
// ════════════════════════════════════════════════════════════════
//
// This is a stripped-down admin-only build of FlyConnect, intended
// for moderation staff who do NOT need the mobile app.
//
// Build:    flutter build web -t lib/main_admin.dart -o build/admin_web --release
// Run dev:  flutter run -d chrome -t lib/main_admin.dart --web-port 8080
// Deploy:   firebase deploy --only hosting:admin
//
// Differences from lib/main.dart:
//   * No splash / onboarding / consumer or business shells
//   * Login screen → admin role gate → admin sidebar
//   * Only registers providers used by admin pages (auth + ones the
//     admin sidebar pages read from)
//   * App title shows "FlyConnect Admin"

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/admin_router.dart';
import 'firebase_options.dart';
import 'shared/providers/real_providers.dart';
import 'shared/widgets/error_boundary.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorBoundary.install();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (!kIsWeb) {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    try {
      await FirebaseAnalytics.instance.logAppOpen();
    } catch (_) {/* analytics is best-effort */}

    runApp(const FlyConnectAdminApp());
  }, (error, stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

class FlyConnectAdminApp extends StatelessWidget {
  const FlyConnectAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Admin-only provider set — skips Match, Trip, Search, Chat
      // (those pages aren't reachable from the admin shell).
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, UserProvider>(
          create: (_) => UserProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, PostProvider>(
          create: (_) => PostProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, EventProvider>(
          create: (_) => EventProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, GroupProvider>(
          create: (_) => GroupProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          create: (_) => NotificationProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, PromotionProvider>(
          create: (_) => PromotionProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
        ChangeNotifierProxyProvider<AuthProvider, SafeCheckProvider>(
          create: (_) => SafeCheckProvider(),
          update: (_, auth, p) { p!.updateAuth(auth); return p; }),
      ],
      child: MaterialApp.router(
        title: 'FlyConnect Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: adminRouter,
      ),
    );
  }
}
