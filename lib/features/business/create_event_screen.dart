import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/event_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});
  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _requirementsCtrl = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _requirementsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in title and location')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please sign in to create an event.'),
        backgroundColor: Colors.red));
      return;
    }
    if (auth.userRole != 'business' && auth.userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Only business accounts can create events.'),
        backgroundColor: Colors.red));
      return;
    }
    if (auth.userRole == 'business' && !user.isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your business account is pending verification. '
            'You\'ll be able to create events once an admin approves it.'),
        backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    final req = _requirementsCtrl.text.trim();
    final newEvent = EventModel(
      id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? 'No description provided.' : _descCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      date: _date,
      time: _time.format(context),
      createdBy: user.uid,
      rsvpCount: 0,
      requirements: req.isEmpty ? [] : req.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList(),
      isFeatured: false,
      createdAt: DateTime.now(),
    );
    try {
      await context.read<EventProvider>().addEvent(newEvent);
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event created successfully!'), duration: Duration(seconds: 2)));
      GoRouter.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to create event: $e'),
        backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, MMM d, y');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: const Text('Create Event', style: AppTextStyles.labelLarge),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cover placeholder
          Container(
            height: 160, width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.backgroundGrey,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.textSecondary),
              SizedBox(height: 6),
              Text('Add Cover Image', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ])),
          ),
          const SizedBox(height: 20),

          const _Label('Event Title *'),
          const SizedBox(height: 6),
          _Field(controller: _titleCtrl, hint: 'e.g. Pilot Meetup at JFK'),
          const SizedBox(height: 14),

          const _Label('Description'),
          const SizedBox(height: 6),
          _Field(controller: _descCtrl, hint: 'Describe the event...', maxLines: 4),
          const SizedBox(height: 14),

          const _Label('Location *'),
          const SizedBox(height: 6),
          _Field(controller: _locationCtrl, hint: 'e.g. Terminal 4, JFK Airport'),
          const SizedBox(height: 14),

          const _Label('Requirements'),
          const SizedBox(height: 6),
          _Field(controller: _requirementsCtrl, hint: 'e.g. Valid crew ID, Airline uniform (comma separated)'),
          const SizedBox(height: 16),

          // Date + Time row
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(dateFmt.format(_date),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                ]),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(children: [
                  const Icon(Icons.access_time_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(_time.format(context),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
            )),
          ]),

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
                : const Text('Create Event', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  const _Field({required this.controller, required this.hint, this.maxLines = 1});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
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
