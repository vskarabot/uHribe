import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/friend.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../widgets/confirm_dialog.dart';
import 'user_avatar.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<Friend>? _results;
  bool _searching = false;
  final _busyIds = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
    _debounce?.cancel();
    if (_query.length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(_query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final results = await ref.read(socialRepositoryProvider).search(query);
      if (mounted && query == _query) setState(() => _results = results);
    } catch (_) {
      if (mounted && query == _query) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _run(Friend friend, Future<FriendshipStatus> Function() action) async {
    setState(() => _busyIds.add(friend.userId));
    try {
      final status = await action();
      if (!mounted) return;
      setState(() {
        _results = _results
            ?.map((r) => r.userId == friend.userId ? r.copyWith(status: status) : r)
            .toList();
      });
      ref.invalidate(friendsProvider);
      ref.invalidate(friendsFeedProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(Strings.friendActionError)));
    } finally {
      if (mounted) setState(() => _busyIds.remove(friend.userId));
    }
  }

  Future<void> _add(Friend f) =>
      _run(f, () => ref.read(socialRepositoryProvider).sendRequest(f.userId));

  Future<void> _accept(Friend f) => _run(f, () async {
        await ref.read(socialRepositoryProvider).acceptRequest(f.userId);
        return FriendshipStatus.friends;
      });

  Future<void> _remove(Friend f) => _run(f, () async {
        await ref.read(socialRepositoryProvider).removeFriendship(f.userId);
        return FriendshipStatus.none;
      });

  Future<void> _confirmRemove(Friend f) async {
    final confirmed = await showConfirmDialog(
      context,
      message: Strings.removeFriendConfirm,
      confirmLabel: Strings.remove,
    );
    if (confirmed) await _remove(f);
  }

  Widget _actions(Friend f) {
    if (_busyIds.contains(f.userId)) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    switch (f.status) {
      case FriendshipStatus.none:
        return FilledButton.tonalIcon(
          onPressed: () => _add(f),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text(Strings.addFriend),
        );
      case FriendshipStatus.outgoing:
        return TextButton(
          onPressed: () => _remove(f),
          child: const Text(Strings.cancel),
        );
      case FriendshipStatus.incoming:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: Strings.decline,
              icon: const Icon(Icons.close),
              onPressed: () => _remove(f),
            ),
            FilledButton(onPressed: () => _accept(f), child: const Text(Strings.accept)),
          ],
        );
      case FriendshipStatus.friends:
        return IconButton(
          tooltip: Strings.removeFriend,
          icon: const Icon(Icons.person_remove_outlined),
          onPressed: () => _confirmRemove(f),
        );
    }
  }

  Widget _tile(Friend f) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: UserAvatar(url: f.avatarUrl),
      title: Text(f.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: f.status == FriendshipStatus.outgoing
          ? Text(Strings.requestSent, style: TextStyle(color: colorScheme.onSurfaceVariant))
          : (f.homeRegion?.isNotEmpty == true ? Text(f.homeRegion!) : null),
      trailing: _actions(f),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.friendsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ShadowedField(
              child: TextField(
                controller: _searchController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: Strings.searchPeopleHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          iconSize: 20,
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                ),
                onChanged: _onQueryChanged,
              ),
            ),
          ),
          Expanded(
            child: _query.length >= 2 ? _buildResults() : _buildFriends(friendsAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final results = _results;
    if (results == null || (_searching && results.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) return const Center(child: Text(Strings.noPeopleFound));
    return ListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
      children: results.map(_tile).toList(),
    );
  }

  Widget _buildFriends(AsyncValue<List<Friend>> friendsAsync) {
    return friendsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(Strings.loadError),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(friendsProvider),
              child: const Text(Strings.retry),
            ),
          ],
        ),
      ),
      data: (all) {
        final incoming = all.where((f) => f.status == FriendshipStatus.incoming).toList();
        final outgoing = all.where((f) => f.status == FriendshipStatus.outgoing).toList();
        final friends = all.where((f) => f.status == FriendshipStatus.friends).toList();

        return RefreshIndicator(
          onRefresh: () => ref.refresh(friendsProvider.future),
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
            children: [
              if (incoming.isNotEmpty) ...[
                _sectionHeader(Strings.friendRequests),
                ...incoming.map(_tile),
              ],
              _sectionHeader(Strings.friendsTitle),
              if (friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(Strings.noFriendsYet),
                )
              else
                ...friends.map(_tile),
              if (outgoing.isNotEmpty) ...[
                _sectionHeader(Strings.sentRequests),
                ...outgoing.map(_tile),
              ],
            ],
          ),
        );
      },
    );
  }
}
