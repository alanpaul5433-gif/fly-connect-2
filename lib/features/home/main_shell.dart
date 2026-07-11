import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/confirm_dialog.dart';

class MainShell extends StatelessWidget {
  static final scaffoldKey = GlobalKey<ScaffoldState>();

  final Widget child;
  const MainShell({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/events')) return 1;
    if (location.startsWith('/match')) return 2;
    if (location.startsWith('/chat')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index, String role) {
    final router = GoRouter.of(context);
    switch (index) {
      case 0: router.go(AppRoutes.home); break;
      case 1: router.go(AppRoutes.events); break;
      case 2: router.go(AppRoutes.match); break;
      case 3: router.go(AppRoutes.chat); break;
      case 4: router.go(AppRoutes.profile); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);

    return Scaffold(
      key: scaffoldKey,
      drawer: _buildSidebar(context),
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.dark.withValues(alpha: 0.08))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _NavItem(assetPath: 'assets/images/nav_home.png', tintAsset: true, index: 0, current: currentIndex, onTap: (i) => _onTap(context, i, 'user')),
              _NavItem(icon: Icons.event_outlined, index: 1, current: currentIndex, onTap: (i) => _onTap(context, i, 'user')),
              GestureDetector(
                onTap: () => context.push(AppRoutes.createPost),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.add_rounded, color: AppColors.dark, size: 28),
                ),
              ),
              _NavItem(assetPath: 'assets/images/nav_match.png', index: 2, current: currentIndex, onTap: (i) => _onTap(context, i, 'user')),
              _NavItem(icon: Icons.person_outline_rounded, index: 4, current: currentIndex, onTap: (i) => _onTap(context, i, 'user')),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) => const AppDrawer();
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFD4F53C), Color(0xFFC8F000)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
                      backgroundColor: AppColors.dark.withValues(alpha: 0.2),
                      child: user?.photoUrl == null ? Text((user != null && user.name.isNotEmpty) ? user.name[0] : 'U',
                          style: const TextStyle(color: AppColors.dark, fontSize: 20)) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? '', style: const TextStyle(
                            color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(user?.airline ?? '', style: TextStyle(
                            color: AppColors.dark.withValues(alpha: 0.6), fontSize: 13)),
                      ],
                    )),
                  ],
                ),
              ),
              const Divider(color: Colors.black12, height: 1),
              const SizedBox(height: 8),
              _SidebarItem(icon: Icons.flight_takeoff, label: 'My Trips',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.trips); }),
              _SidebarItem(icon: Icons.group_outlined, label: 'Groups',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.groupsList); }),
              _SidebarItem(icon: Icons.notifications_outlined, label: 'Notifications',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.notifications); }),
              _SidebarItem(icon: Icons.explore_outlined, label: 'Nearby',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.nearby); }),
              _SidebarItem(icon: Icons.search, label: 'Search',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.search); }),
              _SidebarItem(icon: Icons.book_outlined, label: 'Digital Passport',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.passport); }),
              const Spacer(),
              const Divider(color: Colors.black12, height: 1),
              _SidebarItem(icon: Icons.settings_outlined, label: 'Settings',
                  onTap: () { Navigator.pop(context); context.push(AppRoutes.settings); }),
              _SidebarItem(
                icon: Icons.help_outline,
                label: 'Help & Support',
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                    builder: (_) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Help & Support',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.email_outlined),
                            title: const Text('Email Support'),
                            subtitle: const Text('support@flyconnect.co'),
                            onTap: () => Navigator.pop(context),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.chat_outlined),
                            title: const Text('Live Chat'),
                            subtitle: const Text('Mon–Fri, 9am–6pm EST'),
                            onTap: () => Navigator.pop(context),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.article_outlined),
                            title: const Text('FAQ & Guides'),
                            subtitle: const Text('flyconnect.co/help'),
                            onTap: () => Navigator.pop(context),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
              _SidebarItem(
                icon: Icons.logout,
                label: 'Logout',
                textColor: Colors.red.shade700,
                onTap: () async {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Sign out?',
                    message: "You'll need to sign in again to access your account.",
                    confirmLabel: 'Sign out',
                    isDestructive: true,
                  );
                  if (!confirmed) return;
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  await context.read<AuthProvider>().logout();
                  if (context.mounted) context.go(AppRoutes.login);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData? icon;
  final String? assetPath;
  // When true, a monochrome [assetPath] is recolored to match the active/inactive
  // state (like a Material glyph). When false, the asset keeps its own colors and
  // active/inactive is conveyed via opacity.
  final bool tintAsset;
  final int index;
  final int current;
  final ValueChanged<int> onTap;
  const _NavItem({this.icon, this.assetPath, this.tintAsset = false, required this.index, required this.current, required this.onTap})
      : assert(icon != null || assetPath != null, 'Provide either an icon or an assetPath');

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    final stateColor = active ? AppColors.primary : AppColors.dark.withValues(alpha: 0.4);
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _buildChild(active, stateColor),
      ),
    );
  }

  Widget _buildChild(bool active, Color stateColor) {
    if (assetPath == null) {
      return Icon(icon, color: stateColor, size: 24);
    }
    if (tintAsset) {
      return Image.asset(assetPath!, width: 24, height: 24, fit: BoxFit.contain,
          color: stateColor, colorBlendMode: BlendMode.srcIn);
    }
    return Opacity(
      opacity: active ? 1.0 : 0.4,
      child: Image.asset(assetPath!, width: 24, height: 24, fit: BoxFit.contain),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  const _SidebarItem({required this.icon, required this.label, required this.onTap, this.textColor});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: textColor ?? AppColors.dark, size: 22),
      title: Text(label, style: TextStyle(
        color: textColor ?? AppColors.dark,
        fontWeight: FontWeight.w500, fontSize: 15,
      )),
      onTap: onTap,
      horizontalTitleGap: 8,
      dense: true,
    );
  }
}
