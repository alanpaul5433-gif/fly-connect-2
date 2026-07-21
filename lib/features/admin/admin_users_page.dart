import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import 'admin_audit_helper.dart';
import 'admin_filter_logic.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<Map<String, dynamic>> _users = [];
  String _filter = 'all';
  String _search = '';
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

  /// PII (email, phone) lives in the owner-only `users/{uid}/private/data`
  /// subdoc, not the main doc the list query above reads — see H-2 in
  /// docs/QA_AUDIT_REPORT.md. Admins are allowed to read it
  /// (firestore.rules `private/{docId}` — `isOwner(userId) || isAdmin()`),
  /// so we fan out one extra read per row to merge it back in for the list/
  /// detail/search UI, which is a normal cost for an internal admin tool.
  Future<List<Map<String, dynamic>>> _withPrivateData(
      List<Map<String, dynamic>> docs) async {
    return Future.wait(docs.map((data) async {
      final uid = data['uid'] as String;
      try {
        final privateDoc = await FirebaseFirestore.instance
            .collection('users').doc(uid).collection('private').doc('data').get();
        if (privateDoc.exists) return {...data, ...privateDoc.data()!};
      } catch (_) {/* fail open — list still renders without email/phone */}
      return data;
    }));
  }

  Future<void> _fetchFirstPage() async {
    setState(() { _loading = true; _lastDoc = null; _hasMore = true; });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      final docs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
      final withPrivate = await _withPrivateData(docs);
      if (!mounted) return;
      setState(() {
        _users = withPrivate;
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (_lastDoc == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      final newDocs = snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;
        return data;
      }).toList();
      final withPrivate = await _withPrivateData(newDocs);
      if (!mounted) return;
      setState(() {
        _users.addAll(withPrivate);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
        _hasMore = snapshot.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Backwards-compat alias for the existing onPressed handlers.
  Future<void> _fetchUsers() => _fetchFirstPage();

  List<Map<String, dynamic>> get _filteredUsers =>
      applyUsersFilter(_users, search: _search, filter: _filter);

  UserCounts get _counts => UserCounts.from(_users);

  int get _totalCount => _counts.total;
  int get _verifiedCount => _counts.verified;
  int get _unverifiedCount => _counts.unverified;
  int get _bannedCount => _counts.banned;
  int get _businessCount => _counts.business;

  Future<void> _toggleBan(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    final name = user['name'] ?? 'this user';
    final currentlyBanned = user['isBanned'] == true;

    final confirmed = await _showConfirm(
      context,
      title: currentlyBanned ? 'Unban User' : 'Ban User',
      message: currentlyBanned
          ? 'Allow $name to access the app again?'
          : 'Ban $name from using the app? They will not be able to log in.',
      confirmLabel: currentlyBanned ? 'Unban' : 'Ban',
      confirmColor: currentlyBanned ? AppColors.online : AppColors.error,
    );
    if (!confirmed) return;

    final newBanState = !currentlyBanned;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'isBanned': newBanState});
    await logAdminAction(
      action: newBanState ? 'ban_user' : 'unban_user',
      targetType: 'user',
      targetId: user['uid'] ?? '',
      details: '${newBanState ? "Banned" : "Unbanned"} ${user['name'] ?? user['email'] ?? 'user'}',
    );
    await _fetchUsers();
  }

  Future<void> _toggleVerify(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    final isVerified = user['isVerified'] == true;
    final newVerifyState = !isVerified;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'isVerified': newVerifyState});
    await logAdminAction(
      action: newVerifyState ? 'verify_user' : 'unverify_user',
      targetType: 'user',
      targetId: user['uid'] ?? '',
      details: '${newVerifyState ? "Verified" : "Unverified"} ${user['name'] ?? user['email'] ?? 'user'}',
    );
    await _fetchUsers();
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
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
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

  void _showUserDetail(BuildContext context, Map<String, dynamic> user) {
    final name = user['name'] ?? 'Unknown';
    final email = user['email'] ?? '—';
    final role = user['role'] ?? 'user';
    final airline = user['airline'] ?? '—';
    final position = user['position'] ?? '—';
    final city = user['city'] ?? '—';
    final state = user['state'] ?? '—';
    final bio = user['bio'] ?? '—';
    final isVerified = user['isVerified'] == true;
    final isBanned = user['isBanned'] == true;
    final followerCount = user['followerCount'] ?? 0;
    final followingCount = user['followingCount'] ?? 0;
    final postCount = user['postCount'] ?? 0;
    final uid = user['uid'] ?? '';

    DateTime? createdAt;
    final raw = user['createdAt'];
    if (raw is Timestamp) createdAt = raw.toDate();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(email,
                                style: const TextStyle(
                                    color: Color(0xFF8A8D9A), fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _badge(role,
                                    role == 'business'
                                        ? AppColors.primary
                                        : role == 'admin'
                                            ? Colors.purple.shade300
                                            : Colors.blue.shade300,
                                    AppColors.dark),
                                const SizedBox(width: 6),
                                if (isVerified)
                                  _badge('Verified', AppColors.online,
                                      Colors.white),
                                if (isBanned) ...[
                                  const SizedBox(width: 6),
                                  _badge('Banned', AppColors.error, Colors.white),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Stats row
                      Row(
                        children: [
                          _statChip('Posts', postCount),
                          const SizedBox(width: 12),
                          _statChip('Followers', followerCount),
                          const SizedBox(width: 12),
                          _statChip('Following', followingCount),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Details grid
                      _detailRow('UID', uid),
                      _detailRow('Airline', airline),
                      _detailRow('Position', position),
                      _detailRow('City', city),
                      _detailRow('State', state),
                      _detailRow('Bio', bio),
                      if (createdAt != null)
                        _detailRow('Joined',
                            '${createdAt.day}/${createdAt.month}/${createdAt.year}'),

                      const SizedBox(height: 20),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _toggleVerify(user);
                              },
                              icon: Icon(
                                isVerified
                                    ? Icons.cancel_outlined
                                    : Icons.verified_outlined,
                                size: 16,
                              ),
                              label: Text(isVerified ? 'Unverify' : 'Verify'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isVerified
                                    ? AppColors.warning
                                    : AppColors.online,
                                side: BorderSide(
                                  color: isVerified
                                      ? AppColors.warning
                                      : AppColors.online,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _toggleBan(user);
                              },
                              icon: Icon(
                                isBanned
                                    ? Icons.lock_open_outlined
                                    : Icons.block_outlined,
                                size: 16,
                              ),
                              label: Text(isBanned ? 'Unban' : 'Ban'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isBanned ? AppColors.online : AppColors.error,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Close',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _statChip(String label, dynamic value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$value',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterBar(),
                    const SizedBox(height: 20),
                    _buildStatsRow(),
                    const SizedBox(height: 20),
                    _buildUserTable(filtered),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Showing ${filtered.length} of ${_users.length} loaded',
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
                              label: Text(
                                  _loadingMore ? 'Loading…' : 'Load more',
                                  style: const TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.dark,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          )
                        else if (_users.isNotEmpty)
                          const Text(
                            'End of list',
                            style: TextStyle(
                                color: Color(0xFF8A8D9A), fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFilterBar() {
    final filters = {
      'all': 'All',
      'verified': 'Verified',
      'unverified': 'Unverified',
      'banned': 'Banned',
      'business': 'Business',
      'admin': 'Admin',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              onChanged: (val) => setState(() => _search = val),
              decoration: InputDecoration(
                hintText: 'Search by name, email...',
                hintStyle: const TextStyle(
                  color: Color(0xFF8A8D9A),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8A8D9A)),
                filled: true,
                fillColor: const Color(0xFFF0F0F2),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.entries.map((entry) {
                  final isActive = _filter == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = entry.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF1A1D27)
                              : const Color(0xFFF0F0F2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : const Color(0xFF8A8D9A),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            onPressed: _fetchUsers,
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.textSecondary,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = [
      {'label': 'Total Users', 'count': _totalCount, 'color': const Color(0xFF1A1D27)},
      {'label': 'Verified', 'count': _verifiedCount, 'color': const Color(0xFF4CAF50)},
      {'label': 'Unverified', 'count': _unverifiedCount, 'color': const Color(0xFFFF9500)},
      {'label': 'Banned', 'count': _bannedCount, 'color': const Color(0xFFFF3B30)},
      {'label': 'Business', 'count': _businessCount, 'color': const Color(0xFFD4F53C)},
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s['count']}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: s['color'] as Color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s['label'] as String,
                  style: const TextStyle(color: Color(0xFF8A8D9A), fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUserTable(List<Map<String, dynamic>> users) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            color: const Color(0xFFF5F5F7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('User',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
                Expanded(
                    flex: 3,
                    child: Text('Email',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
                Expanded(
                    flex: 2,
                    child: Text('Role',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
                Expanded(
                    flex: 2,
                    child: Text('Airline',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
                Expanded(
                    flex: 2,
                    child: Text('Verified',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
                Expanded(
                    flex: 2,
                    child: Text('Status',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
                Expanded(
                    flex: 3,
                    child: Text('Actions',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF8A8D9A)))),
              ],
            ),
          ),

          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text('No users found',
                    style: TextStyle(color: Color(0xFF8A8D9A))),
              ),
            )
          else
            ...List.generate(users.length, (index) {
              final user = users[index];
              final name = user['name'] ?? 'Unknown';
              final email = user['email'] ?? '';
              final role = user['role'] ?? 'user';
              final airline = user['airline'] ?? '-';
              final isVerified = user['isVerified'] == true;
              final isBanned = user['isBanned'] == true;
              final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

              return Container(
                color: index % 2 == 1
                    ? const Color(0xFFF5F5F7).withValues(alpha: 0.35)
                    : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // User
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF1A1D27),
                            child: Text(initial,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    // Email
                    Expanded(
                      flex: 3,
                      child: Text(email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF8A8D9A))),
                    ),
                    // Role
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: role == 'business'
                                ? const Color(0xFFD4F53C)
                                : role == 'admin'
                                    ? Colors.purple.shade100
                                    : const Color(0xFFF0F0F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: role == 'business'
                                  ? const Color(0xFF1A1D27)
                                  : role == 'admin'
                                      ? Colors.purple.shade700
                                      : const Color(0xFF8A8D9A),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Airline
                    Expanded(
                      flex: 2,
                      child: Text(airline,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    // Verified
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isVerified
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
                                : const Color(0xFFFF9500).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isVerified ? 'Yes' : 'No',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isVerified
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF9500),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Status
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isBanned
                                ? const Color(0xFFFF3B30).withValues(alpha: 0.12)
                                : const Color(0xFF4CAF50).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isBanned ? 'Banned' : 'Active',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isBanned
                                  ? const Color(0xFFFF3B30)
                                  : const Color(0xFF4CAF50),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Actions
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          // View detail
                          _actionButton(
                            label: 'View',
                            color: const Color(0xFFF0F0F2),
                            textColor: AppColors.textPrimary,
                            onTap: () => _showUserDetail(context, user),
                          ),
                          const SizedBox(width: 5),
                          // Verify/Unverify
                          _actionButton(
                            label: isVerified ? 'Unverify' : 'Verify',
                            color: isVerified
                                ? AppColors.warning.withValues(alpha: 0.12)
                                : AppColors.online.withValues(alpha: 0.12),
                            textColor:
                                isVerified ? AppColors.warning : AppColors.online,
                            onTap: () => _toggleVerify(user),
                          ),
                          const SizedBox(width: 5),
                          // Ban/Unban
                          _actionButton(
                            label: isBanned ? 'Unban' : 'Ban',
                            color: isBanned
                                ? AppColors.online.withValues(alpha: 0.12)
                                : AppColors.error.withValues(alpha: 0.12),
                            textColor:
                                isBanned ? AppColors.online : AppColors.error,
                            onTap: () => _toggleBan(user),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
        ),
      ),
    );
  }
}
