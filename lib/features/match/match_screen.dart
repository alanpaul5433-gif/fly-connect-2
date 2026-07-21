import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/providers/match_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/utils/open_chat.dart';
import '../../shared/models/models.dart';
import '../home/main_shell.dart' show AppDrawer;
import '../../shared/widgets/cached_image.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});
  @override State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> with SingleTickerProviderStateMixin {
  String _matchType = 'buddy'; // buddy | dating | solo
  /// The person we actually matched with, held separately from the candidate
  /// list because that list has already moved on by the time the banner shows.
  /// Non-null means the banner is visible.
  UserModel? _matchedWith;
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MatchProvider>().loadCandidates();
    });
  }

  @override
  void dispose() { _animCtrl.dispose(); super.dispose(); }

  Future<void> _like(UserModel user) async {
    final isMatch = await context.read<MatchProvider>().likeUser(user.uid, _matchType);
    // H1: the banner used to fire on every like. The provider always knew
    // whether the like was mutual; likeUser just returned void, so there was
    // nothing to branch on.
    if (!isMatch || !mounted) return;
    // H2: hold on to the person actually matched. The banner used to read
    // `provider.candidates.first`, but likeUser removes the liked candidate
    // first — so that is the NEXT card, and the banner named the wrong person.
    setState(() => _matchedWith = user);
    _animCtrl.forward();
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      _animCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) setState(() => _matchedWith = null);
    }
  }

  Future<void> _pass(UserModel user) async {
    await context.read<MatchProvider>().passUser(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppTopBar(
        showMenuIcon: true,
        showBack: Navigator.canPop(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_outlined, color: AppColors.textPrimary),
            onPressed: () => context.push(AppRoutes.matchPreferences)),
          const TopBarActions(),
        ],
      ),
      body: Column(children: [
        // Header + type filter
        Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Match', style: AppTextStyles.h2),
          const SizedBox(height: 12),
          // Match type tabs
          Container(
            decoration: BoxDecoration(color: AppColors.backgroundGrey, borderRadius: BorderRadius.circular(100)),
            padding: const EdgeInsets.all(4),
            child: Row(children: [
              _TypeTab(label: '✈️  Buddy', value: 'buddy', current: _matchType,
                onTap: (v) { setState(() => _matchType = v); context.read<MatchProvider>().loadCandidates(); }),
              _TypeTab(label: '💑  Dating', value: 'dating', current: _matchType,
                onTap: (v) { setState(() => _matchType = v); context.read<MatchProvider>().loadCandidates(); }),
              _TypeTab(label: '🎒  Solo', value: 'solo', current: _matchType,
                onTap: (v) { setState(() => _matchType = v); context.read<MatchProvider>().loadCandidates(); }),
            ]),
          ),
        ])),
        const SizedBox(height: 16),
        // Card stack
        Expanded(child: Consumer<MatchProvider>(
          builder: (context, provider, _) {
            final Widget cards;
            if (provider.loading) {
              cards = const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
            } else if (provider.candidates.isEmpty) {
              cards = _NoMoreCards(onRefresh: () => provider.loadCandidates());
            } else {
              final user = provider.candidates.first;
              cards = Stack(children: [
                // Background card peek
                if (provider.candidates.length > 1) Positioned(
                  left: 28, right: 28, top: 8, bottom: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24)),
                  )),
                // Main swipe card
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _SwipeCard(
                    user: user,
                    onLike: () => _like(user),
                    onPass: () => _pass(user),
                    matchType: _matchType,
                  )),
              ]);
            }

            // The banner is layered OUTSIDE the card branches on purpose:
            // liking your last remaining candidate empties the list, and when
            // the banner lived inside that branch the empty-state early return
            // meant the one match you did get was the one you never saw.
            final matched = _matchedWith;
            return Stack(children: [
              cards,
              if (matched != null)
                Positioned(top: 0, left: 0, right: 0,
                  child: SlideTransition(position: _slideAnim,
                    child: _MatchBanner(user: matched,
                      onMessage: () async {
                        await OpenChat.withUser(
                          context,
                          otherUid: matched.uid,
                          otherName: matched.name,
                          otherPhotoUrl: matched.photoUrl,
                        );
                      }))),
            ]);
          },
        )),
      ]),
    );
  }
}

class _TypeTab extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onTap;
  const _TypeTab({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return Expanded(child: GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.dark : Colors.transparent,
          borderRadius: BorderRadius.circular(100)),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textSecondary))),
      ),
    ));
  }
}

