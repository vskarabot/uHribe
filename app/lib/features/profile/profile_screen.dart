import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../models/pending_checkin.dart';
import '../../models/profile.dart';
import '../../models/stats.dart';
import '../../models/visit.dart';
import '../../providers.dart';
import '../../theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final statsAsync = ref.watch(myStatsProvider);
    final visitsAsync = ref.watch(myVisitsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(Strings.navProfile),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text(Strings.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myProfileProvider);
          invalidateUserData(ref);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            profileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Text(Strings.loadError),
              data: (profile) => _ProfileHeader(profile: profile),
            ),
            const SizedBox(height: 24),
            statsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (stats) => _StatsSection(stats: stats),
            ),
            const SizedBox(height: 28),
            const _RejectedCheckInsSection(),
            Text(
              Strings.myVisits,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            visitsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const Text(Strings.loadError),
              data: (visits) => _VisitsSection(visits: visits),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  final Profile profile;

  const _ProfileHeader({required this.profile});

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

enum _SaveState { idle, saving, saved }

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  static const _savedHold = Duration(milliseconds: 900);

  bool _editing = false;
  bool _uploadingAvatar = false;
  _SaveState _saveState = _SaveState.idle;
  final _nameController = TextEditingController();
  String? _region;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _dirty {
    final profile = widget.profile;
    return _nameController.text.trim() != (profile.displayName ?? '') ||
        (_region ?? '') != (profile.homeRegion ?? '') ||
        (_avatarUrl ?? '') != (profile.avatarUrl ?? '');
  }

  void _startEditing() {
    final profile = widget.profile;
    setState(() {
      _nameController.text = profile.displayName ?? '';
      _region = profile.homeRegion;
      _avatarUrl = profile.avatarUrl;
      _saveState = _SaveState.idle;
      _editing = true;
    });
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(Strings.chooseFromGallery),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(Strings.takePhoto),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final url = await ref.read(profileRepositoryProvider).uploadAvatar(bytes, ext);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {
      if (mounted) _showSnackBar(context, Strings.avatarUploadError);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saveState = _SaveState.saving);
    try {
      await ref
          .read(profileRepositoryProvider)
          .update(
            displayName: _nameController.text.trim(),
            avatarUrl: _avatarUrl ?? '',
            homeRegion: _region ?? '',
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveState = _SaveState.idle);
      _showSnackBar(context, Strings.profileSaveError);
      return;
    }
    ref.invalidate(myProfileProvider);
    if (!mounted) return;
    setState(() => _saveState = _SaveState.saved);
    await Future<void>.delayed(_savedHold);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    if (!_editing) {
      return Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
                ? NetworkImage(profile.avatarUrl!)
                : null,
            child: (profile.avatarUrl == null || profile.avatarUrl!.isEmpty)
                ? const Icon(Icons.person, size: 32)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName?.isNotEmpty == true
                      ? profile.displayName!
                      : (profile.email ?? ''),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                if (profile.homeRegion != null && profile.homeRegion!.isNotEmpty)
                  Text(profile.homeRegion!),
              ],
            ),
          ),
          CustomPaint(
            foregroundPainter: _DottedCirclePainter(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            child: IconButton(
              icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.primary),
              tooltip: Strings.editProfile,
              onPressed: _startEditing,
            ),
          ),
        ],
      );
    }

    final busy = _saveState != _SaveState.idle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                Strings.editProfile,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: Strings.cancel,
              onPressed: busy ? null : () => setState(() => _editing = false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _uploadingAvatar ? null : _pickAvatar,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                      ? NetworkImage(_avatarUrl!)
                      : null,
                  child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                      ? const Icon(Icons.person, size: 40)
                      : null,
                ),
                if (_uploadingAvatar)
                  const Positioned.fill(
                    child: CircleAvatar(
                      backgroundColor: Colors.black38,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _uploadingAvatar ? null : _pickAvatar,
            child: const Text(Strings.changePhoto),
          ),
        ),
        const SizedBox(height: 4),
        ShadowedField(
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: Strings.displayName),
          ),
        ),
        const SizedBox(height: 12),
        ShadowedField(
          child: DropdownButtonFormField<String>(
            initialValue: _region,
            decoration: const InputDecoration(labelText: Strings.homeRegion),
            items: Strings.regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (v) => setState(() => _region = v),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: (_dirty || busy)
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    onPressed: (busy || _uploadingAvatar) ? null : _save,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _SaveButtonLabel(key: ValueKey(_saveState), state: _saveState),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _DottedCirclePainter extends CustomPainter {
  final Color color;

  const _DottedCirclePainter({required this.color});

  static const _dashCount = 12;

  static const _dashFraction = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 4,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    const step = 2 * math.pi / _dashCount;
    for (var i = 0; i < _dashCount; i++) {
      canvas.drawArc(rect, step * i, step * _dashFraction, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedCirclePainter oldDelegate) => oldDelegate.color != color;
}

class _SaveButtonLabel extends StatelessWidget {
  final _SaveState state;

  const _SaveButtonLabel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    return switch (state) {
      _SaveState.idle => const Text(Strings.save),
      _SaveState.saving => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      _SaveState.saved => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 18, color: color),
          const SizedBox(width: 8),
          Text(Strings.profileSaved, style: TextStyle(color: color)),
        ],
      ),
    };
  }
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 16),
    ),
  );
}

