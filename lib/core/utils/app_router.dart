import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/auth_provider.dart';
import '../constants/app_routes.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/business/dashboard_screen.dart';
import '../../features/business/promotions_screen.dart';
import '../../features/business/create_promotion_screen.dart';
import '../../features/business/promotion_detail_screen.dart';
import '../../shared/providers/promotion_provider.dart';
import '../../shared/providers/group_provider.dart';
import '../../shared/providers/event_provider.dart';
import '../../shared/models/models.dart';
import 'package:provider/provider.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/home/main_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/events/events_screen.dart';
import '../../features/events/event_details_screen.dart';
import '../../features/events/create_group_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/edit_profile_details_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/conversation_screen.dart';
import '../../features/match/match_screen.dart';
import '../../features/match/match_preferences_screen.dart';
import '../../features/nearby/nearby_users_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/trips/trips_screen.dart';
import '../../features/groups/groups_screen.dart';
import '../../features/groups/group_details_screen.dart';
import '../../features/home/create_post_screen.dart';
import '../../features/business/business_shell.dart';
import '../../features/business/group_management_screen.dart';
import '../../features/business/event_management_screen.dart';
import '../../features/business/business_profile_screen.dart';
import '../../features/business/analytics_screen.dart';
import '../../features/business/business_events_screen.dart';
import '../../features/business/create_event_screen.dart';
import '../../features/nearby/safe_check_history_screen.dart';
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
import '../../features/promotions/offers_screen.dart';
import '../../features/common/not_found_screen.dart';

