import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'cached_image.dart';

// ── Primary Button ──────────────────────────────────────────────────────────
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final double? width;
  final Color? backgroundColor;
  final Color? textColor;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.width,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.primary,
          foregroundColor: textColor ?? AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.textPrimary,
                ),
              )
            : Text(label, style: AppTextStyles.button.copyWith(color: textColor ?? AppColors.textPrimary)),
      ),
    );
  }
}

// ── App Text Field ────────────────────────────────────────────────────────────
class AppTextField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final int? maxLines;
  /// Hard character cap. Defaults to null (uncapped) so the existing
  /// usages stay backward-compatible. Setting this also surfaces the
  /// "n / max" counter under the field.
  final int? maxLength;

  const AppTextField({
    super.key,
    required this.hint,
    this.controller,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.hint,
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(maxLines != null && maxLines! > 1 ? 16 : 100),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(maxLines != null && maxLines! > 1 ? 16 : 100),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(maxLines != null && maxLines! > 1 ? 16 : 100),
          borderSide: const BorderSide(color: AppColors.dark, width: 1.5),
        ),
        filled: true,
        fillColor: AppColors.background,
      ),
    );
  }
}

// ── Social Login Button ───────────────────────────────────────────────────────
class SocialLoginButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;

  const SocialLoginButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.inputBorder),
        ),
        child: Center(child: icon),
      ),
    );
  }
}

// ── App Header / TopBar ───────────────────────────────────────────────────────
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showBack;
  final List<Widget>? actions;
  final bool showMenuIcon;
  final VoidCallback? onMenuTap;

  const AppTopBar({
    super.key,
    this.title,
    this.showBack = false,
    this.actions,
    this.showMenuIcon = false,
    this.onMenuTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 20, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            )
          : showMenuIcon
              ? GestureDetector(
                  onTap: onMenuTap ?? () => Scaffold.of(context).openDrawer(),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 22, height: 2.5, color: AppColors.textPrimary, margin: const EdgeInsets.only(bottom: 5)),
                        Container(width: 16, height: 2.5, color: AppColors.textPrimary),
                      ],
                    ),
                  ),
                )
              : null,
      title: title != null
          ? Text(title!, style: AppTextStyles.labelLarge)
          : null,
      actions: actions,
    );
  }
}

// ── Notification + Chat action icons ─────────────────────────────────────────
class TopBarActions extends StatelessWidget {
  final bool showSearch;
  final bool showChat;

  const TopBarActions({super.key, this.showSearch = true, this.showChat = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showSearch)
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textPrimary, size: 24),
            onPressed: () => context.push('/search'),
          ),
        _BadgeIcon(icon: Icons.notifications_outlined, count: 15, onTap: () => GoRouter.of(context).push('/notifications')),
        if (showChat) _BadgeIcon(icon: Icons.chat_bubble_outline, count: 15, onTap: () => GoRouter.of(context).push('/chat')),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback? onTap;

  const _BadgeIcon({required this.icon, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(icon, color: AppColors.textPrimary, size: 24),
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.badge,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  count > 9 ? '9+' : count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── User Avatar ───────────────────────────────────────────────────────────────
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final bool isOnline;
  final bool isLive;
  final bool isSelected;

  const UserAvatar({
    super.key,
    this.imageUrl,
    this.radius = 28,
    this.isOnline = false,
    this.isLive = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: AppColors.primary, width: 2.5)
                : isLive
                    ? Border.all(color: AppColors.error, width: 2)
                    : Border.all(color: Colors.transparent, width: 0),
          ),
          child: CachedAvatar(
            url: imageUrl,
            radius: radius,
            backgroundColor: AppColors.backgroundGrey,
            fallback: Icon(Icons.person, size: radius, color: AppColors.textSecondary),
          ),
        ),
        if (isOnline)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        if (isLive)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Live',
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
/// Consistent empty-state placeholder used across all feature screens.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.backgroundGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: AppTextStyles.labelLarge,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTextStyles.h4),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              children: [
                Text(actionLabel!, style: AppTextStyles.labelSmall),
                const Icon(Icons.arrow_forward, size: 14, color: AppColors.textSecondary),
              ],
            ),
          ),
      ],
    );
  }
}
