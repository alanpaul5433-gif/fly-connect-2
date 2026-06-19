import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/group_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/cached_image.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 2, child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Groups', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () => context.push(AppRoutes.createGroup)),
        ],
        bottom: const TabBar(
          labelColor: AppColors.dark,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: [Tab(text: 'Discover'), Tab(text: 'My Groups')],
        ),
      ),
      body: Consumer<GroupProvider>(
        builder: (context, provider, _) => TabBarView(children: [
          _groupsList(context, provider.groups, provider, discover: true),
          _groupsList(context, provider.myGroups, provider, discover: false),
        ]),
      ),
    ));
  }

  Widget _groupsList(BuildContext context, List<GroupModel> groups, GroupProvider provider, {required bool discover}) {
    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        title: discover ? 'No groups yet' : 'No groups joined',
        subtitle: discover
            ? 'Start your own crew community.'
            : 'Discover groups from your airline or city to join.',
        actionLabel: discover ? 'Create Group' : 'Discover Groups',
        onAction: () {
          if (discover) {
            context.push(AppRoutes.createGroup);
          } else {
            // Switch tab to Discover — both lists live in this widget,
            // so just nudge the user toward the other tab.
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Tap "Discover" above to find groups to join.'),
              duration: Duration(seconds: 2),
            ));
          }
        },
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        final isMember = provider.isMember(g.id);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CachedAvatar(
              url: g.imageUrl,
              radius: 28,
              backgroundColor: AppColors.primary,
              fallback: const Icon(Icons.group, color: AppColors.dark)),
            title: Row(children: [
              Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (g.isPinned) const Icon(Icons.push_pin, size: 14, color: AppColors.primary),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              // Member count + up to 2 tag chips. Wrapped in Expanded→Wrap so a
              // large member count or long tags flow to a second line instead of
              // overflowing the ListTile subtitle (was a RenderFlex overflow).
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.people, size: 12, color: Colors.grey.shade400),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Wrap(
                    spacing: 6, runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${g.memberCount} members',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ...g.tags.take(2).map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                        child: Text(tag,
                          style: const TextStyle(fontSize: 10, color: AppColors.dark)))),
                    ],
                  ),
                ),
              ]),
            ]),
            trailing: isMember
              ? OutlinedButton(onPressed: () => provider.leaveGroup(g.id),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Leave', style: TextStyle(fontSize: 12)))
              : ElevatedButton(onPressed: () => provider.joinGroup(g.id),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.dark, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Join', style: TextStyle(fontSize: 12))),
            onTap: () {
              final isBusiness = context.read<AuthProvider>().userRole == 'business';
              if (isBusiness) {
                context.push('/business-group-management');
              } else {
                context.push('${AppRoutes.groupDetails}/${g.id}');
              }
            },
          ),
        );
      },
    );
  }
}
