import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/auth_provider.dart' show AuthProvider;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5)));
    _controller.forward();

    // Route once the 900ms logo animation has fully played (plus a ~100ms
    // beat). Was a flat 2s — trimmed to cut ~1s of dead splash time off
    // perceived cold start without clipping the animation (L-7).
    Future.delayed(const Duration(milliseconds: 1000), _routeNext);
  }

  Future<void> _routeNext() async {
    if (!mounted) return;
    try {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        // Already authenticated — wait for the role fetch to actually finish
        // before deciding, so a slow Firestore read can't leave us reading
        // the 'user' default and stranding a business/admin account in the
        // wrong shell. Bounded so an offline/unreachable Firestore can't
        // hang splash forever.
        await auth.authReady.timeout(const Duration(seconds: 3), onTimeout: () {});
        if (!mounted) return;
        final role = auth.userRole;
        if (!mounted) return;
        switch (role) {
          case 'admin':
            context.go('/admin/dashboard');
            break;
          case 'business':
            context.go('/dashboard');
            break;
          default:
            context.go(AppRoutes.home);
        }
        return;
      }
    } catch (e) {
      // AuthProvider type mismatch in mock mode — fall through to login.
      // Log so a real (non-mock) failure here isn't an invisible logout.
      debugPrint('[Splash] auth/role resolution failed, routing to login: $e');
    }
    // Not logged in (or mock mode) — check onboarding then go to login
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    if (!mounted) return;
    context.go(seen ? AppRoutes.login : AppRoutes.onboarding);
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black, // #000000 — matches the app icon background seamlessly
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/images/app_icon.png', width: 140, height: 140),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Text('DEBUG MODE', style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 11, letterSpacing: 2)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