class _StatsSection extends StatelessWidget {
  final Stats stats;

  const _StatsSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final counters = <Widget>[
      _StatCard(label: Strings.statsPeaksVisited, value: '${stats.peaksVisited}'),
      _StatCard(label: Strings.statsTotalVisits, value: '${stats.totalVisits}'),
      _StatCard(label: Strings.statsThisYear, value: '${stats.visitsThisYear}'),
      _StatCard(
        label: Strings.statsTotalElevation,
        value: '${_groupThousands(stats.totalElevationM)} m',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Strings.statsTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final columns = constraints.maxWidth >= 640 ? 4 : 2;
            final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [for (final card in counters) SizedBox(width: width, child: card)],
            );
          },
        ),
        if (stats.highestPeakName != null) ...[
          const SizedBox(height: 12),
          _StatDetailTile(
            icon: Icons.landscape_outlined,
            label: Strings.statsHighestPeak,
            value: stats.highestPeakName!,
            trailing: stats.highestPeakElevationM != null
                ? '${stats.highestPeakElevationM} m'
                : null,
          ),
        ],
        if (stats.firstVisitOn != null) ...[
          const SizedBox(height: 8),
          _StatDetailTile(
            icon: Icons.flag_outlined,
            label: Strings.statsFirstVisit,
            value: stats.firstVisitPeakName ?? '',
            trailing: _formatDate(stats.firstVisitOn!),
          ),
        ],
        if (stats.lastVisitOn != null) ...[
          const SizedBox(height: 8),
          _StatDetailTile(
            icon: Icons.schedule_outlined,
            label: Strings.statsLastVisit,
            value: stats.lastVisitPeakName ?? '',
            trailing: _formatDate(stats.lastVisitOn!),
          ),
        ],
      ],
    );
  }
}

String _groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _formatDate(DateTime date) => '${date.day}. ${date.month}. ${date.year}';

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StatDetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? trailing;

  const _StatDetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Text(trailing!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _RejectedCheckInsSection extends ConsumerWidget {
  const _RejectedCheckInsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCheckInsProvider).value ?? const <PendingCheckIn>[];
    final rejected = pending.where((c) => c.rejected).toList(growable: false);
    if (rejected.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rejected.map(
          (checkIn) => Card(
            child: ListTile(
              leading: Icon(Icons.error_outline, color: colorScheme.error),
              title: Text(checkIn.peakName),
              subtitle: Text('${Strings.rejectedCheckIn}: ${checkIn.lastError ?? ''}'),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(pendingCheckInsProvider.notifier).discard(checkIn.clientId),
                child: const Text(Strings.discard),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _VisitsSection extends ConsumerStatefulWidget {
  final List<Visit> visits;

  const _VisitsSection({required this.visits});

  @override
  ConsumerState<_VisitsSection> createState() => _VisitsSectionState();
}

class _VisitsSectionState extends ConsumerState<_VisitsSection> {
  final _hiddenIds = <String>{};

  Future<void> _delete(Visit visit) async {
    setState(() => _hiddenIds.add(visit.id));
    try {
      await ref.read(visitsRepositoryProvider).deleteVisit(visit.id);
      invalidateUserData(ref);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hiddenIds.remove(visit.id));
      _showSnackBar(context, Strings.visitDeleteError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.visits.where((v) => !_hiddenIds.contains(v.id)).toList();
    if (visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(Strings.noVisitsYet),
      );
    }
    return Column(
      children: visible
          .map((v) => _VisitTile(visit: v, onDelete: () => _delete(v)))
          .toList(growable: false),
    );
  }
}

class _VisitTile extends StatelessWidget {
  final Visit visit;
  final VoidCallback onDelete;

  const _VisitTile({required this.visit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(visit.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        final confirmed = await _confirmDelete(context);
        if (confirmed) onDelete();
        return confirmed;
      },
      child: Card(
        child: ListTile(
          title: Text(visit.peakName ?? '#${visit.peakId}'),
          subtitle: Text(
            '${_formatDate(visit.visitedOn)}'
            '${visit.notes != null && visit.notes!.isNotEmpty ? ' · ${visit.notes}' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (visit.peakElevationM != null) ...[
                Text('${visit.peakElevationM} m'),
                const SizedBox(width: 4),
              ],
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: Strings.delete,
                onPressed: () async {
                  if (await _confirmDelete(context)) onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: const Text(Strings.deleteVisitConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(Strings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(Strings.delete),
              ),
            ],
          ),
        ) ??
        false;
  }
}
