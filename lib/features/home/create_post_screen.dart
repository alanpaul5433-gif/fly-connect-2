import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/group_provider.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _captionController = TextEditingController();
  final _locationController = TextEditingController();
  Uint8List? _imageBytes;
  String _audience = 'Everyone';
  String? _selectedGroupId;
  String? _selectedGroupName;
  bool _loading = false;

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _post() async {
    if (_captionController.text.trim().isEmpty && _imageBytes == null) return;
    setState(() => _loading = true);

    final provider = context.read<PostProvider>();

    try {
      // Upload image to Firebase Storage if present
      List<String> mediaUrls = const [];
      if (_imageBytes != null) {
        final url = await provider.uploadPostImage(_imageBytes!);
        if (url != null) {
          mediaUrls = [url];
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Image upload failed. Posting without image.'),
            backgroundColor: Colors.red,
          ));
        }
      }

      await provider.createPost(
        caption: _captionController.text.trim(),
        mediaUrls: mediaUrls,
        mediaType: mediaUrls.isNotEmpty ? 'image' : 'text',
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        groupId: _selectedGroupId,
        audience: _audience,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not create post. Please try again.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showGroupPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Post to a Group', style: AppTextStyles.h4),
            ),
            const SizedBox(height: 8),
            ...context.read<GroupProvider>().myGroups.map((g) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.dark,
                child: Text(g.name.isNotEmpty ? g.name[0] : '?',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              title: Text(g.name, style: AppTextStyles.labelMedium),
              subtitle: Text('${g.memberCount} members',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              trailing: _selectedGroupId == g.id
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() {
                  _selectedGroupId = g.id;
                  _selectedGroupName = g.name;
                });
                Navigator.pop(ctx);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.dark),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('New Post', style: AppTextStyles.h4),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _loading ? null : _post,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4F53C),
                      foregroundColor: const Color(0xFF1A1D27),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      minimumSize: const Size(80, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A1D27)),
                          )
                        : const Text('Share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── User Row ─────────────────────────────
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.dark,
                          backgroundImage: user?.photoUrl != null
                              ? NetworkImage(user!.photoUrl!)
                              : null,
                          child: user?.photoUrl == null
                              ? Text(
                                  user?.name.isNotEmpty == true ? user!.name[0] : 'U',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?.name ?? 'You', style: AppTextStyles.labelMedium),
                              Text(
                                [user?.airline, user?.position]
                                    .where((s) => s != null && s.isNotEmpty)
                                    .join(' · '),
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _audience,
                          underline: const SizedBox(),
                          style: const TextStyle(color: AppColors.dark, fontSize: 12),
                          items: ['Everyone', 'Connections', 'Only me']
                              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => setState(() => _audience = v!),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Caption Field ─────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: _captionController,
                        minLines: 3,
                        maxLines: 6,
                        // Caps post bodies at 2,000 chars. Firestore docs are
                        // limited to ~1 MB but our model docs include lots of
                        // metadata, so we leave headroom. UI counter shows
                        // remaining characters.
                        maxLength: 2000,
                        style: const TextStyle(fontSize: 15, color: Colors.black87),
                        decoration: const InputDecoration(
                          hintText: "What's on your mind?",
                          hintStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide(color: Color(0xFF1A1D27), width: 1),
                          ),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Media Area ───────────────────────────
                    Container(
                      height: 220,
                      margin: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: AppColors.dark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Image or empty state
                          if (_imageBytes != null)
                            Image.memory(_imageBytes!, fit: BoxFit.cover)
                          else
                            const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: AppColors.primary,
                                    child: Icon(Icons.camera_alt_outlined,
                                        color: AppColors.dark, size: 26),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Tap to add photo or video',
                                    style: TextStyle(
                                        color: Colors.white60, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),

                          // Bottom overlay buttons
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black54, Colors.transparent],
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _MediaButton(
                                    icon: Icons.photo_library_outlined,
                                    label: 'Gallery',
                                    onTap: _pickFromGallery,
                                  ),
                                  _MediaButton(
                                    icon: Icons.camera_alt_outlined,
                                    label: 'Camera',
                                    onTap: () async {
                                      final picker = ImagePicker();
                                      final picked = await picker.pickImage(
                                          source: ImageSource.camera);
                                      if (picked != null) {
                                        final bytes = await picked.readAsBytes();
                                        setState(() => _imageBytes = bytes);
                                      }
                                    },
                                  ),
                                  _MediaButton(
                                    icon: Icons.format_list_bulleted,
                                    label: 'Text only',
                                    onTap: () =>
                                        setState(() => _imageBytes = null),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Details Rows ─────────────────────────
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      child: TextField(
                        controller: _locationController,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.dark),
                        decoration: InputDecoration(
                          hintText: 'Add location',
                          hintStyle: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.backgroundGrey),
                    _DetailRow(
                      icon: Icons.group_outlined,
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary, size: 20),
                      onTap: _showGroupPicker,
                      child: Text(
                        _selectedGroupName ?? 'Post to a group (optional)',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _selectedGroupName != null
                              ? AppColors.dark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Tags Row ─────────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Airline chip
                          if (user?.airline != null && user!.airline!.isNotEmpty)
                            _TagChip(
                              label: user.airline!,
                              backgroundColor: AppColors.dark,
                              labelColor: AppColors.primary,
                            ),
                          const SizedBox(width: 8),
                          const _TagChip(
                            label: '#LayoverLife',
                            backgroundColor: AppColors.dark,
                            labelColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}

// ── Helper widgets ───────────────────────────────────────────

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MediaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.icon,
    required this.child,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(child: child),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color labelColor;

  const _TagChip({
    required this.label,
    required this.backgroundColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: AppTextStyles.caption.copyWith(
              color: labelColor, fontWeight: FontWeight.w600)),
    );
  }
}
