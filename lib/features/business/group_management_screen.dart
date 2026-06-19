import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';

class GroupManagementScreen extends StatefulWidget {
  final GroupModel group;
  const GroupManagementScreen({super.key, required this.group});
  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  bool _chatEnabled = true;
  late List<UserModel> _members;

  @override
  void initState() {
    super.initState();
    _members = <UserModel>[];
  }

  void _showBroadcast(BuildContext context) {
    // Capture the host messenger before the sheet route is pushed so the
    // success SnackBar resolves against this screen, not the sheet.
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BroadcastSheet(
        memberCount: _members.length,
        onSend: () => messenger.showSnackBar(
          const SnackBar(content: Text('Message sent to all members'), duration: Duration(seconds: 2))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
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
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onSelected: (val) {
              if (val == 'delete') {
                showDialog(context: context, builder: (_) => AlertDialog(
                  title: const Text('Delete Group'),
                  content: const Text('Are you sure you want to delete this group? This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(onPressed: () { Navigator.pop(context); GoRouter.of(context).pop(); },
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
            const Expanded(child: _StatCard(value: '24', label: 'Posts', icon: Icons.grid_view_outlined)),
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
                  onChanged: (v) {
                    setState(() => _chatEnabled = v);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Chat ${v ? 'enabled' : 'disabled'}'),
                      duration: const Duration(seconds: 2)));
                  },
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
            Text('${_members.length} total', style: AppTextStyles.caption),
          ]),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: ListView.separated(
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
                      if (val == 'remove') setState(() => _members.removeWhere((m) => m.uid == u.uid));
                      if (val == 'admin') {
                        ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${u.name} is now an admin')));
                      }
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

          const Text('Pending Requests', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: const Center(
              child: Text('No pending requests', style: AppTextStyles.caption),
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
class _BroadcastSheet extends StatefulWidget {
  final int memberCount;
  final VoidCallback onSend;
  const _BroadcastSheet({required this.memberCount, required this.onSend});

  @override
  State<_BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<_BroadcastSheet> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSend();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.dark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Send Broadcast', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
