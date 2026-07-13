import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/event_provider.dart';

// ignore_for_file: use_build_context_synchronously

class EventManagementScreen extends StatefulWidget {
  final EventModel event;
  const EventManagementScreen({super.key, required this.event});
  @override
  State<EventManagementScreen> createState() => _EventManagementScreenState();
}

class _EventManagementScreenState extends State<EventManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<UserModel> _approved;
  late List<UserModel> _pending;
  late List<UserModel> _declined;
  late String _editTitle;
  late String _editDesc;
  late String _editLocation;

  bool _loadingAttendees = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _approved = <UserModel>[];
    _pending = <UserModel>[];
    _declined = [];
    _editTitle = widget.event.title;
    _editDesc = widget.event.description;
    _editLocation = widget.event.location;
    _loadAttendees();
  }

  Future<void> _loadAttendees() async {
    try {
      final rsvpSnap = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('rsvps')
          .get();

      final futures = rsvpSnap.docs.map((rsvpDoc) async {
        final uid = rsvpDoc.id;
        final status = (rsvpDoc.data()['status'] as String?) ?? 'pending';
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (!userDoc.exists) return null;
        return MapEntry(status, UserModel.fromFirestore(userDoc));
      });

      final results = await Future.wait(futures);
      final approved = <UserModel>[];
      final pending = <UserModel>[];
      final declined = <UserModel>[];

      for (final entry in results) {
        if (entry == null) continue;
        switch (entry.key) {
          case 'approved': approved.add(entry.value); break;
          case 'declined': declined.add(entry.value); break;
          default: pending.add(entry.value);
        }
      }

      if (mounted) {
        setState(() {
          _approved = approved;
          _pending = pending;
          _declined = declined;
          _loadingAttendees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAttendees = false);
    }
  }

  void _showEditSheet() {
    final titleCtrl = TextEditingController(text: _editTitle);
    final descCtrl = TextEditingController(text: _editDesc);
    final locCtrl = TextEditingController(text: _editLocation);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Edit Event', style: AppTextStyles.labelLarge)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 12),
            const Text('Title', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(controller: titleCtrl, decoration: InputDecoration(
              hintText: 'Event title',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            )),
            const SizedBox(height: 12),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(controller: descCtrl, maxLines: 3, decoration: InputDecoration(
              hintText: 'Event description',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            )),
            const SizedBox(height: 12),
            const Text('Location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(controller: locCtrl, decoration: InputDecoration(
              hintText: 'Event location',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            )),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final newTitle = titleCtrl.text.trim().isEmpty ? _editTitle : titleCtrl.text.trim();
                  final newDesc = descCtrl.text.trim().isEmpty ? _editDesc : descCtrl.text.trim();
                  final newLocation = locCtrl.text.trim().isEmpty ? _editLocation : locCtrl.text.trim();
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  try {
                    await context.read<EventProvider>().updateEvent(widget.event.id,
                      title: newTitle, description: newDesc, location: newLocation);
                    if (mounted) {
                      setState(() { _editTitle = newTitle; _editDesc = newDesc; _editLocation = newLocation; });
                    }
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Event updated successfully'), duration: Duration(seconds: 2)));
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Could not update event. Try again.')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark, foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  void _openEventChat() {
    final e = widget.event;
    context.push('/conversation/evt_${e.id}?name=${Uri.encodeComponent(e.title)}&group=true');
  }

  void _removeAttendee(UserModel u, String status) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Attendee'),
        content: Text('Remove ${u.name} from this event?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              setState(() {
                if (status == 'approved') {
                  _approved.remove(u);
                } else if (status == 'pending') _pending.remove(u);
                else _declined.remove(u);
              });
              try {
                await context.read<EventProvider>().removeAttendee(widget.event.id, u.uid);
                messenger.showSnackBar(
                  SnackBar(content: Text('${u.name} removed'), duration: const Duration(seconds: 2)));
              } catch (_) {
                if (mounted) {
                  setState(() {
                    if (status == 'approved') {
                      _approved.add(u);
                    } else if (status == 'pending') _pending.add(u);
                    else _declined.add(u);
                  });
                }
                messenger.showSnackBar(
                  const SnackBar(content: Text('Could not remove attendee. Try again.')));
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _approve(UserModel u) async {
    setState(() { _pending.remove(u); _approved.add(u); });
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('rsvps')
          .doc(u.uid)
          .set({'status': 'approved'}, SetOptions(merge: true));
    } catch (_) {
      // Revert optimistic update on failure
      if (mounted) setState(() { _approved.remove(u); _pending.add(u); });
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${u.name} approved'), duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _decline(UserModel u) async {
    setState(() { _pending.remove(u); _declined.add(u); });
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('rsvps')
          .doc(u.uid)
          .set({'status': 'declined'}, SetOptions(merge: true));
    } catch (_) {
      if (mounted) setState(() { _declined.remove(u); _pending.add(u); });
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${u.name} declined'), duration: const Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final fmt = DateFormat('MMM d, y');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: Text(_editTitle, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.black),
            onPressed: _openEventChat,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.black),
            onPressed: _showEditSheet,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'https://flyconnect.co/events/${e.id}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied!')));
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Event header card
            Container(
              decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      e.imageUrl!, height: 160, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(height: 160, color: Colors.white10,
                        child: const Center(child: Icon(Icons.event, color: AppColors.primary, size: 48))),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(_editTitle, style: AppTextStyles.h4.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 14),
                  const SizedBox(width: 6),
                  Text('${fmt.format(e.date)} · ${e.time}',
                    style: AppTextStyles.caption.copyWith(color: Colors.white70)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.location,
                    style: AppTextStyles.caption.copyWith(color: Colors.white70))),
                ]),
              ]),
            ),

            const SizedBox(height: 20),

            // Stats row
            Row(children: [
              Expanded(child: _StatCard(value: e.rsvpCount.toString(), label: 'Total RSVPs', icon: Icons.people_outline)),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(value: _approved.length.toString(), label: 'Approved', icon: Icons.check_circle_outline)),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(value: _pending.length.toString(), label: 'Pending', icon: Icons.hourglass_empty)),
            ]),

            const SizedBox(height: 20),

            // Tab bar + attendee lists
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(children: [
                TabBar(
                  controller: _tabs,
                  labelColor: AppColors.dark,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(text: 'Approved (${_approved.length})'),
                    Tab(text: 'Pending (${_pending.length})'),
                    Tab(text: 'Declined (${_declined.length})'),
                  ],
                ),
                SizedBox(
                  height: 400,
                  child: _loadingAttendees
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : TabBarView(controller: _tabs, children: [
                        _attendeeList(_approved, 'approved'),
                        _attendeeList(_pending, 'pending'),
                        _attendeeList(_declined, 'declined'),
                      ]),
                ),
              ]),
            ),

            const SizedBox(height: 20),
          ]),
        )),
      ]),
    );
  }

  Widget _attendeeList(List<UserModel> users, String status) {
    if (users.isEmpty) {
      return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No $status attendees', style: AppTextStyles.caption)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (_, i) {
        final u = users[i];
        return Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.dark,
            backgroundImage: u.photoUrl != null ? NetworkImage(u.photoUrl!) : null,
            child: u.photoUrl == null
              ? Text(u.name.isNotEmpty ? u.name[0] : '?',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))
              : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u.name, style: AppTextStyles.labelMedium),
            Text('${u.airline ?? ''} · ${u.position ?? ''}', style: AppTextStyles.caption),
          ])),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (status == 'approved')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(100)),
                child: const Text('Attending',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 11)),
              )
            else if (status == 'pending')
              Row(mainAxisSize: MainAxisSize.min, children: [
                ElevatedButton(
                  onPressed: () => _approve(u),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: AppColors.dark,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text('Approve', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () => _decline(u),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text('Decline', style: TextStyle(fontSize: 11)),
                ),
              ])
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(100)),
                child: const Text('Declined',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 11)),
              ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              color: AppColors.primary,
              onPressed: () => context.push(
                '/conversation/evt_${widget.event.id}_${u.uid}?name=${Uri.encodeComponent(u.name)}&photo=${u.photoUrl ?? ''}'),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              color: Colors.red.shade300,
              onPressed: () => _removeAttendee(u, status),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
          ]),
        ]);
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _StatCard({required this.value, required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.primary, size: 18),
      const SizedBox(height: 8),
      Text(value, style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
      Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70)),
    ]));
}
