import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/group_provider.dart';

class GroupManagementScreen extends StatefulWidget {
  final GroupModel group;
  const GroupManagementScreen({super.key, required this.group});
  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  late bool _chatEnabled;
  List<UserModel> _members = [];
  bool _loadingMembers = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _chatEnabled = widget.group.chatEnabled;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final members = await context.read<GroupProvider>().fetchMembers(widget.group.members);
    if (mounted) setState(() { _members = members; _loadingMembers = false; });
  }

  bool get _canManage {
    final uid = context.read<AuthProvider>().currentUser?.uid;
    return uid != null && (widget.group.createdBy == uid || widget.group.admins.contains(uid));
  }

  Future<void> _deleteGroup() async {
    setState(() => _deleting = true);
    final groupProvider = context.read<GroupProvider>();
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await groupProvider.deleteGroup(widget.group.id);
      router.pop();
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete group. Try again.')));
    }
  }

  Future<void> _toggleChat(bool v) async {
    final prev = _chatEnabled;
    setState(() => _chatEnabled = v);
    try {
      await context.read<GroupProvider>().setChatEnabled(widget.group.id, v);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Chat ${v ? 'enabled' : 'disabled'}'),
          duration: const Duration(seconds: 2)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _chatEnabled = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update chat setting.')));
      }
    }
  }

  Future<void> _removeMember(UserModel u) async {
    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _members.removeWhere((m) => m.uid == u.uid));
    try {
      await groupProvider.removeMember(widget.group.id, u.uid);
      messenger.showSnackBar(SnackBar(content: Text('${u.name} removed'), duration: const Duration(seconds: 2)));
    } catch (_) {
      if (mounted) setState(() => _members.add(u));
      messenger.showSnackBar(const SnackBar(content: Text('Could not remove member. Try again.')));
    }
  }

  Future<void> _makeAdmin(UserModel u) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<GroupProvider>().makeAdmin(widget.group.id, u.uid);
      messenger.showSnackBar(SnackBar(content: Text('${u.name} is now an admin')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update admin status.')));
    }
  }

  Future<bool> _sendBroadcast(String text) async {
    try {
      await context.read<GroupProvider>().sendBroadcast(widget.group.id, text);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _showBroadcast(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BroadcastSheet(memberCount: _members.length, onSend: _sendBroadcast),
    ).then((sent) {
      if (sent == true) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Broadcast saved — members will see it in the group'),
          duration: Duration(seconds: 2)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;

    if (!_canManage) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop())),
        body: const Center(child: Text("You don't have permission to manage this group.")),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: Text(g.name, style: AppTextStyles.labelLarge),
        actions: [
          PopupMenuButton<String>(
            icon: _deleting
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : const Icon(Icons.more_vert, color: Colors.black),
            onSelected: (val) {
              if (val == 'delete') {
                showDialog(context: context, builder: (dialogCtx) => AlertDialog(
                  title: const Text('Delete Group'),
                  content: const Text('Are you sure you want to delete this group? This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () { Navigator.pop(dialogCtx); _deleteGroup(); },
                      child: const Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete Group', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Stats row
          Row(children: [
            Expanded(child: _StatCard(value: g.memberCount.toString(), label: 'Members', icon: Icons.people_outline)),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(
              value: _chatEnabled ? 'Enabled' : 'Disabled',
              label: 'Chat Status',
              icon: Icons.chat_bubble_outline,
            )),
          ]),

          const SizedBox(height: 20),

          // Chat toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Group Chat', style: AppTextStyles.labelMedium),
                  SizedBox(height: 2),
                  Text('Allow members to chat in this group', style: AppTextStyles.caption),
                ])),
                CupertinoSwitch(
                  value: _chatEnabled,
                  activeTrackColor: AppColors.primary,
                  onChanged: _toggleChat,
                ),
              ]),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.campaign, color: AppColors.primary),
                title: const Text('Broadcast Message', style: AppTextStyles.labelMedium),
                subtitle: const Text('Send to all members', style: AppTextStyles.caption),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onTap: () => _showBroadcast(context),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // Members section
          Row(children: [
            const Text('Members', style: AppTextStyles.labelLarge),
            const Spacer(),
            Text(
              _loadingMembers ? 'Loading…' : '${_members.length} of ${g.memberCount} shown',
              style: AppTextStyles.caption),
          ]),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: _loadingMembers
              ? const Padding(padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
              : _members.isEmpty
                ? const Padding(padding: EdgeInsets.all(24),
                    child: Center(child: Text('No members yet', style: AppTextStyles.caption)))
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _members.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                    itemBuilder: (_, i) {
                      final u = _members[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.dark,
                          backgroundImage: u.photoUrl != null ? NetworkImage(u.photoUrl!) : null,
                          child: u.photoUrl == null
                            ? Text(u.name.isNotEmpty ? u.name[0] : '?',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))
                            : null,
                        ),
                        title: Text(u.name, style: AppTextStyles.labelMedium),
                        subtitle: Text('${u.airline ?? ''} · ${u.position ?? ''}', style: AppTextStyles.caption),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
                          onSelected: (val) {
                            if (val == 'view') context.push('/users/${u.uid}');
                            if (val == 'remove') _removeMember(u);
                            if (val == 'admin') _makeAdmin(u);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'view', child: Text('View Profile')),
                            PopupMenuItem(value: 'remove', child: Text('Remove from Group', style: TextStyle(color: Colors.red))),
                            PopupMenuItem(value: 'admin', child: Text('Make Admin')),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _StatCard({required this.value, required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(height: 8),
        Text(value, style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
        Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70)),
      ]),
    );
  }
}

/// Broadcast composer shown in a bottom sheet. Owns its [TextEditingController]
/// so it is disposed when the sheet closes (a bare modal builder leaks it).
/// [onSend] performs the real Firestore write and reports success/failure;
/// the sheet stays open and shows an inline error on failure instead of
/// popping and claiming success regardless.
class _BroadcastSheet extends StatefulWidget {
  final int memberCount;
  final Future<bool> Function(String text) onSend;
  const _BroadcastSheet({required this.memberCount, required this.onSend});

  @override
  State<_BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<_BroadcastSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() { _sending = true; _failed = false; });
    final ok = await widget.onSend(text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() { _sending = false; _failed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Broadcast Message', style: AppTextStyles.labelLarge),
        const SizedBox(height: 4),
        Text('Send to all ${widget.memberCount} members', style: AppTextStyles.caption),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Write your message...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary)),
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: 8),
          const Text('Could not send. Try again.', style: TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _sending ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.dark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send Broadcast', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
