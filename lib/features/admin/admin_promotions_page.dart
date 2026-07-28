import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import 'admin_thumbnail.dart';
import 'admin_audit_helper.dart';
import 'cursor_paginator.dart';

class AdminPromotionsPage extends StatefulWidget {
  const AdminPromotionsPage({super.key});

  @override
  State<AdminPromotionsPage> createState() => _AdminPromotionsPageState();
}

class _AdminPromotionsPageState extends State<AdminPromotionsPage> {
  List<Map<String, dynamic>> _promos = [];
  String _filter = 'all';
  bool _loading = true;
  bool _loadingMore = false;

  final _paginator = CursorPaginator(pageSize: 50);

  Query<Map<String, dynamic>> get _baseQuery => FirebaseFirestore.instance
      .collection('promotions')
      .orderBy('createdAt', descending: true);

  @override
  void initState() {
    super.initState();
    _fetchPromos();
  }

  Future<void> _fetchPromos() async {
    setState(() { _loading = true; });
    _paginator.reset();
    try {
      final snapshot = await _paginator.fetchFirst(_baseQuery);
      if (!mounted) return;
      setState(() {
        _promos = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      debugPrint('[AdminPromotions] fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_loadingMore || !_paginator.hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await _paginator.fetchNext(_baseQuery);
      if (!mounted || snap == null) return;
      setState(() {
        _promos.addAll(snap.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }));
      });
    } catch (e) {
      debugPrint('[AdminPromotions] fetchMore failed: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool _isExpired(Map<String, dynamic> p) {
    final validTo = p['validTo'];
    if (validTo is Timestamp) {
      return validTo.toDate().isBefore(DateTime.now());
    }
    return false;
  }

  List<Map<String, dynamic>> get _filteredPromos {
    switch (_filter) {
      case 'pending':
        return _promos.where((p) => p['isApproved'] != true).toList();
      case 'active':
        return _promos
            .where((p) =>
                p['isApproved'] == true &&
                p['isActive'] == true &&
                !_isExpired(p))
            .toList();
      case 'expired':
        return _promos.where(_isExpired).toList();
      default:
        return _promos;
    }
  }

  int get _pendingCount =>
      _promos.where((p) => p['isApproved'] != true).length;
  int get _activeCount => _promos
      .where((p) =>
          p['isApproved'] == true && p['isActive'] == true && !_isExpired(p))
      .length;
  int get _expiredCount => _promos.where(_isExpired).length;

  Future<void> _approve(String id) async {
    await FirebaseFirestore.instance
        .collection('promotions')
        .doc(id)
        .update({'isApproved': true, 'isActive': true});
    await logAdminAction(
      action: 'approve_promotion',
      targetType: 'promotion',
      targetId: id,
      details: 'Approved & published promotion $id',
    );
    _fetchPromos();
  }

  Future<void> _reject(String id, String title) async {
    final confirmed = await _showConfirm(
      context,
      title: 'Reject Promotion',
      message: 'Reject "$title"? It will be deactivated.',
      confirmLabel: 'Reject',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;
    await FirebaseFirestore.instance
        .collection('promotions')
        .doc(id)
        .update({'isApproved': false, 'isActive': false});
    await logAdminAction(
      action: 'reject_promotion',
      targetType: 'promotion',
      targetId: id,
      details: 'Rejected promotion "$title"',
    );
    _fetchPromos();
  }

  Future<void> _toggleActive(String id, bool current) async {
    await FirebaseFirestore.instance
        .collection('promotions')
        .doc(id)
        .update({'isActive': !current});
    await logAdminAction(
      action: current ? 'deactivate_promotion' : 'activate_promotion',
      targetType: 'promotion',
      targetId: id,
      details: '${current ? "Deactivated" : "Activated"} promotion $id',
    );
    _fetchPromos();
  }

  Future<bool> _showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _fmtDate(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      return '${d.day}/${d.month}/${d.year}';
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    final filtered = _filteredPromos;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatCard(
                  'Pending Approval', _pendingCount, AppColors.warning),
              const SizedBox(width: 12),
              _buildStatCard('Active', _activeCount, AppColors.online),
              const SizedBox(width: 12),
              _buildStatCard('Expired', _expiredCount, AppColors.error),
              const SizedBox(width: 12),
              _buildStatCard('Total', _promos.length, Colors.blue),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _filterPill('All', 'all'),
              const SizedBox(width: 8),
              _filterPill('Pending', 'pending'),
              const SizedBox(width: 8),
              _filterPill('Active', 'active'),
              const SizedBox(width: 8),
              _filterPill('Expired', 'expired'),
              const Spacer(),
              IconButton(
                onPressed: _fetchPromos,
                icon: const Icon(Icons.refresh_rounded),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No promotions found',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...filtered.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPromoCard(p),
                )),
          if (_promos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${filtered.length} of ${_promos.length} loaded',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                if (_paginator.hasMore)
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: _loadingMore ? null : _fetchMore,
                      icon: _loadingMore
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.expand_more, size: 16),
                      label: Text(
                          _loadingMore ? 'Loading…' : 'Load more',
                          style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.dark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  )
                else
                  const Text('End of list',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterPill(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.dark : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('$count',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoCard(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final title = (p['title'] ?? 'Untitled') as String;
    final businessName = (p['businessName'] ?? 'Unknown business') as String;
    final discount = p['discountPercent'] ?? 0;
    final isApproved = p['isApproved'] == true;
    final isActive = p['isActive'] == true;
    final expired = _isExpired(p);
    final views = p['views'] ?? 0;
    final redemptions = promoRedemptions(p);

    final accent = !isApproved
        ? AppColors.warning
        : expired
            ? AppColors.error
            : isActive
                ? AppColors.online
                : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Padding(
              padding: const EdgeInsets.all(12),
              child: AdminThumbnail(
                imageUrl: p['imageUrl'] as String?,
                label: title,
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('$discount% OFF',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(businessName,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(
                        '${_fmtDate(p['validFrom'])} → ${_fmtDate(p['validTo'])}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('$views views · $redemptions redemptions',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isApproved)
                    SizedBox(
                      width: 100,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () => _approve(id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.online,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  if (!isApproved) const SizedBox(height: 6),
                  SizedBox(
                    width: 100,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => _reject(id, title),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 100,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: () => _toggleActive(id, isActive),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.dark,
                        padding: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      child: Text(isActive ? 'Deactivate' : 'Activate'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Redemption count for a promo document, tolerant of both field names.
///
/// `PromotionModel.toMap` writes **`currentRedemptions`** (models.dart:62), but
/// this page shipped reading `redemptions` — a name only the older seeded
/// documents carry. Every business-created deal therefore reported
/// "0 redemptions" in the moderation queue regardless of actual usage, and 0 is
/// a believable number for a new deal, so nothing looked broken.
///
/// Both generations of document exist in production and neither is going away,
/// so this reads the current name first and falls back to the legacy one. A
/// non-numeric value degrades to 0 rather than throwing: this renders inside a
/// list of up to 50 cards, and one malformed document must not take the whole
/// moderation queue down.
int promoRedemptions(Map<String, dynamic> promo) {
  final value = promo['currentRedemptions'] ?? promo['redemptions'];
  return value is num ? value.toInt() : 0;
}
