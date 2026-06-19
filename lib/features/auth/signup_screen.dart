import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../core/constants/legal_urls.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/providers/auth_provider.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  int _step = 1;
  bool _loading = false;
  String _role = 'user';
  bool _agreedToTerms = false;
  DateTime? _dob;

  /// Minimum age to use FlyConnect. We require 18+ because:
  ///   • Match feature includes dating → liability for minors
  ///   • Business users (paid accounts) require legal capacity
  /// COPPA forbids us collecting PII from under-13 regardless,
  /// so anything under 18 is rejected outright (no grey area).
  static const int _minAge = 18;

  int _ageInYears(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    final hadBirthdayThisYear = now.month > dob.month ||
        (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Your date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _airportCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _bizNameCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  bool _obscure = true;

  String? _selectedAirline;
  String? _selectedPosition;
  String? _selectedCategory;

  static const _airlines = ['American Airlines', 'Delta Air Lines', 'United Airlines',
    'Southwest Airlines', 'JetBlue', 'Alaska Airlines', 'Spirit Airlines', 'Other'];
  static const _positions = ['Pilot', 'Co-Pilot', 'Flight Attendant', 'Gate Agent',
    'Ground Crew', 'Baggage Handler', 'Customer Service', 'TSA Officer', 'Other'];
  static const _categories = ['Restaurant', 'Hotel', 'Transport', 'Lounge',
    'Entertainment', 'Retail', 'Other'];

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose();
    _phoneCtrl.dispose(); _airportCtrl.dispose(); _cityCtrl.dispose();
    _stateCtrl.dispose(); _bioCtrl.dispose();
    _bizNameCtrl.dispose(); _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _signupWithGoogle() async {
    if (!_agreedToTerms) {
      _showConsentRequired();
      return;
    }
    setState(() => _loading = true);
    final ok = await context.read<AuthProvider>().signInWithGoogle(role: _role);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      final role = context.read<AuthProvider>().userRole;
      context.go(role == 'business' ? '/dashboard'
          : role == 'admin' ? '/admin/dashboard'
          : AppRoutes.home);
    } else if (context.read<AuthProvider>().error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<AuthProvider>().error!),
        backgroundColor: Colors.red));
    }
  }

  Future<void> _signupWithApple() async {
    if (!_agreedToTerms) {
      _showConsentRequired();
      return;
    }
    setState(() => _loading = true);
    final ok = await context.read<AuthProvider>().signInWithApple(role: _role);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      final role = context.read<AuthProvider>().userRole;
      context.go(role == 'business' ? '/dashboard'
          : role == 'admin' ? '/admin/dashboard'
          : AppRoutes.home);
    } else if (context.read<AuthProvider>().error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<AuthProvider>().error!),
        backgroundColor: Colors.red));
    }
  }

  void _nextStep() {
    if (_role == 'user') {
      if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')));
        return;
      }
    } else {
      if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')));
        return;
      }
    }

    // Email format check
    final email = _emailCtrl.text.trim();
    final emailOk = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!emailOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')));
      return;
    }

    // Password minimum strength
    if (_passwordCtrl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters')));
      return;
    }

    // Age gate — users only. Business accounts have a separate KYC.
    if (_role == 'user') {
      if (_dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your date of birth')));
        return;
      }
      final age = _ageInYears(_dob!);
      if (age < _minAge) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'You must be at least $_minAge years old to use FlyConnect.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ));
        return;
      }
    }

    // Terms & Privacy must be accepted to create an account
    if (!_agreedToTerms) {
      _showConsentRequired();
      return;
    }

    setState(() => _step = 2);
  }

  void _showConsentRequired() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Please agree to the Terms of Service and Privacy Policy to continue.'),
      backgroundColor: Colors.red,
      duration: Duration(seconds: 3),
    ));
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    bool ok;
    if (_role == 'business') {
      final bizName = _bizNameCtrl.text.trim().isNotEmpty ? _bizNameCtrl.text.trim() : _nameCtrl.text.trim();
      final bizBio = [
        if (_selectedCategory != null) _selectedCategory!,
        if (_websiteCtrl.text.trim().isNotEmpty) _websiteCtrl.text.trim(),
        if (_bioCtrl.text.trim().isNotEmpty) _bioCtrl.text.trim(),
      ].join(' · ');
      ok = await auth.signup(
        name: bizName,
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
        role: 'business',
        bio: bizBio.isEmpty ? null : bizBio,
      );
    } else {
      ok = await auth.signup(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        airline: _selectedAirline,
        airport: _airportCtrl.text.trim().isEmpty ? null : _airportCtrl.text.trim(),
        position: _selectedPosition,
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        dob: _dob,
      );
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      context.go(_role == 'business' ? '/dashboard' : AppRoutes.home);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.read<AuthProvider>().error ?? 'Signup failed'),
        backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 20),
          Row(children: List.generate(2, (i) => Container(
            width: i < _step ? 28 : 8, height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: i < _step ? AppColors.primary : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(100))))),
          const SizedBox(height: 24),
          Text(_step == 1 ? 'Create Account' : (_role == 'business' ? 'Your Business' : 'Your Profile'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_step == 1 ? 'Join the airport community' : (_role == 'business' ? 'Tell us about your business' : 'Tell us about your role'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(height: 28),

          if (_step == 1) ...[
            // Role selector
            Row(children: [
              Expanded(child: _RoleCard(
                icon: Icons.airplanemode_active,
                title: 'Crew Member',
                subtitle: 'Join as airline staff',
                selected: _role == 'user',
                onTap: () => setState(() => _role = 'user'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _RoleCard(
                icon: Icons.store_outlined,
                title: 'Business',
                subtitle: 'Promote your business',
                selected: _role == 'business',
                onTap: () => setState(() => _role = 'business'),
              )),
            ]),
            const SizedBox(height: 20),
            if (_role == 'user') ...[
              Semantics(
                textField: true,
                label: 'Full name, required',
                child: AppTextField(hint: 'Full Name', controller: _nameCtrl,
                  prefixIcon: const Icon(Icons.person_outline, size: 20)),
              ),
              const SizedBox(height: 14),
            ],
            Semantics(
              textField: true,
              label: 'Email address, required',
              child: AppTextField(hint: 'Email Address', controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: const Icon(Icons.email_outlined, size: 20)),
            ),
            const SizedBox(height: 14),
            if (_role == 'user') ...[
              Semantics(
                textField: true,
                label: 'Phone number, optional',
                child: AppTextField(hint: 'Phone Number (optional)', controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20)),
              ),
              const SizedBox(height: 14),
            ],
            Semantics(
              textField: true,
              label: 'Password, required, minimum 8 characters',
              child: AppTextField(hint: 'Password', controller: _passwordCtrl,
                obscureText: _obscure,
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure))),
            ),
            if (_role == 'user') ...[
              const SizedBox(height: 14),
              // Age gate — required for users. 18+ enforced in _nextStep.
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.inputBorder),
                  ),
                  child: Row(children: [
                    const Icon(Icons.cake_outlined, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _dob == null
                            ? 'Date of birth (must be 18+)'
                            : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 14,
                          color: _dob == null
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.textSecondary),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Terms & Privacy consent \u2014 required for signup (App Store 5.1.1 / Play Data Safety)
            InkWell(
              onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreedToTerms,
                      onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                      activeColor: AppColors.primary,
                      checkColor: AppColors.dark,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 13, height: 1.4),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms of Service',
                              style: const TextStyle(
                                  color: AppColors.dark,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(
                                    Uri.parse(LegalUrls.termsOfService),
                                    mode: LaunchMode.externalApplication),
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                  color: AppColors.dark,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(
                                    Uri.parse(LegalUrls.privacyPolicy),
                                    mode: LaunchMode.externalApplication),
                            ),
                            const TextSpan(
                                text: ', and I consent to FlyConnect processing my profile, location and content in accordance with them.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Continue', onTap: _nextStep),
            const SizedBox(height: 20),
            // Divider
            Row(children: [
              const Expanded(child: Divider()),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Or sign up with', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Sign up with Google',
                  child: SocialLoginButton(
                    icon: const Text('G', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4285F4))),
                    onTap: _loading ? null : _signupWithGoogle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Sign up with Apple',
                  child: SocialLoginButton(
                    icon: const Icon(Icons.apple, size: 20),
                    onTap: _loading ? null : _signupWithApple,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Center(child: GestureDetector(
              onTap: () => context.go(AppRoutes.login),
              child: RichText(text: const TextSpan(
                style: TextStyle(fontSize: 14, color: Colors.grey),
                children: [
                  TextSpan(text: 'Already have an account? '),
                  TextSpan(text: 'Login', style: TextStyle(
                    color: AppColors.dark, fontWeight: FontWeight.bold)),
                ])))),
          ] else if (_role == 'business') ...[
            AppTextField(hint: 'Business Name', controller: _bizNameCtrl,
              prefixIcon: const Icon(Icons.store_outlined, size: 20)),
            const SizedBox(height: 14),
            _label('Category'),
            _dropdown(_selectedCategory, 'Select category', _categories,
              (v) => setState(() => _selectedCategory = v)),
            const SizedBox(height: 14),
            AppTextField(hint: 'Website (optional)', controller: _websiteCtrl,
              keyboardType: TextInputType.url,
              prefixIcon: const Icon(Icons.language_outlined, size: 20)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: AppTextField(hint: 'City', controller: _cityCtrl)),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(hint: 'State', controller: _stateCtrl)),
            ]),
            const SizedBox(height: 14),
            AppTextField(hint: 'Tell people about your business', controller: _bioCtrl, maxLines: 3, maxLength: 500),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Create Account', isLoading: _loading, onTap: _submit),
            const SizedBox(height: 14),
            Center(child: TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('← Back', style: TextStyle(color: Colors.grey)))),
          ] else ...[
            _label('Airline'),
            _dropdown(_selectedAirline, 'Select your airline', _airlines,
              (v) => setState(() => _selectedAirline = v)),
            const SizedBox(height: 14),
            _label('Position / Role'),
            _dropdown(_selectedPosition, 'Select your role', _positions,
              (v) => setState(() => _selectedPosition = v)),
            const SizedBox(height: 14),
            AppTextField(hint: 'Home Airport (e.g. JFK, LAX)', controller: _airportCtrl,
              prefixIcon: const Icon(Icons.flight, size: 20)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: AppTextField(hint: 'City', controller: _cityCtrl)),
              const SizedBox(width: 12),
              Expanded(child: AppTextField(hint: 'State', controller: _stateCtrl)),
            ]),
            const SizedBox(height: 14),
            AppTextField(hint: 'Bio (optional)', controller: _bioCtrl, maxLines: 3, maxLength: 300),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Create Account', isLoading: _loading, onTap: _submit),
            const SizedBox(height: 14),
            Center(child: TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('← Back', style: TextStyle(color: Colors.grey)))),
          ],
          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(
      fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)));

  Widget _dropdown(String? value, String hint, List<String> items, ValueChanged<String?> onChange) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      hint: Text(hint, style: const TextStyle(color: Colors.grey)),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dark))),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
      onChanged: onChange);
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _RoleCard({required this.icon, required this.title, required this.subtitle,
    required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A1D27) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF1A1D27) : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: selected ? const Color(0xFFD4F53C) : Colors.grey, size: 26),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(
            color: selected ? const Color(0xFFD4F53C) : Colors.black87,
            fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(
            color: selected ? Colors.white60 : Colors.grey.shade500,
            fontSize: 11)),
        ]),
      ),
    );
  }
}
