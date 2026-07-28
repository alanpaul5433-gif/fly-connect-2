import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import 'admin_thumbnail.dart';
import 'admin_audit_helper.dart';

class AdminEventsPage extends StatefulWidget {
  const AdminEventsPage({super.key});

  @override
  State<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends State<AdminEventsPage> {
  List<Map<String, dynamic>> _events = [];
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      final events = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      await _attachCreatorNames(events);
      if (!mounted) return;
      setState(() => _events = events);
    } catch (e) {
      debugPrint('[AdminEvents] fetch failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fills in `creatorName` from the `createdBy` UID each event actually
  /// stores.
  ///
  /// The card rendered `event['creatorName'] ?? 'Unknown'`, but no such field
  /// has ever been written — events store `createdBy`, a UID. So every event
  /// in the queue read "by Unknown", and an admin approving one had no idea
  /// which business submitted it. Unlike the other field-name bugs this is not
  /// a rename: the name is not in the document and has to be looked up.
  ///
  /// Distinct UIDs only — a business submitting ten events costs one read, not
  /// ten. Failures leave `creatorName` unset so the existing 'Unknown'
  /// fallback still renders; a name lookup must not take the queue down.
  Future<void> _attachCreatorNames(List<Map<String, dynamic>> events) async {
    final uids = events
        .map((e) => e['createdBy'])
        .whereType<String>()
        .where((uid) => uid.isNotEmpty)
        .toSet();
    if (uids.isEmpty) return;

    final names = <String, String>{};
    await Future.wait(uids.map((uid) async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final name = doc.data()?['name'];
        if (name is String && name.isNotEmpty) names[uid] = name;
      } catch (_) {/* fall through to 'Unknown' for this one creator */}
    }));

    for (final event in events) {
      final name = names[event['createdBy']];
      if (name != null) event['creatorName'] = name;
    }
  }

  List<Map<String, dynamic>> get _filteredEvents {
    switch (_filter) {
      case 'pending':
        return _events.where((e) => e['isApproved'] != true).toList();
      case 'approved':
        return _events.where((e) => e['isApproved'] == true).toList();
      case 'featured':
        return _events.where((e) => e['isFeatured'] == true).toList();
      default:
        return _events;
    }
  }

  int get _pendingCount => _events.where((e) => e['isApproved'] != true).length;
  int get _approvedCount => _events.where((e) => e['isApproved'] == true).length;
  int get _featuredCount => _events.where((e) => e['isFeatured'] == true).length;

  Future<void> _approveEvent(String docId) async {
    await FirebaseFirestore.instance
        .collection('events')
        .doc(docId)
        .update({'isApproved': true});
    await logAdminAction(
      action: 'approve_event',
      targetType: 'event',
      targetId: docId,
      details: 'Approved event $docId',
    );
    _fetchEvents();
  }

  Future<void> _rejectEvent(String docId, String title) async {
    final confirmed = await _showConfirm(
      context,
      title: 'Reject Event',
      message: 'Delete "$title"? This cannot be undone.',
      confirmLabel: 'Reject & Delete',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;
    await FirebaseFirestore.instance.collection('events').doc(docId).delete();
    await logAdminAction(
      action: 'reject_event',
      targetType: 'event',
      targetId: docId,
      details: 'Rejected & deleted event "$title"',
    );
    _fetchEvents();
  }

  Future<void> _toggleFeature(String docId, bool currentlyFeatured) async {
    await FirebaseFirestore.instance
        .collection('events')
        .doc(docId)
        .update({'isFeatured': !currentlyFeatured});
    await logAdminAction(
      action: currentlyFeatured ? 'unfeature_event' : 'feature_event',
      targetType: 'event',
      targetId: docId,
      details: '${currentlyFeatured ? "Unfeatured" : "Featured"} event $docId',
    );
    _fetchEvents();
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
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
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

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final filtered = _filteredEvents;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _buildStatCard('Pending', _pendingCount, AppColors.warning),
              const SizedBox(width: 12),
              _buildStatCard('Approved', _approvedCount, AppColors.online),
              const SizedBox(width: 12),
              _buildStatCard('Featured', _featuredCount, AppColors.primary),
              const SizedBox(width: 12),
              _buildStatCard('Total Events', _events.length, Colors.blue),
            ],
          ),
          const SizedBox(height: 20),

          // Filter tabs
          Row(
            children: [
              _filterTab('All', 'all'),
              const SizedBox(width: 8),
              _filterTab('Pending', 'pending'),
              const SizedBox(width: 8),
              _filterTab('Approved', 'approved'),
              const SizedBox(width: 8),
              _filterTab('Featured', 'featured'),
              const Spacer(),
              IconButton(
                onPressed: _fetchEvents,
                icon: const Icon(Icons.refresh_rounded),
                color: AppColors.textSecondary,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Event cards
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No events in this category',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...filtered.map((event) => _buildEventCard(event)),
        ],
      ),
    );
  }

  Widget _filterTab(String label, String value) {
    final isActive = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.dark : const Color(0xFFF0F0F2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary,
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
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
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
                  Text(
                    '$count',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w700, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final isPending = event['isApproved'] != true;
    final isFeatured = event['isFeatured'] == true;
    final title = event['title'] ?? 'Untitled Event';
    final createdAt = event['createdAt'] != null
        ? (event['createdAt'] as Timestamp).toDate()
        : DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: isPending
                    ? AppColors.warning
                    : isFeatured
                        ? AppColors.primary
                        : AppColors.online,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            // Events carry an imageUrl that this page never rendered, so
            // approvals happened without seeing the artwork being approved.
            Padding(
              padding: const EdgeInsets.all(12),
              child: AdminThumbnail(
                imageUrl: event['imageUrl'] as String?,
                label: title,
              ),
            ),

            // Image placeholder
            Container(
              width: 100,
              height: 112,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.event_outlined,
                    size: 32, color: AppColors.textSecondary),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isFeatured)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Featured',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.dark)),
                          ),
                        if (isPending)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Pending',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.warning)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'by ${event['creatorName'] ?? 'Unknown'} · ${_timeAgo(createdAt)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    if (event['description'] != null)
                      Text(
                        event['description'],
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (event['location'] != null) ...[
                          const Icon(Icons.location_on,
                              size: 13, color: Colors.blue),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              event['location'],
                              style: const TextStyle(
                                  color: Colors.blue, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (event['rsvpCount'] != null)
                          Text(
                            '${event['rsvpCount']} RSVPs',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Action buttons (fixed width to avoid unbounded-width layout)
            SizedBox(
              width: 132,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isPending)
                      _actionBtn(
                        label: 'Approve',
                        color: AppColors.online,
                        onPressed: () => _approveEvent(event['id']),
                      ),
                    if (isPending) const SizedBox(height: 6),
                    _actionBtn(
                      label: isFeatured ? 'Unfeature' : 'Feature',
                      color: isFeatured
                          ? AppColors.textSecondary
                          : AppColors.primary,
                      textColor: isFeatured ? Colors.white : AppColors.dark,
                      onPressed: () =>
                          _toggleFeature(event['id'], isFeatured),
                    ),
                    const SizedBox(height: 6),
                    _actionBtn(
                      label: 'Reject',
                      color: AppColors.error,
                      onPressed: () => _rejectEvent(event['id'], title),
                      outlined: true,
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

  Widget _actionBtn({
    required String label,
    required Color color,
    Color? textColor,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    final btn = outlined
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: Text(label),
          )
        : ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: textColor ?? Colors.white,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: Text(label),
          );
    return SizedBox(width: 108, height: 32, child: btn);
  }
}
