import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
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

  /// Non-null when the last fetch threw. Previously a failed load was
  /// swallowed into debugPrint and the page rendered "No reports found",
  /// so a permission error, a missing index and a genuinely empty queue
  /// were indistinguishable to the admin.
  String? _loadError;

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
      _loadError = null;
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
      if (mounted) setState(() => _loadError = _describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Turns a Firestore exception into something an admin can act on.
  /// The raw `[cloud_firestore/permission-denied] ...` string is accurate
  /// but tells a moderator nothing about what to do next.
  String _describeError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'You do not have permission to read reports. Confirm this '
              'account still has the admin role.';
        case 'failed-precondition':
          return 'This query needs a Firestore index that has not been '
              'created yet.';
        case 'unavailable':
          return 'Could not reach Firestore. Check your connection.';
        case 'not-found':
          return 'That record no longer exists — it may have been deleted.';
      }
      return e.message ?? e.code;
    }
    return e.toString();
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
      if (!mounted) return;
      setState(() => _loadingMore = false);
      // Don't blank the list that is already on screen — the loaded pages
      // are still valid. Just say the next page failed.
      _showMessage('Could not load more: ${_describeError(e)}',
          isError: true);
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: isError ? AppColors.error : null,
    ));
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
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(docId)
          .update({'status': status});
    } catch (e) {
      debugPrint('[AdminReports] status update failed: $e');
      _showMessage('Could not update the report: ${_describeError(e)}',
          isError: true);
      return;
    }
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

  /// Shows what the report points at, and offers the admin page that can act
  /// on it.
  ///
  /// This used to `push('/posts/:id')` and friends. Those are consumer routes;
  /// the admin target registers none of them, so the push hit GoRouter's
  /// `errorBuilder` — which lives outside the ShellRoute — and replaced the
  /// entire console with "Page not found".
  ///
  /// No admin page takes a document id, so this cannot deep-link. It shows the
  /// identifying fields instead and lets the admin copy the target's name
  /// straight into the users search (applyUsersFilter matches name and email,
  /// not id — which is why the name, not the id, is the primary copy action).
  void _viewTarget(Map<String, dynamic> r) {
    final targetType = reportTargetType(r);
    final targetId = (r['targetId'] ?? '') as String;
    final targetName = (r['targetName'] ?? '') as String;
    if (targetId.isEmpty && targetName.isEmpty) {
      _showMessage('No target reference on this report.');
      return;
    }
    final destination = adminRouteForTargetType(targetType);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Reported Target',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _targetRow('Type',
                targetType.isEmpty ? 'unknown' : targetType.toUpperCase()),
            if (targetName.isNotEmpty) _targetRow('Name', targetName),
            if (targetId.isNotEmpty) _targetRow('ID', targetId),
            const SizedBox(height: 12),
            Text(
              destination == null
                  ? 'There is no admin page for "$targetType" targets yet.'
                  : 'Search this name in the destination page to act on it.',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          if (targetName.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: targetName));
                Navigator.of(ctx).pop();
                _showMessage('Copied "$targetName" to the clipboard.');
              },
              child: const Text('Copy Name'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          if (destination != null)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                GoRouter.of(context).go(destination);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dark,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(destination == AppRoutes.adminUsers
                  ? 'Open Users'
                  : 'Open Content'),
            ),
        ],
      ),
    );
  }

  Widget _targetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
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
    // `update()` throws not-found on a missing document, and this call was
    // previously unawaited-by-any-handler: the throw escaped, the success
    // snackbar never ran and no audit entry was written, so a failed ban was
    // pixel-identical to no click at all. Verified live — of the four
    // low-severity reports that show this button, two name a reporter whose
    // user document no longer exists.
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(reporterId)
          .update({'isBanned': true});
    } catch (e) {
      debugPrint('[AdminReports] ban failed: $e');
      _showMessage(
        e is FirebaseException && e.code == 'not-found'
            ? 'Cannot ban ${r['reporterName'] ?? 'this reporter'} — their '
                'account no longer exists.'
            : 'Ban failed: ${_describeError(e)}',
        isError: true,
      );
      return;
    }
    await logAdminAction(
      action: 'ban_user',
      targetType: 'user',
      targetId: reporterId,
      details: 'Banned reporter of report ${r['id']} (low-severity report)',
    );
    _showMessage('Reporter banned.');
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
    if (_loadError != null) return _buildErrorState(_loadError!);
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

  /// Shown instead of the queue when the fetch failed. The point is that this
  /// is visibly NOT the empty state: an admin seeing "No reports found" during
  /// an outage would reasonably conclude the queue was clear.
  Widget _buildErrorState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 36),
            const SizedBox(height: 12),
            const Text('Could not load reports',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchFirstPage,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dark,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
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

/// The admin page that can act on a given report target, or null when none
/// exists.
///
/// Deliberately returns only routes `adminRouter` registers. The bug this
/// replaces was a push to `/posts/:id` — a consumer route absent from the
/// admin build — which dropped the whole console onto GoRouter's
/// "Page not found" screen.
///
/// `chat` and `trip` map to null on purpose: there is no admin surface for
/// either, and offering navigation that goes nowhere useful would just be the
/// same bug wearing a different costume.
String? adminRouteForTargetType(String targetType) {
  switch (targetType) {
    case 'user':
      return AppRoutes.adminUsers;
    case 'post':
    case 'comment':
      return AppRoutes.adminContent;
    default:
      return null;
  }
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
