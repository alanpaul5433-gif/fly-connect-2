import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import 'admin_audit_helper.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  List<Map<String, dynamic>> _reports = [];
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  bool _loading = true;

  // Cursor pagination — Firestore cannot offset, so we keep the last
  // doc snapshot from each page and use startAfterDocument on the next.
  static const int _pageSize = 50;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _fetchFirstPage();
  }

  /// Sort by severity (high > medium > low), then newest first.
  void _sortReports() => _reports.sort(compareReports);

  Future<void> _fetchFirstPage() async {
    setState(() {
      _loading = true;
      _lastDoc = null;
      _hasMore = true;
    });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      setState(() {
        _reports = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _sortReports();
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
      });
    } catch (e) {
      debugPrint('[AdminReports] fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_lastDoc == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      final newDocs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      setState(() {
        _reports.addAll(newDocs);
        _sortReports();
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
        _hasMore = snapshot.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('[AdminReports] fetchMore failed: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Backwards-compat alias for the existing onPressed handlers.
  Future<void> _fetchReports() => _fetchFirstPage();

  List<Map<String, dynamic>> get _filteredReports {
    return _reports.where((r) {
      final status = (r['status'] ?? 'pending') as String;
      final type = reportTargetType(r);
      if (_statusFilter != 'all' && status != _statusFilter) return false;
      if (_typeFilter != 'all' && type != _typeFilter) return false;
      return true;
    }).toList();
  }

  int get _pendingCount =>
      _reports.where((r) => (r['status'] ?? 'pending') == 'pending').length;
  int get _resolvedCount =>
      _reports.where((r) => r['status'] == 'resolved').length;
  int get _dismissedCount =>
      _reports.where((r) => r['status'] == 'dismissed').length;

  Color _severityColor(String severity) {
    switch (severity) {
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _updateStatus(String docId, String status) async {
    await FirebaseFirestore.instance
        .collection('reports')
        .doc(docId)
        .update({'status': status});
    await logAdminAction(
      action: '${status}_report',
      targetType: 'report',
      targetId: docId,
      details: 'Report $docId status set to $status',
    );
    _fetchReports();
  }

  Future<void> _dismissReport(String docId) async {
    final confirmed = await _showConfirm(
      context,
      title: 'Dismiss Report',
      message: 'Mark this report as dismissed?',
      confirmLabel: 'Dismiss',
      confirmColor: AppColors.textSecondary,
    );
    if (!confirmed) return;
    await _updateStatus(docId, 'dismissed');
  }

  /// Opens the reported entity so an admin can review it in context (M-7 —
  /// this button was previously a no-op even though targetType/targetId are
  /// already written onto every report by reportPost/reportContent).
  void _viewTarget(Map<String, dynamic> r) {
    final targetType = reportTargetType(r);
    final targetId = (r['targetId'] ?? '') as String;
    if (targetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No target reference on this report.')));
      return;
    }
    switch (targetType) {
      case 'post':
        GoRouter.of(context).push('/posts/$targetId');
        break;
      case 'user':
        GoRouter.of(context).push('/users/$targetId');
        break;
      case 'group':
        GoRouter.of(context).push('/groups/$targetId');
        break;
      case 'chat':
        GoRouter.of(context).push('/conversation/$targetId');
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open a "$targetType" target directly.')));
    }
  }

  /// Bans the user who filed a (typically abusive/retaliatory) low-severity
  /// report. Mirrors admin_users_page.dart's _toggleBan write shape — no
  /// shared provider method exists yet for banning, so this replicates the
  /// same direct Firestore update + audit-log call (M-7).
  Future<void> _banReporter(Map<String, dynamic> r) async {
    final reporterId = r['reporterId'] as String?;
    if (reporterId == null || reporterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No reporter on file for this report.')));
      return;
    }
    final confirmed = await _showConfirm(
      context,
      title: 'Ban Reporter',
      message: 'Ban the user who filed this report? They will not be able to log in.',
      confirmLabel: 'Ban',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;
    await FirebaseFirestore.instance.collection('users').doc(reporterId).update({'isBanned': true});
    await logAdminAction(
      action: 'ban_user',
      targetType: 'user',
      targetId: reporterId,
      details: 'Banned reporter of report ${r['id']} (low-severity report)',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporter banned.')));
    }
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    final filtered = _filteredReports;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatCard('Pending', _pendingCount, AppColors.warning),
              const SizedBox(width: 12),
              _buildStatCard('Resolved', _resolvedCount, AppColors.online),
              const SizedBox(width: 12),
              _buildStatCard(
                  'Dismissed', _dismissedCount, AppColors.textSecondary),
              const SizedBox(width: 12),
              _buildStatCard('Total', _reports.length, Colors.blue),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterPill('All', _statusFilter == 'all',
                  () => setState(() => _statusFilter = 'all')),
              _filterPill('Pending', _statusFilter == 'pending',
                  () => setState(() => _statusFilter = 'pending')),
              _filterPill('Resolved', _statusFilter == 'resolved',
                  () => setState(() => _statusFilter = 'resolved')),
              _filterPill('Dismissed', _statusFilter == 'dismissed',
                  () => setState(() => _statusFilter = 'dismissed')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterPill('All Types', _typeFilter == 'all',
                  () => setState(() => _typeFilter = 'all')),
              _filterPill('Post', _typeFilter == 'post',
                  () => setState(() => _typeFilter = 'post')),
              _filterPill('User', _typeFilter == 'user',
                  () => setState(() => _typeFilter = 'user')),
              _filterPill('Chat', _typeFilter == 'chat',
                  () => setState(() => _typeFilter = 'chat')),
              _filterPill('Trip', _typeFilter == 'trip',
                  () => setState(() => _typeFilter = 'trip')),
              _filterPill('Comment', _typeFilter == 'comment',
                  () => setState(() => _typeFilter = 'comment')),
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
                child: Text('No reports found',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...filtered.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildReportCard(r),
                )),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${filtered.length} of ${_reports.length} loaded',
                style: const TextStyle(
                  color: Color(0xFF8A8D9A),
                  fontSize: 13,
                ),
              ),
              if (_hasMore)
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _loadingMore ? null : _fetchMore,
                    icon: _loadingMore
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.expand_more, size: 16),
                    label: Text(_loadingMore ? 'Loading…' : 'Load more',
                        style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                )
              else if (_reports.isNotEmpty)
                const Text(
                  'End of list',
                  style: TextStyle(color: Color(0xFF8A8D9A), fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.dark : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
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

  Widget _buildReportCard(Map<String, dynamic> r) {
    final severity = (r['severity'] ?? 'low') as String;
    final accent = _severityColor(severity);
    final type = reportTargetType(r).isEmpty ? 'unknown' : reportTargetType(r);
    final reason = (r['reason'] ?? 'No reason') as String;
    final description = (r['description'] ?? '') as String;
    final reporterName = (r['reporterName'] ?? 'Anonymous') as String;
    final status = (r['status'] ?? 'pending') as String;
    final createdAt = r['createdAt'];
    String timeText = '';
    if (createdAt is Timestamp) {
      timeText = _timeAgo(createdAt.toDate());
    }
    final id = r['id'] as String;

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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundGrey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(type.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(severity.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accent)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundGrey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(status.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(reason,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(description,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Reported by $reporterName',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                        const Spacer(),
                        Text(timeText,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 32,
                          child: OutlinedButton(
                            onPressed: () => _viewTarget(r),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              textStyle: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            child: const Text('View Target'),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          height: 32,
                          child: ElevatedButton(
                            onPressed: () => _updateStatus(id, 'resolved'),
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
                            child: const Text('Resolve'),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          height: 32,
                          child: OutlinedButton(
                            onPressed: () => _dismissReport(id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(
                                  color: AppColors.textSecondary),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              textStyle: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Dismiss'),
                          ),
                        ),
                        if (severity == 'low')
                          SizedBox(
                            width: 110,
                            height: 32,
                            child: OutlinedButton(
                              onPressed: () => _banReporter(r),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: const BorderSide(color: AppColors.error),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                textStyle: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              child: const Text('Ban Reporter'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The kind of thing a report points at: `post`, `chat`, `user`, …
///
/// **Two schemas are live simultaneously**, and both are real data:
///   * the app writes `targetType` (real_providers.dart:1442, :1545)
///   * seeded production documents carry `type`
///
/// This page previously mixed them — "view target" switched on `targetType`
/// (dead for every seeded report) while the type filter and badge read `type`
/// (blank or "unknown" for every app-created report). Each report broke one
/// way or the other, which is what disguised it as cosmetic.
///
/// Reading both is therefore not defensive padding; dropping either name
/// breaks a population of documents that already exists.
String reportTargetType(Map<String, dynamic> report) {
  final value = report['type'] ?? report['targetType'];
  return value is String ? value : '';
}

/// Queue order: severity first, then newest.
///
/// The old tiebreaker read `reportCount`, which reports do not carry, so it
/// compared 0 against 0 and the ordering inside a severity band was whatever
/// Firestore happened to return. `createdAt` is present on every report and
/// matches what an admin wants — the newest unhandled report at the top.
///
/// Undated documents sort last rather than throwing; a single malformed
/// report must not break the whole queue's ordering.
int compareReports(Map<String, dynamic> a, Map<String, dynamic> b) {
  int severityRank(Map<String, dynamic> r) {
    switch (r['severity']) {
      case 'high':
        return 0;
      case 'medium':
        return 1;
      default:
        return 2;
    }
  }

  final rankDelta = severityRank(a).compareTo(severityRank(b));
  if (rankDelta != 0) return rankDelta;

  DateTime? createdAt(Map<String, dynamic> r) {
    final value = r['createdAt'];
    return value is Timestamp ? value.toDate() : null;
  }

  final da = createdAt(a);
  final db = createdAt(b);
  if (da == null && db == null) return 0;
  if (da == null) return 1;
  if (db == null) return -1;
  return db.compareTo(da);
}
