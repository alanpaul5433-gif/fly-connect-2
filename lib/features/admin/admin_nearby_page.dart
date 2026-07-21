import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/constants/app_colors.dart';

/// Admin moderation map. Plots recent SafeCheck check-ins that carry
/// coordinates on a Google Map, colored by status.
///
/// NOTE: coordinates are currently SIMULATED — the mobile app writes a fixed
/// NYC point for check-ins until real GPS ships — so the banner says so rather
/// than implying these are live positions. Mirrors [AdminSafeCheckPage]'s
/// Firestore stream, but renders a map instead of a list.
class AdminNearbyPage extends StatefulWidget {
  const AdminNearbyPage({super.key});

  @override
  State<AdminNearbyPage> createState() => _AdminNearbyPageState();
}

class _AdminNearbyPageState extends State<AdminNearbyPage> {
  StreamSubscription<QuerySnapshot>? _sub;
  final Set<Marker> _markers = {};
  bool _loading = true;
  GoogleMapController? _map;

  static const _fallbackCenter = LatLng(40.7128, -74.0060); // NYC

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('safeChecks')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen(_onData, onError: (e) {
      debugPrint('[AdminNearby] stream error: $e');
      if (mounted) setState(() => _loading = false);
    });
  }

  void _onData(QuerySnapshot snap) {
    if (!mounted) return;
    final markers = <Marker>{};
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue; // only plot geolocated check-ins
      final status = (d['status'] ?? 'safe') as String;
      markers.add(Marker(
        markerId: MarkerId(doc.id),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(_hue(status)),
        infoWindow: InfoWindow(
          title: (d['userName'] ?? 'Unknown') as String,
          snippet: '${_statusLabel(status)} · ${(d['city'] ?? '') as String}',
        ),
      ));
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(markers);
      _loading = false;
    });
    if (_map != null && markers.isNotEmpty) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(markers.first.position, 10));
    }
  }

  double _hue(String status) {
    switch (status) {
      case 'safe':
        return BitmapDescriptor.hueGreen;
      case 'unsure':
        return BitmapDescriptor.hueOrange;
      case 'need_help':
        return BitmapDescriptor.hueRed;
      case 'escalated':
        return BitmapDescriptor.hueViolet;
      default:
        return BitmapDescriptor.hueAzure;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'need_help':
        return 'Needs help';
      case 'unsure':
        return 'Unsure';
      case 'escalated':
        return 'Escalated';
      default:
        return 'Safe';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          color: AppColors.warning.withValues(alpha: 0.15),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Showing ${_markers.length} SafeCheck check-in(s) with coordinates. '
                'Locations are simulated until real GPS ships.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : GoogleMap(
                  initialCameraPosition: const CameraPosition(target: _fallbackCenter, zoom: 10),
                  markers: _markers,
                  onMapCreated: (c) {
                    _map = c;
                    if (_markers.isNotEmpty) {
                      c.animateCamera(CameraUpdate.newLatLngZoom(_markers.first.position, 10));
                    }
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                ),
        ),
      ],
    );
  }
}
