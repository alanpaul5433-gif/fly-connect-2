import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../core/constants/app_colors.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/user_provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _airportCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  String? _selectedAirline;
  String? _selectedPosition;
  File? _pickedImage;
  bool _saving = false;

  static const _airlines = ['American Airlines', 'Delta Air Lines', 'United Airlines',
    'Southwest Airlines', 'JetBlue', 'Alaska Airlines', 'Spirit Airlines', 'Frontier Airlines', 'Other'];
  static const _positions = ['Pilot', 'Co-Pilot', 'Flight Attendant', 'Gate Agent',
    'Ground Crew', 'Baggage Handler', 'Customer Service', 'TSA Officer', 'Air Traffic Control', 'Other'];

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>().currentUser;
    if (user != null) {
      _nameCtrl.text = user.name;
      _bioCtrl.text = user.bio ?? '';
      _airportCtrl.text = user.airport ?? '';
      _cityCtrl.text = user.city ?? '';
      _stateCtrl.text = user.state ?? '';
      _selectedAirline = user.airline;
      _selectedPosition = user.position;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _bioCtrl.dispose(); _airportCtrl.dispose();
    _cityCtrl.dispose(); _stateCtrl.dispose(); super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ]),
      ),
    );
    if (source == null) return;
    final img = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (img != null) setState(() => _pickedImage = File(img.path));
  }

  Future<void> _save() async {
    // Capture the provider before any await — using `context` across an async
    // gap is unsafe (the widget may unmount mid-upload).
    final userProvider = context.read<UserProvider>();
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    final updates = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'airline': _selectedAirline,
      'position': _selectedPosition,
      'airport': _airportCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'state': _stateCtrl.text.trim(),
    };
    try {
      // Upload the newly-picked avatar first; only add photoUrl to the update
      // if it succeeds. A failed upload throws → the catch below reports it,
      // instead of silently saving the rest and dropping the photo.
      if (_pickedImage != null) {
        final url = await userProvider.uploadProfilePhoto(await _pickedImage!.readAsBytes());
        if (url != null) updates['photoUrl'] = url;
      }
      await userProvider.updateProfile(uid, updates);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!'), backgroundColor: Colors.green));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save profile. Please try again.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<UserProvider>().currentUser;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context)),
        title: const Text('Edit Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              // White AppBar — primary fails AA. Use dark for the Save label.
              : const Text('Save', style: TextStyle(color: AppColors.dark, fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Photo picker
          Center(child: GestureDetector(
            onTap: _pickPhoto,
            child: Stack(children: [
              CircleAvatar(radius: 50, backgroundColor: AppColors.backgroundGrey,
                backgroundImage: _pickedImage != null ? FileImage(_pickedImage!)
                  : (user?.photoUrl != null ? NetworkImage(user!.photoUrl!) as ImageProvider : null),
                child: _pickedImage == null && user?.photoUrl == null
                  ? Text(user?.name.isNotEmpty == true ? user!.name[0] : '?',
                      style: const TextStyle(fontSize: 40, color: AppColors.textSecondary)) : null),
              // Camera FAB on the avatar — flip to dark so the button has
              // 3:1 contrast against the white surrounding background
              // (WCAG 1.4.11 non-text contrast for UI components).
              Positioned(bottom: 0, right: 0,
                child: Container(width: 32, height: 32,
                  decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, size: 16, color: AppColors.primary))),
            ]))),
          const SizedBox(height: 28),
          _label('Full Name'),
          _field(controller: _nameCtrl, hint: 'Your full name'),
          const SizedBox(height: 16),
          _label('Bio'),
          _field(controller: _bioCtrl, hint: 'Tell people about yourself...', maxLines: 3),
          const SizedBox(height: 16),
          _label('Airline'),
          _dropdown(value: _selectedAirline, hint: 'Select airline', items: _airlines,
            onChanged: (v) => setState(() => _selectedAirline = v)),
          const SizedBox(height: 16),
          _label('Position'),
          _dropdown(value: _selectedPosition, hint: 'Select position', items: _positions,
            onChanged: (v) => setState(() => _selectedPosition = v)),
          const SizedBox(height: 16),
          _label('Home Airport (IATA code)'),
          _field(controller: _airportCtrl, hint: 'e.g. JFK, LAX, ORD'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('City'),
              _field(controller: _cityCtrl, hint: 'City'),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('State'),
              _field(controller: _stateCtrl, hint: 'State'),
            ])),
          ]),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)));

  Widget _field({required TextEditingController controller, required String hint, int maxLines = 1}) =>
    TextField(controller: controller, maxLines: maxLines,
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.dark, width: 1.5))));

  Widget _dropdown({required String? value, required String hint, required List<String> items, required ValueChanged<String?> onChanged}) =>
    DropdownButtonFormField<String>(initialValue: value, hint: Text(hint, style: const TextStyle(color: Colors.grey)),
      decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.dark))),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
      onChanged: onChanged);
}
