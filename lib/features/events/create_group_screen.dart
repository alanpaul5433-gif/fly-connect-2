import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/group_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group title')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please sign in to create a group.'),
        backgroundColor: Colors.red));
      return;
    }
    if (auth.userRole != 'business' && auth.userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Only business accounts can create groups.'),
        backgroundColor: Colors.red));
      return;
    }
    if (auth.userRole == 'business' && !user.isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your business account is pending verification. '
            'You\'ll be able to create groups once an admin approves it.'),
        backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    final tagsRaw = _tagsCtrl.text.trim();
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final newGroup = GroupModel(
      id: 'grp_${DateTime.now().millisecondsSinceEpoch}',
      name: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? 'A new group for aviation professionals.' : _descCtrl.text.trim(),
      createdBy: user.uid,
      memberCount: 1,
      tags: tags,
      members: [user.uid],
      isPinned: false,
      createdAt: DateTime.now(),
    );
    try {
      await context.read<GroupProvider>().createGroup(newGroup);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group created successfully!'), duration: Duration(seconds: 2)));
      GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to create group: $e'),
        backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: const Text('Create Group', style: AppTextStyles.labelLarge),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Group Name *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          _buildField(_titleCtrl, 'e.g. Delta Pilots Network'),
          const SizedBox(height: 14),

          const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          _buildField(_descCtrl, 'What is this group about?', maxLines: 4),
          const SizedBox(height: 14),

          const Text('Tags', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          _buildField(_tagsCtrl, 'e.g. pilots, delta, networking (comma separated)'),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dark, foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : const Text('Create Group', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, {int maxLines = 1}) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}