class _SwipeCard extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLike, onPass;
  final String matchType;
  const _SwipeCard({required this.user, required this.onLike, required this.onPass, required this.matchType});
  @override State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard> {
  Offset _dragOffset = Offset.zero;
  double _rotation = 0;

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset += d.delta;
      _rotation = _dragOffset.dx * 0.003;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_dragOffset.dx > 80) { widget.onLike(); _reset(); }
    else if (_dragOffset.dx < -80) { widget.onPass(); _reset(); }
    else { setState(() { _dragOffset = Offset.zero; _rotation = 0; }); }
  }

  void _reset() => setState(() { _dragOffset = Offset.zero; _rotation = 0; });

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(angle: _rotation,
          child: Stack(children: [
            // Card
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: const BoxDecoration(color: AppColors.backgroundGrey),
                child: Stack(fit: StackFit.expand, children: [
                  // Photo
                  u.photoUrl != null
                    ? RepaintBoundary(
                        child: CachedFeedImage(url: u.photoUrl!, fit: BoxFit.cover,
                          errorWidget: _PlaceholderAvatar(name: u.name)))
                    : _PlaceholderAvatar(name: u.name),
                  // Gradient overlay
                  const DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                      stops: [0.4, 1.0]))),
                  // Like / Pass indicator overlay
                  if (_dragOffset.dx > 30)
                    Positioned(top: 24, left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(border: Border.all(color: Colors.green, width: 3),
                          borderRadius: BorderRadius.circular(8)),
                        child: Text('LIKE', style: TextStyle(color: Colors.green,
                          fontSize: 28, fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 8)])))),
                  if (_dragOffset.dx < -30)
                    Positioned(top: 24, right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(border: Border.all(color: Colors.red, width: 3),
                          borderRadius: BorderRadius.circular(8)),
                        child: Text('PASS', style: TextStyle(color: Colors.red,
                          fontSize: 28, fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 8)])))),
                  // Info
                  Positioned(bottom: 100, left: 20, right: 20, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u.name}${u.city != null ? ', ${u.city}' : ''}',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                    if (u.airline != null) Text('${u.airline} · ${u.position ?? ''}',
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    if (u.bio != null) ...[
                      const SizedBox(height: 8),
                      Text(u.bio!, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 6, children: u.hobbies.take(4).map((h) =>
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: Colors.white38)),
                        child: Text(h, style: const TextStyle(color: Colors.white, fontSize: 12)))).toList()),
                  ])),
                ])),
            ),
            // Action buttons
            Positioned(bottom: 20, left: 0, right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ActionBtn(icon: Icons.close, color: Colors.red, size: 52, onTap: widget.onPass),
                const SizedBox(width: 20),
                _ActionBtn(
                  icon: Icons.person_outline,
                  color: AppColors.primary,
                  size: 44,
                  onTap: () => context.push('/users/${u.uid}'),
                ),
                const SizedBox(width: 20),
                _ActionBtn(icon: Icons.favorite, color: Colors.pink, size: 52, onTap: widget.onLike),
              ])),
          ]),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final Color color; final double size; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.size, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: size, height: size,
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Icon(icon, color: color, size: size * 0.48)));
}

class _PlaceholderAvatar extends StatelessWidget {
  final String name;
  const _PlaceholderAvatar({required this.name});
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.dark,
    child: Center(child: Text(name.isNotEmpty ? name[0] : '?',
      style: const TextStyle(color: AppColors.primary, fontSize: 80, fontWeight: FontWeight.bold))));
}

class _MatchBanner extends StatelessWidget {
  final UserModel user; final VoidCallback onMessage;
  const _MatchBanner({required this.user, required this.onMessage});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)]),
      // H3: the banner overflowed the right screen edge — text clipped
      // mid-word and the button running off-screen. It sits in a Positioned
      // with top/left/right and no bottom, so its height is UNBOUNDED, and a
      // Column defaults to mainAxisSize.max — it tried to take infinite
      // height. Constraining it to its children fixes the layout.
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🎉 It\'s a Match!', style: TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('You and ${user.name} liked each other!',
          style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('Send Message'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.dark,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
          onPressed: onMessage),
      ]));
  }
}

class _NoMoreCards extends StatelessWidget {
  final VoidCallback onRefresh;
  const _NoMoreCards({required this.onRefresh});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('✈️', style: TextStyle(fontSize: 64)),
    const SizedBox(height: 16),
    const Text('No more profiles', style: AppTextStyles.h4),
    const SizedBox(height: 8),
    Text('Check back later for new matches!',
      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
    const SizedBox(height: 24),
    ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.dark,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
      onPressed: onRefresh, child: const Text('Refresh', style: TextStyle(fontWeight: FontWeight.bold))),
  ]));
}
