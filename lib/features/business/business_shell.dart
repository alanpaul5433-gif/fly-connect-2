import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/widgets/confirm_dialog.dart';

class BusinessShell extends StatelessWidget {
  final Widget child;
  const BusinessShell({super.key, required this.child});

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.local_offer, color: AppColors.dark),
          title: const Text('Create Deal', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); context.push('/promotions/create'); },
        ),
        ListTile(
          leading: const Icon(Icons.event, color: AppColors.dark),
          title: const Text('Create Event', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); context.push('/create-event'); },
        ),
        ListTile(
          leading: const Icon(Icons.group_add, color: AppColors.dark),
          title: const Text('Create Group', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () { Navigator.pop(context); context.push(AppRoutes.createGroup); },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final int current;
    if (location.startsWith('/dashboard')) {
      current = 0;
    } else if (location.startsWith('/promotions')) {
      current = 1;
    } else if (location.startsWith('/business-events')) {
      current = 2;
    } else {
      current = 0;
    }

    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      drawer: _BusinessDrawer(user: user),
      body: Builder(
        builder: (ctx) => Stack(children: [
          child,
          // Hamburger button in top-left
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Scaffold.of(ctx).openDrawer(),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                ),
                child: const Icon(Icons.menu_rounded, size: 22, color: AppColors.dark),
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _BizNavItem(icon: Icons.grid_view_rounded, label: 'Dashboard', active: current == 0,
                onTap: () => GoRouter.of(context).go('/dashboard')),
              _BizNavItem(icon: Icons.local_offer_outlined, label: 'Crew Deals', active: current == 1,
                onTap: () => GoRouter.of(context).go('/promotions')),
              GestureDetector(
                onTap: () => _showQuickActions(context),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.add_rounded, color: AppColors.dark, size: 26),
                ),
              ),
              _BizNavItem(icon: Icons.event_outlined, label: 'Events', active: current == 2,
                onTap: () => GoRouter.of(context).go('/business-events')),
              _BizNavItem(icon: Icons.person_outline, label: 'Profile', active: false,
                onTap: () => context.push('/business-profile')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BusinessDrawer extends StatelessWidget {
  final dynamic user;
  const _BusinessDrawer({this.user});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.dark,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: user?.photoUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(user!.photoUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.business, color: AppColors.dark, size: 30)))
                  : const Icon(Icons.business, color: AppColors.dark, size: 30),
              ),
              const SizedBox(height: 12),
              Text(user?.name ?? 'Business Account',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(user?.email ?? '',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: const Text('Business Account',
                  style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 8),

          // Menu items
          _DrawerItem(icon: Icons.grid_view_rounded, label: 'Dashboard',
            onTap: () { Navigator.pop(context); GoRouter.of(context).go('/dashboard'); }),
          _DrawerItem(icon: Icons.local_offer_outlined, label: 'Crew Deals',
            onTap: () { Navigator.pop(context); GoRouter.of(context).go('/promotions'); }),
          _DrawerItem(icon: Icons.event_outlined, label: 'Events',
            onTap: () { Navigator.pop(context); GoRouter.of(context).go('/business-events'); }),
          _DrawerItem(icon: Icons.group_outlined, label: 'Groups',
            onTap: () { Navigator.pop(context); context.push(AppRoutes.groupsList); }),
          _DrawerItem(icon: Icons.bar_chart_outlined, label: 'Analytics',
            onTap: () { Navigator.pop(context); context.push('/analytics'); }),
          _DrawerItem(icon: Icons.person_outline, label: 'Business Profile',
            onTap: () { Navigator.pop(context); context.push('/business-profile'); }),

          Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: Colors.white12),

          _DrawerItem(icon: Icons.settings_outlined, label: 'Settings',
            onTap: () { Navigator.pop(context); context.push(AppRoutes.settings); }),
          _DrawerItem(icon: Icons.help_outline, label: 'Help & Support',
            onTap: () => Navigator.pop(context)),

          const Spacer(),

          // Logout
          Padding(
            padding: const EdgeInsets.all(20),
            child: GestureDetector(
              onTap: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Sign out?',
                  message: "You'll need to sign in again to access your business dashboard.",
                  confirmLabel: 'Sign out',
                  isDestructive: true,
                );
                if (!confirmed) return;
                if (!context.mounted) return;
                Navigator.pop(context);
                await context.read<AuthProvider>().logout();
                if (!context.mounted) return;
                GoRouter.of(context).go(AppRoutes.login);
              },
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.logout, color: Colors.red, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    leading: Icon(icon, color: Colors.white70, size: 22),
    title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    hoverColor: Colors.white10,
  );
}

class _BizNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _BizNavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: active
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: AppColors.dark, size: 20),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white54, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(
                fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white54)),
            ]),
      ),
    );
  }
}
