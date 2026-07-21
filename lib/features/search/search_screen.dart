import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/search_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/cached_image.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  late TabController _tabs;

  // Search is debounced to stop each keystroke from firing its own
  // Firestore query. At 5M users the un-debounced version would mean
  // ~7 reads per word typed, every keystroke billed.
  Timer? _debounce;
  static const Duration _debounceDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose(); _tabs.dispose(); super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    // Run the clear synchronously so the UI feels instant on empty.
    if (trimmed.isEmpty) {
      context.read<SearchProvider>().clear();
      return;
    }
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      context.read<SearchProvider>().search(trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => context.pop()),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: 'Search people, groups, events...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey.shade400)),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.clear, color: Colors.grey),
              onPressed: () { _ctrl.clear(); context.read<SearchProvider>().clear(); }),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.dark,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [Tab(text: 'People'), Tab(text: 'Groups'), Tab(text: 'Events')],
        ),
      ),
      body: Consumer<SearchProvider>(
        builder: (context, provider, _) {
          if (provider.loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          if (provider.query.isEmpty) return _emptyState();
          return TabBarView(controller: _tabs, children: [
            _peopleList(provider.userResults),
            _groupsList(provider.groupResults),
            _eventsList(provider.eventResults),
          ]);
        },
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.search, size: 64, color: Colors.grey.shade300),
    const SizedBox(height: 12),
    Text('Search for people, groups, and events', style: TextStyle(color: Colors.grey.shade400)),
  ]));

  Widget _peopleList(List<UserModel> users) {
    if (users.isEmpty) return _noResults('people');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (_, i) {
        final u = users[i];
        return ListTile(
          leading: CachedAvatar(
            url: u.photoUrl,
            radius: 20,
            backgroundColor: AppColors.dark,
            fallback: Text(u.name.isNotEmpty ? u.name[0] : '?', style: const TextStyle(color: Colors.white))),
          title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${u.airline ?? ''} · ${u.position ?? ''}', style: const TextStyle(fontSize: 12)),
          trailing: OutlinedButton(
            onPressed: () => context.push('${AppRoutes.userProfile}/${u.uid}'),
            // Contrast: 'View' on white with primary fails AA (1.7:1).
            // Switch text + border to dark so the button reads cleanly.
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.dark),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('View', style: TextStyle(color: AppColors.dark, fontSize: 12, fontWeight: FontWeight.w600))),
          onTap: () => context.push('${AppRoutes.userProfile}/${u.uid}'),
        );
      },
    );
  }

  Widget _groupsList(List<GroupModel> groups) {
    if (groups.isEmpty) return _noResults('groups');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (_, i) {
        final g = groups[i];
        return ListTile(
          leading: CachedAvatar(
            url: g.imageUrl,
            radius: 20,
            backgroundColor: AppColors.primary,
            fallback: const Icon(Icons.group, color: AppColors.dark)),
          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${g.memberCount} members', style: const TextStyle(fontSize: 12)),
          onTap: () => context.push('${AppRoutes.groupDetails}/${g.id}'),
        );
      },
    );
  }

  Widget _eventsList(List<EventModel> events) {
    if (events.isEmpty) return _noResults('events');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            child: const Icon(Icons.event, color: AppColors.dark)),
          title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${e.location} · ${e.rsvpCount} going', style: const TextStyle(fontSize: 12)),
          onTap: () => context.push('${AppRoutes.eventDetails}/${e.id}'),
        );
      },
    );
  }

  Widget _noResults(String type) => Center(
    child: Text('No $type found for "${_ctrl.text}"', style: const TextStyle(color: Colors.grey)));
}
