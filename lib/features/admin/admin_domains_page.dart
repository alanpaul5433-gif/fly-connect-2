import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/utils/email_domain.dart';
import 'admin_audit_helper.dart';

/// Admin management of the signup email-domain allowlist.
///
/// Only crew (`role == 'user'`) signups are gated by this list — businesses
/// go through admin verification instead, so a hotel or lounge does not need
/// an entry here.
///
/// Two behaviours are deliberate and easy to mistake for bugs:
///
///  • **Remove is a soft delete.** `firestore.rules` sets `allow delete: if
///    false` on this collection; removing an entry flips `enabled` to false so
///    `addedBy`/`addedAt` survive as the audit answer to "who let this domain
///    in?". Disabled entries stay visible here, greyed out, and can be
///    re-enabled.
///  • **Turning the gate on is a separate switch.** Adding domains changes
///    nothing until Enforcement is enabled, and disabling enforcement is the
///    fastest rollback if signups start failing.
class AdminDomainsPage extends StatefulWidget {
  const AdminDomainsPage({super.key});

  @override
  State<AdminDomainsPage> createState() => _AdminDomainsPageState();
}

class _AdminDomainsPageState extends State<AdminDomainsPage> {
  static const _gateDoc = 'signup_gate';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _domains = [];
  bool _enforced = false;
  bool _loading = true;
  String? _loadError;

  bool _adding = false;
  String? _addError;
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  int get _enabledCount =>
      _domains.where((d) => d.data()['enabled'] == true).length;

