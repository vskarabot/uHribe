import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/strings.dart';
import '../../models/elevation_bracket.dart';
import '../../models/nearby_filter.dart';
import '../../models/peak.dart';
import '../../providers.dart';
import '../../theme.dart';
import 'peak_filter_chips.dart';

class PeakListScreen extends ConsumerStatefulWidget {
  const PeakListScreen({super.key});

  @override
  ConsumerState<PeakListScreen> createState() => _PeakListScreenState();
}

class _PeakListScreenState extends ConsumerState<PeakListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Peak> _filterAndSort(
    List<Peak> peaks,
    String? area,
    ElevationBracket? elevation,
    NearbyFilter? nearby,
  ) {
    var result = peaks.where((p) {
      if (area != null && p.mountainArea != area) return false;
      if (elevation != null && !elevation.matches(p.elevationM)) return false;
      if (nearby != null && !nearby.matches(p)) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          (p.nameAlt?.toLowerCase().contains(q) ?? false);
    }).toList();

    if (nearby != null) {
      result.sort((a, b) => nearby.distanceM(a).compareTo(nearby.distanceM(b)));
    } else {
      result.sort((a, b) => (b.elevationM ?? 0).compareTo(a.elevationM ?? 0));
    }
    return result;
  }

  void _clearFilters() {
    clearPeakFilters(ref);
    _searchController.clear();
    setState(() => _query = '');
  }

  static String? _metaLine(Peak peak, NearbyFilter? nearby) {
    final parts = [
      if (nearby != null) Strings.distance(nearby.distanceM(peak)),
      if (peak.elevationM != null) '${peak.elevationM} m',
      if (peak.mountainArea != null) peak.mountainArea!,
    ];
    return parts.isEmpty ? null : parts.join('  |  ');
  }

  @override
  Widget build(BuildContext context) {
    final peaksAsync = ref.watch(peaksProvider);
    final visitedAsync = ref.watch(visitedPeakIdsProvider);
    final visitedIds = visitedAsync.value ?? const <int>{};
    final selectedArea = ref.watch(selectedMountainAreaProvider);
    final selectedElevation = ref.watch(selectedElevationBracketProvider);
    final selectedNearby = ref.watch(selectedNearbyFilterProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final allPeaks = peaksAsync.value;
    final filtered = allPeaks == null
        ? null
        : _filterAndSort(allPeaks, selectedArea, selectedElevation, selectedNearby);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Strings.greeting(ref.watch(myProfileProvider).value?.displayName),
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 22),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ShadowedField(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: Strings.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          iconSize: 20,
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: PeakFilterChips(),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  Strings.navPeaks,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (filtered != null)
                  Text(
                    Strings.peakCount(filtered.length, of: allPeaks!.length),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: peaksAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => _ErrorState(
                onRetry: () => ref.invalidate(peaksProvider),
              ),
              data: (_) {
                if (filtered!.isEmpty) {
                  return _EmptyState(
                    filtered: selectedArea != null ||
                        selectedElevation != null ||
                        selectedNearby != null ||
                        _query.isNotEmpty,
                    onClearFilters: _clearFilters,
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 8,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 16,
                    endIndent: 16,
                    color: colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) {
                    final peak = filtered[index];
                    final visited = visitedIds.contains(peak.id);
                    final meta = _metaLine(peak, selectedNearby);
                    return ListTile(
                      title: Text(peak.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: meta == null
                          ? null
                          : Text(
                              meta,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (visited) ...[
                            Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
                            const SizedBox(width: 6),
                          ],
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                      onTap: () => ref.read(peakFocusProvider.notifier).focus(peak.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClearFilters});

  final bool filtered;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Strings.noPeaksFound),
          if (filtered) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text(Strings.clearFilters),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(Strings.loadError),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text(Strings.retry)),
        ],
      ),
    );
  }
}
