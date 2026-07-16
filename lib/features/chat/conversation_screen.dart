import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/models/models.dart';

class ConversationScreen extends StatefulWidget {
  final String chatId;
  final String otherName;
  final String? otherPhotoUrl;
  final bool isGroup;
  const ConversationScreen({super.key, required this.chatId, required this.otherName, this.otherPhotoUrl, this.isGroup = false});
  @override State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final chatProvider = context.read<ChatProvider>();
    chatProvider.markAsRead(widget.chatId);
    chatProvider.markMessagesRead(widget.chatId);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() => _sending = true);
    try {
      await context.read<ChatProvider>().sendMessage(widget.chatId, text);
      if (!mounted) return;
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _showConversationMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Mute / Clear-conversation hidden for v1.0 — not yet implemented.
          // Report + Block below are fully functional (write to Firestore).
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title:
                const Text('Report user', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showReportSheet();
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text('Block user', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              await context
                  .read<PostProvider>()
                  .blockUser(widget.chatId); // chatId == other user's uid for DMs
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('User blocked. You will not see their content.'),
                  duration: Duration(seconds: 2),
                ));
              }
            },
          ),
        ]),
      ),
    );
  }

  void _showReportSheet() {
    const reasons = [
      'Spam or misleading',
      'Harassment or bullying',
      'Hate speech',
      'Sexual or explicit content',
      'Impersonation',
      'Other',
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Why are you reporting this?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          ...reasons.map((r) => ListTile(
                title: Text(r),
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<PostProvider>().reportContent(
                        targetType: widget.isGroup ? 'chat' : 'user',
                        targetId: widget.chatId,
                        reason: r,
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Report submitted. Our team will review it.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ));
                  }
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final myUid = context.read<AuthProvider>().currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: Row(children: [
          CircleAvatar(radius: 18,
            backgroundImage: widget.otherPhotoUrl != null ? NetworkImage(widget.otherPhotoUrl!) : null,
            backgroundColor: AppColors.dark,
            child: widget.otherPhotoUrl == null ? Text(widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.otherName, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600)),
            StreamBuilder<Map<String, bool>>(
              stream: context.read<ChatProvider>().watchTyping(widget.chatId),
              builder: (_, snap) {
                final typing = snap.data?.entries
                    .where((e) => e.key != myUid && e.value).isNotEmpty ?? false;
                // Contrast: `AppColors.primary` (neon yellow-green) on white
                // is 1.7:1 — fails WCAG AA. `AppColors.online` is a darker
                // green that passes the 3:1 large-text contrast bar and
                // matches the rest of the app's status indicators.
                return Text(typing ? 'typing...' : 'Online',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.online));
              }),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            tooltip: 'Conversation options',
            onPressed: _showConversationMenu,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: StreamBuilder<List<MessageModel>>(
          stream: context.read<ChatProvider>().watchMessages(widget.chatId),
          builder: (context, snap) {
            final msgs = snap.data ?? [];
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: msgs.length,
              itemBuilder: (context, i) {
                final m = msgs[i];
                final isMe = m.senderId == myUid;
                final showDate = i == 0 || !_sameDay(msgs[i - 1].createdAt, m.createdAt);
                return Column(children: [
                  if (showDate) Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_formatDate(m.createdAt),
                      style: const TextStyle(fontSize: 12, color: Colors.grey))),
                  Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.primary : Colors.grey.shade100,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16))),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (!isMe && widget.isGroup) Text(m.senderName,
                          // Sender label sits on Colors.grey.shade100 (≈ white)
                          // for incoming bubbles — primary fails contrast there.
                          // AppColors.dark gives 13.6:1 and reads clearly.
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark)),
                        Text(m.text, style: TextStyle(color: isMe ? AppColors.dark : Colors.black87, fontSize: 15)),
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(timeago.format(m.createdAt, allowFromNow: true),
                            style: TextStyle(fontSize: 10, color: isMe ? AppColors.dark.withValues(alpha: 0.6) : Colors.grey)),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(m.readBy.length > 1 ? Icons.done_all : Icons.done,
                              size: 14, color: AppColors.dark.withValues(alpha: 0.7)),
                          ],
                        ]),
                      ]),
                    )),
                ]);
              },
            );
          },
        )),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            // Image attach hidden for v1.0 — image messages not yet wired to Storage.
            Expanded(child: TextField(
              controller: _ctrl,
              onChanged: (v) => context.read<ChatProvider>().setTyping(widget.chatId, v.isNotEmpty),
              decoration: InputDecoration(
                hintText: 'Message...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.primary)),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(width: 42, height: 42,
                decoration: BoxDecoration(color: _sending ? Colors.grey.shade300 : AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: AppColors.dark, size: 20))),
          ]),
        ),
      ]),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (_sameDay(dt, now)) return 'Today';
    if (_sameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
