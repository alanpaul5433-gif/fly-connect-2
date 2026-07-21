import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';

class CreatePromotionScreen extends StatefulWidget {
  const CreatePromotionScreen({super.key});
  @override
  State<CreatePromotionScreen> createState() => _CreatePromotionScreenState();
}

class _CreatePromotionScreenState extends State<CreatePromotionScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _maxRedemCtrl = TextEditingController();
  double _discount = 20;
  DateTime _validFrom = DateTime.now();
  DateTime _validTo = DateTime.now().add(const Duration(days: 30));
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _maxRedemCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _validFrom : _validTo,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF1A1D27), onPrimary: Color(0xFFD4F53C))),
        child: child!),
    );
    if (picked != null) {
      setState(() { if (isFrom) {
        _validFrom = picked;
      } else {
        _validTo = picked;
      } });
    }
  }

  bool _posting = false;

  Future<void> _post() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a deal title')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null || (user.role != 'business' && user.role != 'admin')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Only business accounts can create deals.'),
        backgroundColor: Colors.red));
      return;
    }
    if (user.role == 'business' && !user.isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your business account is pending verification. '
            'You\'ll be able to create deals once an admin approves it.'),
        backgroundColor: Colors.red));
      return;
    }
    setState(() => _posting = true);
    try {
      // Upload image to Firebase Storage if one was picked
      String? imageUrl;
      if (_imageBytes != null) {
        final ref = FirebaseStorage.instance.ref(
            'business_images/${user.uid}/promos/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putData(_imageBytes!, SettableMetadata(contentType: 'image/jpeg'));
        imageUrl = await ref.getDownloadURL();
      }
      final maxRedem = int.tryParse(_maxRedemCtrl.text.trim()) ?? 100;
      final newPromo = PromotionModel(
        id: 'promo_${DateTime.now().millisecondsSinceEpoch}',
        businessId: user.uid,
        businessName: user.name,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : _titleCtrl.text.trim(),
        imageUrl: imageUrl,
        discountPercent: _discount.round(),
        validFrom: _validFrom,
        validTo: _validTo,
        maxRedemptions: maxRedem,
        currentRedemptions: 0,
        views: 0,
        saves: 0,
        isActive: false,
        isApproved: false,
      );
      if (!mounted) return;
      await context.read<PromotionProvider>().addPromotion(newPromo);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deal submitted! It will be visible to crew after admin approval.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to create deal: $e'),
        backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create Deal', style: AppTextStyles.labelLarge),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _posting ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4F53C),
                foregroundColor: const Color(0xFF1A1D27),
                elevation: 0,
                minimumSize: const Size(70, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
              ),
              child: const Text('Post', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image picker
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D27),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: _imageBytes != null
                  ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                  : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 36),
                      SizedBox(height: 10),
                      Text('Add deal image', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ]),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _titleCtrl,
            decoration: _inputDec('Deal Title'),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: _inputDec('Description'),
          ),
          const SizedBox(height: 14),

          // Discount slider
          Row(children: [
            const Text('Discount:', style: AppTextStyles.bodyMedium),
            const SizedBox(width: 8),
            Text('${_discount.round()}%', style: AppTextStyles.labelMedium.copyWith(color: const Color(0xFF1A1D27))),
            const Spacer(),
            SizedBox(
              width: 180,
              child: Slider(
                value: _discount,
                min: 5, max: 70, divisions: 13,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.backgroundGrey,
                onChanged: (v) => setState(() => _discount = v),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Date pickers
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => _pickDate(true),
              child: _DateBox(label: 'Valid From', date: fmt.format(_validFrom)),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => _pickDate(false),
              child: _DateBox(label: 'Valid To', date: fmt.format(_validTo)),
            )),
          ]),
          const SizedBox(height: 14),

          TextField(
            controller: _maxRedemCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDec('Max Redemptions'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Maximum number of times this deal can be redeemed by users',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.grey),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A1D27))),
  );
}

class _DateBox extends StatelessWidget {
  final String label;
  final String date;
  const _DateBox({required this.label, required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(date, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ]),
    );
  }
}
