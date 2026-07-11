import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../core/constants/legal_urls.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushLikes = true;
  bool _pushComments = true;
  bool _pushMatches = true;
  bool _pushMessages = true;
  bool _pushEvents = false;
  bool _profilePublic = true;
  bool _showOnNearby = true;
  bool _showAirline = true;
  bool _shareLocation = true;
  bool _approxLocationOnly = true;
  String _nearbyVisibility = 'all'; // 'all', 'friends', 'verified'
  bool _pushSafeCheck = true;
  bool _loadingLogout = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {
      // Fall back to pubspec version if platform call fails
      if (mounted) setState(() => _appVersion = '—');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => Navigator.pop(context)),
        title: const Text('Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: ListView(children: [
        _Section(title: 'Account', children: [
          _Tile(icon: Icons.person_outline, label: 'Edit Profile',
            onTap: () => context.push(AppRoutes.editProfileDetails)),
          _Tile(icon: Icons.lock_outline, label: 'Change Password',
            onTap: () => _changePasswordSheet(context)),
          // Phone/email update tiles hidden for v1.0 — not yet implemented.
          // Re-add here once the update flows exist.
        ]),
        _Section(title: 'Notifications', children: [
          _ToggleTile(icon: Icons.favorite_outline, label: 'Likes', value: _pushLikes,
            onChanged: (v) => setState(() => _pushLikes = v)),
          _ToggleTile(icon: Icons.chat_bubble_outline, label: 'Comments', value: _pushComments,
            onChanged: (v) => setState(() => _pushComments = v)),
          _ToggleTile(icon: Icons.favorite_border, label: 'New Matches', value: _pushMatches,
            onChanged: (v) => setState(() => _pushMatches = v)),
          _ToggleTile(icon: Icons.message_outlined, label: 'Messages', value: _pushMessages,
            onChanged: (v) => setState(() => _pushMessages = v)),
          _ToggleTile(icon: Icons.event_outlined, label: 'Events Near You', value: _pushEvents,
            onChanged: (v) => setState(() => _pushEvents = v)),
          _ToggleTile(icon: Icons.health_and_safety, label: 'SafeCheck Alerts', value: _pushSafeCheck,
            onChanged: (v) => setState(() => _pushSafeCheck = v)),
        ]),
        _Section(title: 'Privacy', children: [
          _ToggleTile(icon: Icons.public, label: 'Public Profile', value: _profilePublic,
            onChanged: (v) => setState(() => _profilePublic = v)),
          _ToggleTile(icon: Icons.location_on_outlined, label: 'Show on Nearby Map', value: _showOnNearby,
            onChanged: (v) => setState(() => _showOnNearby = v)),
          _ToggleTile(icon: Icons.flight, label: 'Show Airline & Position', value: _showAirline,
            onChanged: (v) => setState(() => _showAirline = v)),
          _ToggleTile(icon: Icons.share_location, label: 'Share Location for SafeCheck', value: _shareLocation,
            onChanged: (v) => setState(() => _shareLocation = v)),
          _ToggleTile(icon: Icons.blur_on, label: 'Approximate Location Only', value: _approxLocationOnly,
            onChanged: (v) => setState(() => _approxLocationOnly = v)),
          _Tile(icon: Icons.visibility, label: 'SafeCheck Visibility',
            trailing: Text(
              _nearbyVisibility == 'all' ? 'Everyone'
                : _nearbyVisibility == 'friends' ? 'Friends Only' : 'Verified Users',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showVisibilitySheet(context)),
          _Tile(icon: Icons.block, label: 'Blocked Users',
            onTap: () => _blockedUsersSheet(context)),
          _Tile(icon: Icons.download_for_offline_outlined, label: 'Request My Data',
            onTap: () => _requestDataSheet(context)),
        ]),
        // Developer testing removed for production
        _Section(title: 'Support', children: [
          _Tile(icon: Icons.help_outline, label: 'Help & Support',
            onTap: () => _showInfoSheet(context, 'Help & Support', 'Contact: support@flyconnect.co')),
          _Tile(icon: Icons.description_outlined, label: 'Terms of Service',
            onTap: () => _openUrl(LegalUrls.termsOfService)),
          _Tile(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy',
            onTap: () => _openUrl(LegalUrls.privacyPolicy)),
          _Tile(icon: Icons.info_outline, label: 'App Version',
            trailing: Text(_appVersion.isEmpty ? '…' : _appVersion,
                style: const TextStyle(color: Colors.grey, fontSize: 13))),
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Delete Account', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => _deleteAccountSheet(context))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: ElevatedButton.icon(
            icon: _loadingLogout
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.logout, size: 20),
            label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dark, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              final router = GoRouter.of(context);
              final confirmed = await showConfirmDialog(
                context,
                title: 'Sign out?',
                message: "You'll need to sign in again to access your account.",
                confirmLabel: 'Sign out',
                isDestructive: true,
              );
              if (!confirmed) return;
              if (!mounted) return;
              setState(() => _loadingLogout = true);
              await authProvider.logout();
              router.go(AppRoutes.login);
            })),
      ]),
    );
  }

  void _changePasswordSheet(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _ChangePasswordSheet());
  }

  void _showVisibilitySheet(BuildContext context) {
    showModalBottomSheet(context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('SafeCheck Visibility', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _nearbyVisibility,
            onChanged: (val) {
              setState(() => _nearbyVisibility = val!);
              Navigator.pop(context);
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ...['all', 'friends', 'verified'].map((v) => RadioListTile<String>(
                title: Text(v == 'all' ? 'Everyone' : v == 'friends' ? 'Friends Only' : 'Verified Users Only'),
                value: v,
                activeColor: AppColors.dark,
              )),
            ]),
          ),
        ])));
  }

  /// GDPR / CCPA "right to access" self-serve.
  /// Writes a doc to `gdpr_requests` with type='export'; the admin
  /// Audit panel processes the queue and an admin (or a Cloud Function
  /// when wired) compiles + emails the export.
  void _requestDataSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const Text('Request Your Data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'You can request a copy of all data we hold about you. '
              'Per GDPR / CCPA we will respond within 30 days. The export '
              'is sent to your account email.',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 16),
          const Text('What\'s included:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          _bullet('Your profile (name, email, photos, bio)'),
          _bullet('Your posts, comments, and likes'),
          _bullet('Your chats and SafeCheck history'),
          _bullet('Your trip history and group memberships'),
          _bullet('Audit log of admin actions affecting you (if any)'),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                Navigator.pop(ctx);
                return;
              }
              try {
                await FirebaseFirestore.instance.collection('gdpr_requests').add({
                  'userId': user.uid,
                  'userName': user.displayName ?? '',
                  'userEmail': user.email ?? '',
                  'requestType': 'export',
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                  'notes': 'User-initiated via Settings → Request My Data',
                });
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Request submitted. We will email you within 30 days.'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 4),
                  ));
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Could not submit request: $e'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: const Text('Submit Request',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _blockedUsersSheet(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          const Padding(padding: EdgeInsets.all(16),
            child: Text('Blocked Users', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Expanded(child: ListView(controller: ctrl,
            children: const [Center(child: Padding(padding: EdgeInsets.all(32),
              child: Text('No blocked users', style: TextStyle(color: Colors.grey))))])),
        ])));
  }

  void _showInfoSheet(BuildContext context, String title, String message) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
        ])));
  }

  /// Opens an external URL (Terms / Privacy) in the browser. Shows a SnackBar
  /// if the link can't be opened so the action never silently no-ops.
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await canLaunchUrl(uri) &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')));
    }
  }

  void _deleteAccountSheet(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
  }

}

