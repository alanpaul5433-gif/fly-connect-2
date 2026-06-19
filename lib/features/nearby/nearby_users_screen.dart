import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/real_providers.dart';
import '../../shared/utils/open_chat.dart';

// ─── Status helpers ──────────────────────────────────────────
Color _statusColor(String? status) => switch (status) {
  'safe'      => AppColors.online,
  'unsure'    => AppColors.warning,
  'need_help' => AppColors.error,
  _           => AppColors.primary,
};

IconData _statusIcon(String? status) => switch (status) {
  'safe'      => Icons.check_circle,
  'unsure'    => Icons.help,
  'need_help' => Icons.warning,
  _           => Icons.circle,
};

String _statusLabel(String? status) => switch (status) {
  'safe'      => 'Safe',
  'unsure'    => 'Unsure',
  'need_help' => 'Need Help',
  _           => '',
};

/// Google Maps marker hue per SafeCheck status (markers are bitmaps, so we
/// can't reuse the [Color]s — we map to the SDK's predefined hues instead).
double _statusHue(String? status) => switch (status) {
  'safe'      => BitmapDescriptor.hueGreen,
  'unsure'    => BitmapDescriptor.hueOrange,
  'need_help' => BitmapDescriptor.hueRed,
  _           => BitmapDescriptor.hueYellow,
};

// ─── Nearby user model ───────────────────────────────────────
class _NearbyUser {
  final String uid, name, airline, position, distance;
  final double lat, lng;
  const _NearbyUser({required this.uid, required this.name, required this.airline,
    required this.position, required this.lat, required this.lng, required this.distance});
}

// Simulated coordinates around NYC for nearby users
const _nearbyCoords = [
  (40.7128, -74.0060, '0.3 km'),
  (40.7158, -74.0020, '0.8 km'),
  (40.7100, -74.0100, '1.2 km'),
  (40.7180, -73.9980, '1.5 km'),
  (40.7090, -74.0150, '2.0 km'),
  (40.7140, -74.0080, '0.5 km'),
  (40.7110, -74.0040, '1.0 km'),
];

// ─── Screen ──────────────────────────────────────────────────
class NearbyUsersScreen extends StatefulWidget {
  const NearbyUsersScreen({super.key});
  @override State<NearbyUsersScreen> createState() => _NearbyUsersScreenState();
}

