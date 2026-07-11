// Admin-only GoRouter used by the dedicated admin web target
// (lib/main_admin.dart). Stripped of all consumer/business routes.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants/app_routes.dart';
import '../../shared/providers/real_providers.dart';
import '../../features/admin/admin_login_screen.dart';
import '../../features/admin/admin_shell.dart';
import '../../features/admin/admin_dashboard_page.dart';
import '../../features/admin/admin_users_page.dart';
import '../../features/admin/admin_content_page.dart';
import '../../features/admin/admin_safecheck_page.dart';
import '../../features/admin/admin_nearby_page.dart';
import '../../features/admin/admin_events_page.dart';
import '../../features/admin/admin_analytics_page.dart';
import '../../features/admin/admin_notifications_page.dart';
import '../../features/admin/admin_reports_page.dart';
import '../../features/admin/admin_promotions_page.dart';
import '../../features/admin/admin_gdpr_page.dart';
import '../../features/admin/admin_audit_page.dart';
import '../../features/admin/admin_business_verification_page.dart';

final GoRouter adminRouter = GoRouter(
  initialLocation: '/login',
  debugLogDiagnostics: false,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final isLoggedIn = auth.isLoggedIn;
      final isAdmin = isLoggedIn && auth.userRole == 'admin';

      // Login screen: if already admin, jump to dashboard.
      if (loc == '/login' && isAdmin) {
        return '/admin/dashboard';
      }

      // Any admin route: if not logged in OR not admin, bounce to login.
      if (loc.startsWith('/admin') && !isAdmin) {
        return '/login';
      }

      // Anything else (e.g. root /) → login.
      if (loc == '/' || loc == '') {
        return isAdmin ? '/admin/dashboard' : '/login';
      }
    } catch (_) {
      // AuthProvider not ready yet — let initial location show
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, __) => const AdminLoginScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.adminDashboard,
          builder: (_, __) => const AdminDashboardPage(),
        ),
        GoRoute(
          path: AppRoutes.adminUsers,
          builder: (_, __) => const AdminUsersPage(),
        ),
        GoRoute(
          path: AppRoutes.adminReports,
          builder: (_, __) => const AdminReportsPage(),
        ),
        GoRoute(
          path: AppRoutes.adminContent,
          builder: (_, __) => const AdminContentPage(),
        ),
        GoRoute(
          path: AppRoutes.adminSafeCheck,
          builder: (_, __) => const AdminSafeCheckPage(),
        ),
        GoRoute(
          path: AppRoutes.adminNearby,
          builder: (_, __) => const AdminNearbyPage(),
        ),
        GoRoute(
          path: AppRoutes.adminEvents,
          builder: (_, __) => const AdminEventsPage(),
        ),
        GoRoute(
          path: AppRoutes.adminPromotions,
          builder: (_, __) => const AdminPromotionsPage(),
        ),
        GoRoute(
          path: AppRoutes.adminBusinessVerify,
          builder: (_, __) => const AdminBusinessVerificationPage(),
        ),
        GoRoute(
          path: AppRoutes.adminGdpr,
          builder: (_, __) => const AdminGdprPage(),
        ),
        GoRoute(
          path: AppRoutes.adminAudit,
          builder: (_, __) => const AdminAuditPage(),
        ),
        GoRoute(
          path: AppRoutes.adminAnalytics,
          builder: (_, __) => const AdminAnalyticsPage(),
        ),
        GoRoute(
          path: AppRoutes.adminNotifications,
          builder: (_, __) => const AdminNotificationsPage(),
        ),
      ],
    ),
  ],
  errorBuilder: (_, __) => const Scaffold(
    body: Center(child: Text('Page not found')),
  ),
);
