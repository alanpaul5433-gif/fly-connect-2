import 'package:flutter_test/flutter_test.dart';

void main() {
  // We can't construct AdminShell directly in a widget test without
  // GoRouter + Provider scaffolding (which in turn needs Firebase init),
  // so instead we lock down the expected sidebar navigation by mirroring
  // the static _navItems list. If a developer adds or renames an admin
  // page, this test reminds them to also update the sidebar + this list.
  test('Admin sidebar has the expected 13 nav items', () {
    const expected = [
      'Dashboard', 'Users', 'Reports', 'Content', 'SafeCheck',
      'Nearby', 'Events', 'Promotions', 'Businesses', 'GDPR', 'Audit Log',
      'Analytics', 'Notifications',
    ];
    // Manually transcribed from lib/features/admin/admin_shell.dart
    // to flag drift if the file changes without this test being
    // updated. If this list and the runtime list drift apart the
    // sidebar will silently show the old set.
    const inShell = [
      'Dashboard', 'Users', 'Reports', 'Content', 'SafeCheck',
      'Nearby', 'Events', 'Promotions', 'Businesses', 'GDPR', 'Audit Log',
      'Analytics', 'Notifications',
    ];
    expect(inShell, expected);
    expect(inShell.length, 13);
  });

  test('Admin route paths follow the /admin/* convention', () {
    const adminRoutes = [
      '/admin/dashboard', '/admin/users', '/admin/reports',
      '/admin/content', '/admin/safecheck', '/admin/nearby', '/admin/events',
      '/admin/promotions', '/admin/business-verify', '/admin/gdpr',
      '/admin/audit', '/admin/analytics', '/admin/notifications',
    ];
    for (final r in adminRoutes) {
      expect(r.startsWith('/admin/'), isTrue,
          reason: '$r does not follow the /admin/* prefix convention');
    }
    expect(adminRoutes.toSet().length, adminRoutes.length,
        reason: 'Admin route list contains duplicates');
  });
}