class _NearbyUsersScreenState extends State<NearbyUsersScreen> {
  _NearbyUser? _selected;
  bool _listView = false;
  GoogleMapController? _mapController;
  List<_NearbyUser> _nearbyUsers = [];
  bool _loadingUsers = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNearbyUsers();
  }

  Future<void> _loadNearbyUsers() async {
    if (mounted) {
      setState(() { _loadingUsers = true; _loadError = null; });
    }
    final auth = context.read<AuthProvider>();
    final myUid = auth.currentUser?.uid;

    // Safety: do NOT show users I have blocked, AND do NOT show users
    // who have blocked me. Either direction means we shouldn't surface
    // each other on the map (stalking / harassment mitigation).
    final blockedByMe = <String>{};
    final blockedMe = <String>{};
    if (myUid != null) {
      try {
        final mineSnap = await FirebaseFirestore.instance
            .collection('users').doc(myUid)
            .collection('blocked').get();
        blockedByMe.addAll(mineSnap.docs.map((d) => d.id));
      } catch (_) {/* fail open */}
      try {
        final theirsSnap = await FirebaseFirestore.instance
            .collectionGroup('blocked')
            .where(FieldPath.documentId, isEqualTo: myUid)
            .get();
        blockedMe.addAll(theirsSnap.docs.map((d) =>
            d.reference.parent.parent?.id ?? '').where((s) => s.isNotEmpty));
      } catch (_) {/* fail open */}
    }

    try {
      final snap = await FirebaseFirestore.instance.collection('users')
          .where('role', isEqualTo: 'user')
          .limit(20) // fetch extra so blocks don't shrink the list to nothing
          .get();
      final users = <_NearbyUser>[];
      int coordIdx = 0;
      for (final doc in snap.docs) {
        if (doc.id == myUid) continue;
        if (blockedByMe.contains(doc.id)) continue;
        if (blockedMe.contains(doc.id)) continue;
        if (users.length >= 10) break;
        final d = doc.data();
        final coord = _nearbyCoords[coordIdx % _nearbyCoords.length];
        users.add(_NearbyUser(
          uid: doc.id,
          name: d['name'] ?? 'User',
          airline: d['airline'] ?? '',
          position: d['position'] ?? '',
          lat: coord.$1, lng: coord.$2, distance: coord.$3,
        ));
        coordIdx++;
      }
      if (mounted) setState(() { _nearbyUsers = users; _loadingUsers = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Could not load nearby users.';
          _loadingUsers = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeCheck = context.watch<SafeCheckProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => GoRouter.of(context).pop()),
        title: const Text('Nearby Users', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black),
            tooltip: 'SafeCheck History',
            onPressed: () => context.push(AppRoutes.safeCheckHistory)),
          IconButton(
            icon: Icon(_listView ? Icons.map_outlined : Icons.list, color: Colors.black),
            tooltip: _listView ? 'Show map view' : 'Show list view',
            onPressed: () => setState(() => _listView = !_listView)),
          const TopBarActions(),
        ],
      ),
      floatingActionButton: _buildFab(safeCheck),
      body: Column(children: [
        // Honest notice: coordinates are approximate until real geolocation ships
        Container(
          width: double.infinity,
          color: AppColors.warning.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Locations are approximate. Real GPS is coming in a future update.',
                style: TextStyle(fontSize: 11, color: AppColors.warning.withValues(alpha: 0.9)),
              ),
            ),
          ]),
        ),
        if (_loadError != null && _nearbyUsers.isEmpty)
          InlineErrorBanner(
            message: _loadError!,
            onRetry: _loadNearbyUsers,
          ),
        Expanded(
          child: _loadingUsers
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _loadError != null && _nearbyUsers.isEmpty
              ? const SizedBox.shrink()
              : _nearbyUsers.isEmpty
                ? const Center(child: Text('No nearby users found', style: TextStyle(color: Colors.grey)))
                : _listView ? _buildList(safeCheck) : _buildMap(safeCheck),
        ),
      ]),
    );
  }

  // ─── FAB ──────────────────────────────────────────────────
  /// Emergency-number chip in the SafeCheck disclaimer.
  /// Opens the phone dialer (`tel:` scheme) but does not auto-dial — user
  /// must still press the call button on their device.
  Widget _emergencyChip(String label, String tel) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(tel);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.call, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _buildFab(SafeCheckProvider safeCheck) {
    final hasActive = safeCheck.myLatestCheckIn != null;
    final activeStatus = safeCheck.myLatestCheckIn?.status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FloatingActionButton.extended(
        backgroundColor: AppColors.dark,
        icon: Icon(
          hasActive ? Icons.verified_user : Icons.health_and_safety,
          color: hasActive ? _statusColor(activeStatus) : AppColors.primary),
        label: Text(
          hasActive ? 'Update Status' : 'SafeCheck',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => _showSafeCheckSheet(context),
      ),
    );
  }

  // ─── Map view (Google Maps) ───────────────────────────────
  Widget _buildMap(SafeCheckProvider safeCheck) {
    // Google Maps markers are bitmaps, not widgets — so the old avatar pins
    // become status-coloured default markers. Tapping one still opens the
    // user card overlay, same as before.
    final markers = _nearbyUsers.map((u) {
      final check = safeCheck.latestForUser(u.uid);
      return Marker(
        markerId: MarkerId(u.uid),
        position: LatLng(u.lat, u.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(_statusHue(check?.status)),
        onTap: () => setState(() => _selected = u),
      );
    }).toSet();

    return Stack(children: [
      GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(40.7128, -74.0060),
          zoom: 14,
        ),
        markers: markers,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        onMapCreated: (controller) => _mapController = controller,
        onTap: (_) => setState(() => _selected = null),
      ),
      // My location button
      Positioned(right: 16, bottom: _selected != null ? 260 : 100,
        child: FloatingActionButton.small(
          heroTag: 'my_location',
          backgroundColor: Colors.white,
          onPressed: () => _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(const LatLng(40.7128, -74.0060), 14)),
          child: const Icon(Icons.my_location, color: AppColors.dark))),
      // Selected user card
      if (_selected != null) Positioned(
        bottom: 0, left: 0, right: 0,
        child: _UserCard(
          user: _selected!,
          checkIn: safeCheck.latestForUser(_selected!.uid),
          onDismiss: () => setState(() => _selected = null))),
    ]);
  }

  // ─── List view ────────────────────────────────────────────
  Widget _buildList(SafeCheckProvider safeCheck) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.location_on, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text('${_nearbyUsers.length} people nearby', style: AppTextStyles.bodyMedium),
        ])),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _nearbyUsers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final u = _nearbyUsers[i];
          final check = safeCheck.latestForUser(u.uid);
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100)),
            child: Row(children: [
              CircleAvatar(radius: 26, backgroundColor: AppColors.dark,
                child: Text(u.name.isNotEmpty ? u.name[0] : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.name, style: AppTextStyles.labelMedium),
                Text('${u.airline} · ${u.position}', style: AppTextStyles.caption),
                if (check != null) ...[
                  const SizedBox(height: 6),
                  _StatusBadge(status: check.status),
                ],
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [
                  const Icon(Icons.location_on, size: 12, color: AppColors.primary),
                  Text(u.distance, style: AppTextStyles.caption),
                ]),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => context.push('/users/${u.uid}'),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(100)),
                    child: const Text('Connect', style: TextStyle(color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 12)))),
              ]),
            ]),
          );
        },
      )),
    ]);
  }

  // ─── SafeCheck bottom sheet ───────────────────────────────
  void _showSafeCheckSheet(BuildContext context) {
    String? selectedStatus;
    final msgCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Drag handle
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            // Title
            const Row(children: [
              Icon(Icons.health_and_safety, color: AppColors.primary, size: 28),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SafeCheck', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Share your safety status with nearby users',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              ])),
            ]),
            const SizedBox(height: 14),
            // ── Emergency disclaimer ──────────────────────────
            // Legal: SafeCheck is NOT an emergency service. Prevents
            // users from believing this app will dispatch help.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'Not an emergency service',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'SafeCheck shares status with nearby crew. In a real emergency call your local number.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    _emergencyChip('US 911', 'tel:911'),
                    _emergencyChip('EU 112', 'tel:112'),
                    _emergencyChip('UK 999', 'tel:999'),
                  ]),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            // Status options
            ...[
              ('safe', 'Safe', "I'm safe and settled", Icons.check_circle, AppColors.online),
              ('unsure', 'Unsure', 'My situation is unclear', Icons.help_outline, AppColors.warning),
              ('need_help', 'Need Help', 'I need assistance', Icons.warning_amber, AppColors.error),
            ].map((opt) {
              final (value, label, desc, icon, color) = opt;
              final isSelected = selectedStatus == value;
              return GestureDetector(
                onTap: () => setSheetState(() => selectedStatus = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelected ? color : Colors.grey.shade200, width: isSelected ? 2 : 1)),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 24)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15,
                        color: isSelected ? color : AppColors.textPrimary)),
                      Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ])),
                    Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? color : Colors.grey.shade400),
                  ])),
              );
            }),
            const SizedBox(height: 6),
            // Message field
            TextField(
              controller: msgCtrl,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: 'Add a short message (optional)',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.dark)),
              ),
            ),
            const SizedBox(height: 16),
            // Submit
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedStatus != null ? AppColors.primary : Colors.grey.shade300,
                foregroundColor: AppColors.dark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: selectedStatus == null ? null : () async {
                final auth = context.read<AuthProvider>();
                final safeCheckProvider = context.read<SafeCheckProvider>();
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final user = auth.currentUser;
                if (user == null) return;
                final status = selectedStatus!;
                final message = msgCtrl.text.trim().isEmpty ? null : msgCtrl.text.trim();
                try {
                  await safeCheckProvider.checkIn(
                    status: status,
                    message: message,
                    city: user.city ?? 'New York',
                    lat: 40.7128,
                    lng: -74.0060,
                    userId: user.uid,
                    userName: user.name,
                    userPhotoUrl: user.photoUrl,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  scaffoldMessenger.showSnackBar(SnackBar(
                      content: Row(children: [
                        Icon(_statusIcon(status), color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        const Text('SafeCheck shared!'),
                      ]),
                      backgroundColor: _statusColor(status),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                } catch (_) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  scaffoldMessenger.showSnackBar(const SnackBar(
                    content: Text('Could not submit SafeCheck. Please try again.'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ));
                }

              },
              child: Text(selectedStatus != null ? 'Share Status' : 'Select a status',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)))),
          ]),
        );
      }),
    );
  }
}