// Shared helpers for the settings sheets/dialogs. Top-level so the extracted
// sheet widgets (below) can reuse them alongside the screen itself.
Widget _bullet(String text) => Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('\u2022 ', style: TextStyle(color: Colors.black87)),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
        ),
      ]),
    );

InputDecoration _inputDec(String hint) => InputDecoration(
  hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.dark)));

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: Colors.grey, letterSpacing: 0.8))),
    Container(margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: children)),
  ]);
}

class _Tile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback? onTap; final Widget? trailing;
  const _Tile({required this.icon, required this.label, this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 22, color: AppColors.textPrimary),
    title: Text(label, style: const TextStyle(fontSize: 15)),
    // Only show the chevron affordance when the tile is actually tappable.
    trailing: trailing ?? (onTap != null
        ? const Icon(Icons.chevron_right, color: Colors.grey, size: 20)
        : null),
    onTap: onTap,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))));
}

class _ToggleTile extends StatelessWidget {
  final IconData icon; final String label; final bool value; final ValueChanged<bool> onChanged;
  const _ToggleTile({required this.icon, required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 22, color: AppColors.textPrimary),
    title: Text(label, style: const TextStyle(fontSize: 15)),
    trailing: CupertinoSwitch(value: value, activeTrackColor: AppColors.dark, onChanged: onChanged));
}

