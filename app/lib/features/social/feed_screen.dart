import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../models/friend.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../widgets/date_sections.dart';
import 'user_avatar.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(friendsFeedProvider);
    final friendsAsync = ref.watch(friendsProvider);
    final incoming = ref.watch(incomingRequestCountProvider);
    final hasFriends =
        friendsAsync.value?.any((f) => f.status == FriendshipStatus.friends) ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(Strings.navFeed, style: AppTheme.tabTitleStyle(context)),
        actions: [
          IconButton(
            tooltip: Strings.friendsTitle,
            icon: Badge(
              isLabelVisible: incoming > 0,
              label: Text('$incoming'),
              child: const Icon(Icons.people_outline),
            ),
            onPressed: () => context.push('/friends'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(friendsProvider);
          return ref.refresh(friendsFeedProvider.future);
        },
        child: feedAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 120),
              const Center(child: Text(Strings.loadError)),
              const SizedBox(height: 12),
              Center(
                child: FilledButton(
                  onPressed: () => ref.invalidate(friendsFeedProvider),
                  child: const Text(Strings.retry),
                ),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? _EmptyFeed(hasFriends: hasFriends)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
                  children: [
                    for (final (index, item) in items.indexed) ...[
                      if (index == 0 ||
                          dateSectionOf(items[index - 1].visitedOn) !=
                              dateSectionOf(item.visitedOn))
                        DateSectionHeader(dateSectionOf(item.visitedOn)),
                      _FeedTile(
                        item: item,
                        onTap: () => ref.read(peakFocusProvider.notifier).focus(item.peakId),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({required this.item, required this.onTap});

  final FeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: UserAvatar(url: item.avatarUrl),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.displayName ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            visitTimeLabel(item.visitedOn, item.visitedAt),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Text(
        [item.peakName, if (item.elevationM != null) '${item.elevationM} m'].join(' · '),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.hasFriends});

  final bool hasFriends;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasFriends ? Strings.feedEmpty : Strings.noFriendsYet,
                    textAlign: TextAlign.center,
                  ),
                  if (!hasFriends) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/friends'),
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                      label: const Text(Strings.addFriends),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