  Future<void> _fetch() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final db = FirebaseFirestore.instance;
      // Ordered by document id, which IS the domain — no composite index
      // needed, and no filter, so the enabled/disabled split is done in Dart.
      // See firestore-indexes-audit.md for why we avoid filter+orderBy pairs
      // that pass in the emulator and fail in production.
      final results = await Future.wait([
        db.collection('allowed_domains').orderBy(FieldPath.documentId).get(),
        db.collection('app_config').doc(_gateDoc).get(),
      ]);
      if (!mounted) return;
      setState(() {
        _domains = (results[0] as QuerySnapshot<Map<String, dynamic>>).docs;
        _enforced = (results[1] as DocumentSnapshot<Map<String, dynamic>>)
                .data()?['enforced'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  Future<void> _addDomain() async {
    final parsed = normalizeAdminDomainInput(_addCtrl.text);
    if (!parsed.isAccepted) {
      setState(() => _addError = parsed.error);
      return;
    }
    final domain = parsed.domain!;

    if (_domains.any((d) => d.id == domain)) {
      setState(() => _addError = '"$domain" is already on the list.');
      return;
    }

    // A public provider silently converts "approved airlines only" into
    // "anyone on earth", with no error and nothing in any log that reads as a
    // problem. Make it a deliberate act.
    if (parsed.needsPublicProviderConfirmation) {
      final ok = await _showConfirm(
        title: 'Allow anyone with a $domain address?',
        message: '$domain is a public email provider. Adding it lets ANYONE '
            'create a FlyConnect crew account, which effectively turns the '
            'allowlist off. Add it only if you mean to.',
        confirmLabel: 'Add anyway',
        confirmColor: AppColors.error,
      );
      if (!ok) return;
    }

    setState(() { _adding = true; _addError = null; });
    try {
      await FirebaseFirestore.instance
          .collection('allowed_domains')
          .doc(domain)
          .set({
        'domain': domain,
        'enabled': true,
        'addedBy': _currentUid(),
        // Rules require addedAt == request.time, so only a real server
        // timestamp is accepted — a client clock cannot forge provenance.
        'addedAt': FieldValue.serverTimestamp(),
      });
      await logAdminAction(
        action: 'add_allowed_domain',
        targetType: 'allowed_domain',
        targetId: domain,
        details: parsed.needsPublicProviderConfirmation
            ? 'Added PUBLIC PROVIDER $domain to the signup allowlist'
            : 'Added $domain to the signup allowlist',
      );
      _addCtrl.clear();
    } catch (e) {
      if (mounted) setState(() => _addError = 'Could not add "$domain": $e');
    }
    if (!mounted) return;
    setState(() => _adding = false);
    await _fetch();
  }

  Future<void> _setEnabled(String domain, bool enabled) async {
    if (!enabled) {
      final ok = await _showConfirm(
        title: 'Remove $domain?',
        message: 'New signups with a "$domain" email will be refused. '
            'Existing accounts are NOT affected and keep working.',
        confirmLabel: 'Remove',
        confirmColor: AppColors.error,
      );
      if (!ok) return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('allowed_domains')
          .doc(domain)
          .update({
        'enabled': enabled,
        'updatedBy': _currentUid(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await logAdminAction(
        action: enabled ? 'enable_allowed_domain' : 'disable_allowed_domain',
        targetType: 'allowed_domain',
        targetId: domain,
        details: enabled
            ? 'Re-enabled $domain for signup'
            : 'Removed $domain from the signup allowlist',
      );
    } catch (e) {
      if (mounted) _snack('Could not update "$domain": $e');
    }
    await _fetch();
  }

  Future<void> _setEnforced(bool value) async {
    // Rules cannot count documents, so "enforced with an empty list" — which
    // would refuse every crew signup on the platform — has to be prevented
    // here. There is no in-app recovery once signups are dead.
    if (value && _enabledCount == 0) {
      _snack('Add at least one domain before turning enforcement on — '
          'otherwise every crew signup will be refused.');
      return;
    }
    final ok = await _showConfirm(
      title: value ? 'Turn enforcement ON?' : 'Turn enforcement OFF?',
      message: value
          ? 'Crew signups will be limited to the $_enabledCount domain(s) '
              'below, effective immediately. Existing accounts are unaffected.'
          : 'Anyone will be able to create a crew account with any email '
              'address, effective immediately.',
      confirmLabel: value ? 'Turn on' : 'Turn off',
      confirmColor: value ? AppColors.dark : AppColors.error,
    );
    if (!ok) return;

    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc(_gateDoc)
          .set({
        'enforced': value,
        'updatedBy': _currentUid(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await logAdminAction(
        action: value ? 'enable_signup_gate' : 'disable_signup_gate',
        targetType: 'config',
        targetId: _gateDoc,
        details: value
            ? 'Enabled the signup domain gate ($_enabledCount domain(s) active)'
            : 'Disabled the signup domain gate — signup is open to any domain',
      );
    } catch (e) {
      if (mounted) _snack('Could not change enforcement: $e');
    }
    await _fetch();
  }

  /// `firestore.rules` requires `addedBy`/`updatedBy` to equal the caller's own
  /// uid, so a write with the wrong value here is rejected rather than
  /// mis-attributed.
  String _currentUid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<bool> _showConfirm({
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Failed to load allowed domains',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_loadError!,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry')),
                ]))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEnforcementCard(),
                        const SizedBox(height: 20),
                        _buildAddRow(),
                        const SizedBox(height: 20),
                        if (_domains.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'No allowed domains yet. Add a company domain '
                                '(e.g. delta.com) to let its crew sign up.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          ..._domains.map((d) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildDomainCard(d),
                              )),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildEnforcementCard() {
    final active = _enforced;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? AppColors.dark : Colors.orange.shade200, width: 1),
      ),
      child: Row(children: [
        Icon(active ? Icons.lock_outline : Icons.lock_open_outlined,
            size: 28, color: active ? AppColors.dark : Colors.orange),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(active ? 'Enforcement is ON' : 'Enforcement is OFF',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              active
                  ? 'Crew signups are limited to the $_enabledCount enabled '
                      'domain(s) below. Business signups are unaffected.'
                  : 'Anyone can sign up with any email address. Domains below '
                      'have no effect until this is turned on.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: 'Signup domain enforcement',
          toggled: active,
          child: Switch(
            value: active,
            activeThumbColor: AppColors.dark,
            onChanged: _setEnforced,
          ),
        ),
      ]),
    );
  }

  Widget _buildAddRow() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Semantics(
          textField: true,
          label: 'Domain to add, for example delta dot com',
          child: TextField(
            controller: _addCtrl,
            enabled: !_adding,
            onSubmitted: (_) => _adding ? null : _addDomain(),
            decoration: InputDecoration(
              hintText: 'e.g. delta.com',
              errorText: _addError,
              errorMaxLines: 3,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          // Disabled while in flight: a second arrayless write would dedupe
          // harmlessly, but logAdminAction would not, leaving a duplicate
          // audit entry.
          onPressed: _adding ? null : _addDomain,
          icon: _adding
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add, size: 16),
          label: Text(_adding ? 'Adding…' : 'Add'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.dark,
            foregroundColor: Colors.white,
            elevation: 0,
            // The global theme sets minimumSize width to double.infinity
            // (full-width buttons). This button lives in a Row's inflexible
            // slot, which Flutter measures with an UNBOUNDED main axis, so the
            // infinite minimum width throws "BoxConstraints forces an infinite
            // width" and blanks the whole page. Pin the width floor to 0 so it
            // sizes to its content instead.
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ]);
  }

  Widget _buildDomainCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final enabled = data['enabled'] == true;
    final addedAt = data['addedAt'];
    final added = addedAt is Timestamp
        ? '${addedAt.toDate().year}-${addedAt.toDate().month.toString().padLeft(2, '0')}-${addedAt.toDate().day.toString().padLeft(2, '0')}'
        : '—';
    final isPublic = kPublicEmailProviders.contains(doc.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.alternate_email,
            size: 20,
            color: enabled ? AppColors.dark : AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(doc.id,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      decoration: enabled ? null : TextDecoration.lineThrough,
                    )),
              ),
              if (isPublic) ...[
                const SizedBox(width: 8),
                _pill('PUBLIC PROVIDER', AppColors.error),
              ],
              if (!enabled) ...[
                const SizedBox(width: 8),
                _pill('REMOVED', AppColors.textSecondary),
              ],
            ]),
            const SizedBox(height: 3),
            Text('Added $added',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ),
        TextButton(
          onPressed: () => _setEnabled(doc.id, !enabled),
          child: Text(enabled ? 'Remove' : 'Re-enable',
              style: TextStyle(
                  color: enabled ? AppColors.error : AppColors.dark,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      );
}
