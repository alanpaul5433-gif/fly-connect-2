import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/providers/real_providers.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;

  const _NavItem({required this.label, required this.icon, required this.route});
}

const _navItems = <_NavItem>[
  _NavItem(label: 'Dashboard', icon: Icons.grid_view_rounded, route: '/admin/dashboard'),
  _NavItem(label: 'Users', icon: Icons.people_outline, route: '/admin/users'),
  _NavItem(label: 'Reports', icon: Icons.flag_outlined, route: '/admin/reports'),
  _NavItem(label: 'Content', icon: Icons.article_outlined, route: '/admin/content'),
  _NavItem(label: 'SafeCheck', icon: Icons.health_and_safety, route: '/admin/safecheck'),
  _NavItem(label: 'Nearby', icon: Icons.map_outlined, route: '/admin/nearby'),
  _NavItem(label: 'Events', icon: Icons.event_outlined, route: '/admin/events'),
  _NavItem(label: 'Promotions', icon: Icons.local_offer_outlined, route: '/admin/promotions'),
  _NavItem(label: 'Businesses', icon: Icons.verified_outlined, route: '/admin/business-verify'),
  _NavItem(label: 'GDPR', icon: Icons.privacy_tip_outlined, route: '/admin/gdpr'),
  _NavItem(label: 'Audit Log', icon: Icons.fact_check_outlined, route: '/admin/audit'),
  _NavItem(label: 'Analytics', icon: Icons.bar_chart_rounded, route: '/admin/analytics'),
  _NavItem(label: 'Notifications', icon: Icons.notifications_outlined, route: '/admin/notifications'),
];

class AdminShell extends StatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  /// Auto-logout an admin after this many minutes of no input.
  /// Mitigates the "logged-in admin walks away from laptop" risk.
  static const Duration _idleTimeout = Duration(minutes: 30);
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _resetIdle();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _autoLogout);
  }

  Future<void> _autoLogout() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await auth.logout();
    if (!mounted) return;
    router.go('/login');
    messenger?.showSnackBar(const SnackBar(
      content: Text('Signed out after 30 minutes of inactivity.'),
      backgroundColor: AppColors.warning,
    ));
  }

  String _pageTitle(String location) {
    for (final item in _navItems) {
      if (location.startsWith(item.route)) return item.label;
    }
    return 'Admin';
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final user = context.watch<AuthProvider>().currentUser;
    final auth = context.read<AuthProvider>();

    return Scaffold(
      // Listener catches mouse/keyboard/touch — any input resets the
      // idle timer. Cheaper than wrapping in GestureDetector and works
      // for keyboard nav on web (Flutter web doesn't bubble keys through
      // GestureDetector reliably).
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetIdle(),
        onPointerMove: (_) => _resetIdle(),
        onPointerSignal: (_) => _resetIdle(),
        child: Row(
        children: [
          // ── Sidebar ──────────────────────────────────
          Container(
            width: 240,
            color: AppColors.dark,
            child: Column(
              children: [
                // Brand header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                  child: Row(
                    children: [
                      const Text(
                        'FlyConnect',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ADMIN',
                          style: TextStyle(
                            color: Color(0xFF8A8D9A),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 24),
                ),

                // Nav items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _navItems.length,
                    itemBuilder: (context, index) {
                      final item = _navItems[index];
                      final isActive = location.startsWith(item.route);
                      return _SidebarNavItem(
                        item: item,
                        isActive: isActive,
                        onTap: () => context.go(item.route),
                      );
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                ),

                // User info card with logout
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        child: Text(
                          (user?.name.isNotEmpty == true)
                              ? user!.name[0].toUpperCase()
                              : 'A',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? 'Admin',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Super Admin',
                              style: TextStyle(
                                color: Color(0xFF8A8D9A),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          // Confirm before signing out — admins lose any
                          // in-flight investigation work otherwise.
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              title: const Text('Sign out?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              content: const Text(
                                  'You will need to sign in again to access the admin console.',
                                  style: TextStyle(
                                      color: Color(0xFF8A8D9A), fontSize: 14)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Sign Out'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          if (!context.mounted) return;
                          final ok = await auth.logout();
                          if (!context.mounted) return;
                          if (ok) {
                            context.go('/login');
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(auth.error ?? 'Logout failed'),
                              backgroundColor: AppColors.error,
                            ));
                          }
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        color: const Color(0xFF8A8D9A),
                        tooltip: 'Logout',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Content area ─────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top header bar
                Container(
                  height: 60,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    children: [
                      Text(
                        _pageTitle(location),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => context.go('/admin/notifications'),
                        icon: const Icon(Icons.notifications_outlined),
                        color: AppColors.textSecondary,
                        tooltip: 'Notifications',
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                // Page content
                Expanded(
                  child: Container(
                    color: const Color(0xFFF7F7F7),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // Active indicator bar
                Container(
                  width: 3,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  item.icon,
                  size: 20,
                  color: isActive ? AppColors.primary : const Color(0xFF8A8D9A),
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: isActive ? AppColors.primary : const Color(0xFF8A8D9A),
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
