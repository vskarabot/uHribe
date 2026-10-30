import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';

class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  ConsumerState<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends ConsumerState<LocationPermissionScreen> {
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await rememberLocationEnabled(ref, true);
      }
    } catch (_) {
    }
    await ref.read(locationPromptSeenProvider.notifier).markSeen();
  }

  Future<void> _skip() async {
    await ref.read(locationPromptSeenProvider.notifier).markSeen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.my_location, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              const Text(
                Strings.locationPromptTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                Strings.locationPromptBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _allow,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(Strings.locationPromptAllow),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text(Strings.locationPromptSkip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