// ─── Status badge (compact) ──────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_statusIcon(status), size: 12, color: color),
        const SizedBox(width: 4),
        Text(_statusLabel(status),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ─── User card (map overlay) ─────────────────────────────────
class _UserCard extends StatelessWidget {
  final _NearbyUser user;
  final SafeCheckModel? checkIn;
  final VoidCallback onDismiss;
  const _UserCard({required this.user, this.checkIn, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          CircleAvatar(radius: 30, backgroundColor: AppColors.dark,
            child: Text(user.name.isNotEmpty ? user.name[0] : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 22))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.name, style: AppTextStyles.h4),
            Text('${user.airline} · ${user.position}', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            Row(children: [
              const Icon(Icons.location_on, size: 13, color: AppColors.primary),
              Text(user.distance, style: AppTextStyles.caption),
            ]),
          ])),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ]),
        // SafeCheck status section
        if (checkIn != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor(checkIn!.status).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _statusColor(checkIn!.status).withValues(alpha: 0.2))),
            child: Row(children: [
              Icon(_statusIcon(checkIn!.status), color: _statusColor(checkIn!.status), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_statusLabel(checkIn!.status),
                  style: TextStyle(fontWeight: FontWeight.w600, color: _statusColor(checkIn!.status), fontSize: 13)),
                if (checkIn!.message != null)
                  Text(checkIn!.message!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
              Text(_timeAgo(checkIn!.createdAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Message'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              if (auth.currentUser == null) return;
              await OpenChat.withUser(
                context,
                otherUid: user.uid,
                otherName: user.name,
              );
            })),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: const Text('Connect'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.dark,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              context.push('/users/${user.uid}');
            })),
        ]),
      ]),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
