import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Small verified-account indicator, shown next to a name wherever a
/// business (or otherwise admin-verified) account is displayed — profile
/// header, event/group organizer row, etc. One definition so verified status
/// looks the same everywhere it appears.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.verified, color: AppColors.primary, size: size);
}