/// Change-password composer shown in a bottom sheet. Owns its three
/// [TextEditingController]s so they are disposed when the sheet closes
/// (a bare modal builder leaked them). Behavior is otherwise unchanged.
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Capture the messenger up front so it survives the pop + awaits.
    final messenger = ScaffoldMessenger.of(context);
    final current = _currentCtrl.text;
    final newPass = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    // Validation
    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Please fill in all fields'),
        backgroundColor: Colors.red));
      return;
    }
    if (newPass.length < 8) {
      messenger.showSnackBar(const SnackBar(
        content: Text('New password must be at least 8 characters'),
        backgroundColor: Colors.red));
      return;
    }
    if (newPass != confirm) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Passwords do not match'),
        backgroundColor: Colors.red));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Please sign in again to change your password.'),
        backgroundColor: Colors.red));
      return;
    }

    try {
      // Re-authenticate with the current password (Firebase requirement
      // for sensitive operations on sessions older than a few minutes).
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPass);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('Password updated successfully'),
        backgroundColor: AppColors.online));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Current password is incorrect.';
          break;
        case 'weak-password':
          msg = 'New password is too weak.';
          break;
        case 'requires-recent-login':
          msg = 'Please sign out and sign in again, then try.';
          break;
        default:
          msg = e.message ?? 'Could not update password.';
      }
      messenger.showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Change Password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(controller: _currentCtrl, obscureText: true,
          decoration: _inputDec('Current password')),
        const SizedBox(height: 12),
        TextField(controller: _newCtrl, obscureText: true,
          decoration: _inputDec('New password')),
        const SizedBox(height: 12),
        TextField(controller: _confirmCtrl, obscureText: true,
          decoration: _inputDec('Confirm new password')),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.dark,
            padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: _submit,
          child: const Text('Update Password', style: TextStyle(fontWeight: FontWeight.bold)))),
      ]));
  }
}

/// Account-deletion confirmation dialog. Owns its confirm-text controller and
/// the in-flight flag, replacing a [StatefulBuilder] that could not dispose
/// the controller. Behavior (type-DELETE gating, GDPR log, delete flow) is
/// preserved.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _isDeleting = false;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final auth = context.read<AuthProvider>();
    setState(() => _isDeleting = true);
    // GDPR audit trail: record the deletion request before
    // we actually delete (the auth user goes away on next line).
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('gdpr_requests').add({
          'userId': fbUser.uid,
          'userName': fbUser.displayName ?? '',
          'userEmail': fbUser.email ?? '',
          'requestType': 'delete',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'notes': 'User-initiated via Settings → Delete Account',
        });
      } catch (_) {/* non-fatal */}
    }
    final ok = await auth.deleteAccount();
    if (!mounted) return;
    Navigator.pop(context);
    if (ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')));
      router.go(AppRoutes.login);
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(auth.error ?? 'Could not delete account.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Delete your account?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This will permanently:',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          _bullet('Delete your profile, posts, trips, and saved items'),
          _bullet('Remove you from groups, chats, and events'),
          _bullet('Anonymize any posts you made (shown as "[deleted user]")'),
          _bullet('Revoke access to all data linked to this account'),
          const SizedBox(height: 12),
          const Text(
            'This cannot be undone.',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 16),
          const Text(
            'Type DELETE to confirm:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _confirmCtrl,
            decoration: InputDecoration(
              hintText: 'DELETE',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: (_confirmCtrl.text.trim() == 'DELETE' && !_isDeleting)
              ? _confirmDelete
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Delete permanently'),
        ),
      ],
    );
  }
}
