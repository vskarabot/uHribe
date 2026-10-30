import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/strings.dart';
import '../../models/friend.dart';
import '../../providers.dart';
import '../../theme.dart';
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
                          _sectionOf(items[index - 1].visitedOn) != _sectionOf(item.visitedOn))
                        _SectionHeader(_sectionOf(item.visitedOn)),
                      _FeedTile(
                        item: item,
                        showDate: _sectionOf(item.visitedOn) == Strings.feedThisWeek,
                        onTap: () => ref.read(peakFocusProvider.notifier).focus(item.peakId),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  static String _sectionOf(DateTime visitedOn) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(visitedOn.year, visitedOn.month, visitedOn.day);
    if (!day.isBefore(today)) return Strings.feedToday;
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    if (!day.isBefore(weekStart)) return Strings.feedThisWeek;
    return _formatDate(day);
  }
}

String _formatDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

String _formatTime(DateTime t) =>
    '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({required this.item, required this.showDate, required this.onTap});

  final FeedItem item;
  final bool showDate;
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
            showDate
                ? '${item.visitedOn.day}. ${item.visitedOn.month}. · ${_formatTime(item.visitedAt)}'
                : _formatTime(item.visitedAt),
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