// Each ShellRoute needs its own unique navigatorKey to avoid GlobalKey conflicts on web
final _userShellKey     = GlobalKey<NavigatorState>(debugLabel: 'user-shell');
final _businessShellKey = GlobalKey<NavigatorState>(debugLabel: 'biz-shell');
final _adminShellKey    = GlobalKey<NavigatorState>(debugLabel: 'admin-shell');

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: false,
  redirect: (context, state) {
    final loc = state.matchedLocation;

    const publicRoutes = {
      AppRoutes.splash, AppRoutes.login, AppRoutes.signup,
      AppRoutes.otp, AppRoutes.forgotPassword, AppRoutes.onboarding,
    };

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final isLoggedIn = auth.isLoggedIn;

      // Unauthenticated — only public routes allowed
      if (!isLoggedIn && !publicRoutes.contains(loc)) {
        return AppRoutes.login;
      }

      // Role-based guards
      if (isLoggedIn) {
        final role = auth.userRole;

        if (loc.startsWith('/admin') && role != 'admin') {
          return role == 'business' ? '/dashboard' : AppRoutes.home;
        }

        if ((loc == '/dashboard' || loc == '/promotions' || loc == '/business-events') &&
            role != 'business' && role != 'admin') {
          return AppRoutes.home;
        }

        // Event/Group creation is business-only (admins allowed for moderation).
        // Catches deep-links / direct navigation; the UI also hides the buttons.
        if ((loc == '/create-event' || loc == AppRoutes.createGroup) &&
            role != 'business' && role != 'admin') {
          return AppRoutes.home;
        }
      }
    } catch (_) {
      // Provider not yet ready — let splash handle routing
    }

    return null;
  },
  routes: [
    // ── Auth ──────────────────────────────────────────────────
    GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
    GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
    GoRoute(path: AppRoutes.signup, builder: (_, __) => const SignupScreen()),
    GoRoute(path: AppRoutes.otp,
      builder: (_, state) => OtpScreen(email: state.uri.queryParameters['email'] ?? '')),
    GoRoute(path: AppRoutes.forgotPassword, builder: (_, __) => const ForgotPasswordScreen()),

    // ── User Shell (bottom nav) ───────────────────────────────
    ShellRoute(
      navigatorKey: _userShellKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(path: AppRoutes.events, builder: (_, __) => const EventsScreen()),
        GoRoute(path: AppRoutes.match, builder: (_, __) => const MatchScreen()),
        GoRoute(path: AppRoutes.chat, builder: (_, __) => const ChatScreen()),
        GoRoute(path: AppRoutes.profile, builder: (_, __) => const ProfileScreen(isOwner: true)),
      ],
    ),

    // ── Business Shell (bottom nav) ───────────────────────────
    ShellRoute(
      navigatorKey: _businessShellKey,
      builder: (context, state, child) => BusinessShell(child: child),
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/promotions', builder: (_, __) => const PromotionsScreen()),
        GoRoute(path: '/business-events', builder: (_, __) => const BusinessEventsScreen()),
      ],
    ),

    // ── Admin Shell (sidebar nav) ──────────────────────────────
    ShellRoute(
      navigatorKey: _adminShellKey,
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(path: AppRoutes.adminDashboard, builder: (_, __) => const AdminDashboardPage()),
        GoRoute(path: AppRoutes.adminUsers, builder: (_, __) => const AdminUsersPage()),
        GoRoute(path: AppRoutes.adminContent, builder: (_, __) => const AdminContentPage()),
        GoRoute(path: AppRoutes.adminSafeCheck, builder: (_, __) => const AdminSafeCheckPage()),
        GoRoute(path: AppRoutes.adminNearby, builder: (_, __) => const AdminNearbyPage()),
        GoRoute(path: AppRoutes.adminEvents, builder: (_, __) => const AdminEventsPage()),
        GoRoute(path: AppRoutes.adminAnalytics, builder: (_, __) => const AdminAnalyticsPage()),
        GoRoute(path: AppRoutes.adminNotifications, builder: (_, __) => const AdminNotificationsPage()),
        GoRoute(path: AppRoutes.adminReports, builder: (_, __) => const AdminReportsPage()),
        GoRoute(path: AppRoutes.adminPromotions, builder: (_, __) => const AdminPromotionsPage()),
        GoRoute(path: AppRoutes.adminGdpr, builder: (_, __) => const AdminGdprPage()),
        GoRoute(path: AppRoutes.adminAudit, builder: (_, __) => const AdminAuditPage()),
        GoRoute(path: AppRoutes.adminBusinessVerify, builder: (_, __) => const AdminBusinessVerificationPage()),
      ],
    ),

    // ── Standalone ────────────────────────────────────────────
    GoRoute(path: '/events/:eventId',
      builder: (_, state) => EventDetailsScreen(eventId: state.pathParameters['eventId'])),
    GoRoute(path: AppRoutes.createGroup, builder: (_, __) => const CreateGroupScreen()),
    GoRoute(path: AppRoutes.editProfile, builder: (_, __) => const EditProfileScreen()),
    GoRoute(path: AppRoutes.editProfileDetails, builder: (_, __) => const EditProfileDetailsScreen()),
    GoRoute(path: AppRoutes.nearby, builder: (_, __) => const NearbyUsersScreen()),
    GoRoute(path: AppRoutes.safeCheckHistory, builder: (_, __) => const SafeCheckHistoryScreen()),
    GoRoute(path: AppRoutes.offers, builder: (_, __) => const OffersScreen()),
    GoRoute(path: AppRoutes.settings, builder: (_, __) => const SettingsScreen()),
    GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
    GoRoute(path: AppRoutes.search, builder: (_, __) => const SearchScreen()),
    GoRoute(path: AppRoutes.trips, builder: (_, __) => const TripsScreen()),
    GoRoute(path: AppRoutes.matchPreferences, builder: (_, __) => const MatchPreferencesScreen()),
    GoRoute(path: '/groups-list', builder: (_, __) => const GroupsScreen()),

    // ── Deep link routes ──────────────────────────────────────
    GoRoute(path: '/users/:userId',
      builder: (_, state) => ProfileScreen(
        isOwner: false, userId: state.pathParameters['userId'])),

    GoRoute(path: '/conversation/:chatId',
      builder: (_, state) => ConversationScreen(
        chatId: state.pathParameters['chatId'] ?? '',
        otherName: state.uri.queryParameters['name'] ?? 'Chat',
        otherPhotoUrl: state.uri.queryParameters['photo'],
        isGroup: state.uri.queryParameters['group'] == 'true')),

    GoRoute(path: '/groups/:groupId',
      builder: (_, state) => GroupDetailsScreen(groupId: state.pathParameters['groupId'] ?? '')),

    GoRoute(path: '/passport/:userId',
      builder: (_, state) => TripsScreen(userId: state.pathParameters['userId'])),

    GoRoute(path: '/create-post', builder: (_, __) => const CreatePostScreen()),
    GoRoute(path: '/business-group-management',
      builder: (context, __) {
        final groups = context.read<GroupProvider>().groups;
        if (groups.isEmpty) {
          return const NotFoundScreen(
            title: 'No groups yet',
            message: 'Create a group first from your dashboard to manage it.',
          );
        }
        return GroupManagementScreen(group: groups.first);
      }),
    GoRoute(path: '/business-event-management',
      builder: (context, state) {
        // Prefer an event passed via GoRouter extra (from _EventCard.onPressed)
        if (state.extra is EventModel) {
          return EventManagementScreen(event: state.extra as EventModel);
        }
        final events = context.read<EventProvider>().events;
        if (events.isEmpty) {
          return const NotFoundScreen(
            title: 'No events yet',
            message: 'Create an event first from your dashboard to manage it.',
          );
        }
        return EventManagementScreen(event: events.first);
      }),
    GoRoute(path: '/business-profile',
      builder: (_, __) => const BusinessProfileScreen(isOwner: true)),
    GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),

    // ── Business standalone routes ────────────────────────────
    // Note: /promotions/create must be listed before /promotions/:id
    GoRoute(path: '/promotions/create', builder: (_, __) => const CreatePromotionScreen()),
    GoRoute(path: '/promotions/:id', builder: (context, state) {
      final id = state.pathParameters['id']!;
      final promos = context.read<PromotionProvider>().promotions;
      final promo = promos.where((p) => p.id == id).firstOrNull;
      if (promo == null) {
        return const NotFoundScreen(
          title: 'Promotion not found',
          message: 'This offer may have expired or been removed.',
        );
      }
      return PromotionDetailScreen(promotion: promo);
    }),
    GoRoute(path: '/events/create', builder: (_, __) => const EventsScreen()),
    GoRoute(path: '/create-event', builder: (_, __) => const CreateEventScreen()),
  ],
);
