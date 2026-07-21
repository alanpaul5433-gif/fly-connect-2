import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../models/models.dart';
import 'verified_badge.dart';

/// "Hosted by [name] [verified badge]" row shown on event/group details so
/// users can see who created the content and, for a verified business,
/// trust that signal — previously createdBy was stored but never surfaced
/// anywhere in either screen. Tapping navigates to the organizer's profile.
class OrganizerRow extends StatelessWidget {
  final UserModel organizer;
  const OrganizerRow({super.key, required this.organizer});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/users/${organizer.uid}'),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Text('Hosted by ${organizer.name}', style: AppTextStyles.caption),
      if (organizer.isVerified) ...[
        const SizedBox(width: 4),
        const VerifiedBadge(size: 14),
      ],
    ]),
  );
}
