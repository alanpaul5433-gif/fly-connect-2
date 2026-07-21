import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/providers/trip_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'passport_ownership.dart';

class TripsScreen extends StatefulWidget {
  /// Optional: if non-null and different from the current user's uid,
  /// the screen shows a read-only view of that user's passport.
  final String? userId;
  const TripsScreen({super.key, this.userId});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  // Distinguishes "trips still loading" from "loaded but empty",
  // so the empty state doesn't flash on cold start before the first
  // snapshot returns.
  bool _initialLoadComplete = false;

  static const List<Map<String, String>> _countries = [
    {'code': 'US', 'name': 'United States', 'flag': '🇺🇸'},
    {'code': 'GB', 'name': 'United Kingdom', 'flag': '🇬🇧'},
    {'code': 'JP', 'name': 'Japan', 'flag': '🇯🇵'},
    {'code': 'FR', 'name': 'France', 'flag': '🇫🇷'},
    {'code': 'DE', 'name': 'Germany', 'flag': '🇩🇪'},
    {'code': 'AU', 'name': 'Australia', 'flag': '🇦🇺'},
    {'code': 'CA', 'name': 'Canada', 'flag': '🇨🇦'},
    {'code': 'IT', 'name': 'Italy', 'flag': '🇮🇹'},
    {'code': 'ES', 'name': 'Spain', 'flag': '🇪🇸'},
    {'code': 'TH', 'name': 'Thailand', 'flag': '🇹🇭'},
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _initialLoadComplete = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewerUid = context.watch<AuthProvider>().currentUser?.uid;
    final isSelf = isOwnPassport(viewerUid: viewerUid, routeUserId: widget.userId);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        // H9: only "My Trips" when it IS mine. A foreign passport is read-only.
        title: Text(isSelf ? 'My Trips' : 'Trips',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          if (isSelf)
            IconButton(icon: const Icon(Icons.add, color: Colors.black),
              onPressed: () => _showAddTrip(context)),
        ],
      ),
      // Own passport: the live TripProvider stream + edit controls. Someone
      // else's: a read-only stream of THEIR trips (H9 — this used to ignore
      // widget.userId entirely and show the viewer's own trips, editable).
      body: isSelf
        ? Consumer<TripProvider>(
            builder: (context, provider, _) =>
              _tripsBody(provider.trips, readOnly: false, provider: provider))
        : StreamBuilder<List<TripModel>>(
            stream: context.read<TripProvider>().watchUserTrips(widget.userId!),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _TripsSkeleton();
              }
              return _tripsBody(snap.data ?? const [], readOnly: true, provider: null);
            }),
    );
  }

  Widget _tripsBody(List<TripModel> trips,
      {required bool readOnly, required TripProvider? provider}) {
    if (trips.isNotEmpty && !_initialLoadComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _initialLoadComplete = true);
      });
    }
    if (trips.isEmpty) {
      if (!readOnly && !_initialLoadComplete) return const _TripsSkeleton();
      return readOnly ? _emptyForeignState() : _emptyState(context);
    }
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: _passportSection(trips)),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          (context, i) => _tripCard(context, trips[i], provider, readOnly: readOnly),
          childCount: trips.length,
        )),
      ),
    ]);
  }

  Widget _passportSection(List<TripModel> trips) {
    final stamps = trips.map((t) => t.countryCode).toSet();
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.dark, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.book, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('Digital Passport', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
            child: Text('${stamps.length} countries', style: const TextStyle(color: AppColors.dark, fontWeight: FontWeight.bold, fontSize: 12))),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: trips.map((t) {
          final country = _countries.firstWhere((c) => c['code'] == t.countryCode,
            orElse: () => {'code': t.countryCode, 'name': t.destination, 'flag': '✈️'});
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5))),
            child: Column(children: [
              Text(country['flag'] ?? '✈️', style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 2),
              Text(country['code'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 10)),
            ]));
        }).toList()),
      ]),
    );
  }

  Widget _tripCard(BuildContext context, TripModel trip, TripProvider? provider,
      {required bool readOnly}) {
    final country = _countries.firstWhere((c) => c['code'] == trip.countryCode,
      orElse: () => {'code': trip.countryCode, 'name': trip.destination, 'flag': '✈️'});
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(width: 50, height: 50, decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(country['flag'] ?? '✈️', style: const TextStyle(fontSize: 26)))),
        title: Text(trip.destination, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(country['name'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(DateFormat('MMM d, yyyy').format(trip.startDate), style: const TextStyle(fontSize: 12)),
        ]),
        // H9: Delete only on your OWN passport. Previously every card carried a
        // live Delete even when viewing someone else — and it deleted YOUR trip.
        trailing: (readOnly || provider == null) ? null : IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final confirmed = await showConfirmDialog(
              context,
              title: 'Delete trip?',
              message: 'Delete your trip to ${trip.destination}? This cannot be undone.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (!confirmed) return;
            try {
              await provider.deleteTrip(trip.id);
            } catch (_) {
              messenger.showSnackBar(const SnackBar(
                content: Text('Could not delete trip. Please try again.'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ));
            }
          }),
      ),
    );
  }

  // Read-only variant: no "Add Trip" CTA, and the copy is about them, not you.
  Widget _emptyForeignState() => const EmptyState(
        icon: Icons.flight_takeoff_outlined,
        title: 'No trips yet',
        subtitle: 'This traveller hasn\'t added any passport stamps yet.',
      );

  Widget _emptyState(BuildContext context) => EmptyState(
        icon: Icons.flight_takeoff_outlined,
        title: 'No trips yet',
        subtitle: 'Log your layovers and travel — your passport stamps will appear here.',
        actionLabel: 'Add Trip',
        onAction: () => _showAddTrip(context),
      );

  void _showAddTrip(BuildContext context) {
    String? selectedCountry;
    final destCtrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add Trip', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            AppTextField(hint: 'Destination', controller: destCtrl),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedCountry,
              hint: const Text('Select Country'),
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              items: _countries.map((c) => DropdownMenuItem(value: c['code'], child: Text('${c['flag']} ${c['name']}'))).toList(),
              onChanged: (v) => setState(() => selectedCountry = v),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save Trip', onTap: () async {
              if (destCtrl.text.isEmpty || selectedCountry == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Please enter a destination and pick a country.'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              final auth = context.read<AuthProvider>();
              final uid = auth.currentUser?.uid;
              if (uid == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Please sign in to save trips.'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              final messenger = ScaffoldMessenger.of(ctx);
              try {
                await context.read<TripProvider>().addTrip(TripModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  userId: uid,
                  destination: destCtrl.text.trim(),
                  countryCode: selectedCountry!,
                  startDate: DateTime.now(),
                  createdAt: DateTime.now(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {
                messenger.showSnackBar(const SnackBar(
                  content: Text('Could not add trip. Please try again.'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            }),
          ]),
        )));
  }
}

class _TripsSkeleton extends StatelessWidget {
  const _TripsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(children: [
          Skeleton(width: 50, height: 50, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 140, height: 14),
                SizedBox(height: 8),
                Skeleton(width: 100, height: 10),
                SizedBox(height: 6),
                Skeleton(width: 80, height: 10),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
