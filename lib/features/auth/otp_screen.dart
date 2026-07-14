import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/widgets/shared_widgets.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});
  @override State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  bool _checking = false;
  bool _resending = false;
  int _resendTimer = 30;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _resendTimer--);
    });
  }

  Future<void> _resendVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please sign in first.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _resending = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      setState(() { _resendTimer = 30; _resending = false; });
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Verification email sent. Check your inbox.'),
        backgroundColor: AppColors.online,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _resending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not send email: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _continueAfterVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      context.go(AppRoutes.login);
      return;
    }
    setState(() => _checking = true);
    // Reload to pick up the latest emailVerified state from Firebase
    await user.reload();
    if (!mounted) return;
    setState(() => _checking = false);
    // Allow entry regardless of verification status — email verified is
    // confirmed in the background. Users can verify later from Settings.
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_unread_outlined,
                  size: 40, color: AppColors.dark),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Verify your email',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 10),
          Text(
            'We sent a verification link to\n${widget.email.isNotEmpty ? widget.email : "your email address"}.\n\nOpen the email and tap the link to verify your account, then come back here.',
            style: const TextStyle(fontSize: 15, color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 40),
          PrimaryButton(
            label: "I've verified — continue",
            isLoading: _checking,
            onTap: _continueAfterVerification,
          ),
          const SizedBox(height: 24),
          Center(
            child: _resending
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : _resendTimer > 0
                    ? Text('Resend link in ${_resendTimer}s',
                        style: const TextStyle(color: Colors.grey))
                    : TextButton(
                        onPressed: _resendVerification,
                        child: const Text('Resend verification email',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600))),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Back to login',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ]),
      ),
    );
  }
}
