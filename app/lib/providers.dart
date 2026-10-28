import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/auth_repository.dart';
import 'data/offline_peaks_repository.dart';
import 'data/offline_routes_repository.dart';
import 'data/peaks_repository.dart';
import 'data/pending_checkins_repository.dart';
import 'data/profile_repository.dart';
import 'data/routes_repository.dart';
import 'data/social_repository.dart';
import 'data/visits_repository.dart';
import 'models/elevation_bracket.dart';
import 'models/friend.dart';
import 'models/hiking_route.dart';
import 'models/peak.dart';
import 'models/pending_checkin.dart';
import 'models/profile.dart';
import 'models/stats.dart';
import 'models/visit.dart';
import 'services/checkin_service.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final peaksRepositoryProvider = Provider<PeaksRepository>((ref) {
  return PeaksRepository(ref.watch(supabaseClientProvider));
});

final routesRepositoryProvider = Provider<RoutesRepository>((ref) {
  return RoutesRepository(ref.watch(supabaseClientProvider));
});

final visitsRepositoryProvider = Provider<VisitsRepository>((ref) {
  return VisitsRepository(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SocialRepository(ref.watch(supabaseClientProvider));
});

final offlinePeaksRepositoryProvider = Provider<OfflinePeaksRepository>((ref) {
  return OfflinePeaksRepository(ref.watch(supabaseClientProvider));
});

final offlineRoutesRepositoryProvider = Provider<OfflineRoutesRepository>((ref) {
  return OfflineRoutesRepository(ref.watch(routesRepositoryProvider));
});

final pendingCheckInsRepositoryProvider = Provider<PendingCheckInsRepository>((ref) {
  return PendingCheckInsRepository();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

final checkInServiceProvider = Provider<CheckInService>((ref) {
  return CheckInService(
    ref.watch(supabaseClientProvider),
    ref.watch(pendingCheckInsRepositoryProvider),
    ref.watch(locationServiceProvider),
    ref.watch(connectivityServiceProvider),
  );
});

class OnlineStatusNotifier extends Notifier<bool> {
  @override
  bool build() {
    final service = ref.watch(connectivityServiceProvider);
    final sub = service.onStatusChange.listen((online) => state = online);
    ref.onDispose(sub.cancel);
    return service.isOnline;
  }
}

final onlineStatusProvider =
    NotifierProvider<OnlineStatusNotifier, bool>(OnlineStatusNotifier.new);

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

final sessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.maybeWhen(
    data: (state) => state.session,
    orElse: () => ref.watch(authRepositoryProvider).currentSession,
  );
});

final peaksProvider = FutureProvider<List<Peak>>((ref) async {
  final offlineRepo = ref.watch(offlinePeaksRepositoryProvider);
  if (!ref.watch(onlineStatusProvider)) {
    final offline = await offlineRepo.all();
    if (offline.isNotEmpty) return offline;
  }

  try {
    return await ref.watch(peaksRepositoryProvider).fetchAll().timeout(_fetchTimeout);
  } catch (_) {
    final offline = await offlineRepo.all();
    if (offline.isEmpty) rethrow;
    return offline;
  }
});

const _fetchTimeout = Duration(seconds: 12);

class SelectedMountainAreaNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? area) => state = area;
}

final selectedMountainAreaProvider =
    NotifierProvider<SelectedMountainAreaNotifier, String?>(SelectedMountainAreaNotifier.new);

class SelectedElevationBracketNotifier extends Notifier<ElevationBracket?> {
  @override
  ElevationBracket? build() => null;

  void set(ElevationBracket? bracket) => state = bracket;
}

final selectedElevationBracketProvider =
    NotifierProvider<SelectedElevationBracketNotifier, ElevationBracket?>(
  SelectedElevationBracketNotifier.new,
);

final visitedPeakIdsProvider = FutureProvider<Set<int>>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(visitsRepositoryProvider).fetchVisitedPeakIds();
});

final myVisitsProvider = FutureProvider<List<Visit>>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(visitsRepositoryProvider).fetchMyVisits();
});

final myStatsProvider = FutureProvider<Stats>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(visitsRepositoryProvider).fetchMyStats();
});

final myProfileProvider = FutureProvider<Profile>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(profileRepositoryProvider).fetchMine();
});

final friendsProvider = FutureProvider<List<Friend>>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(socialRepositoryProvider).fetchFriends();
});

final incomingRequestCountProvider = Provider<int>((ref) {
  final friends = ref.watch(friendsProvider).value ?? const <Friend>[];
  return friends.where((f) => f.status == FriendshipStatus.incoming).length;
});

final friendsFeedProvider = FutureProvider<List<FeedItem>>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(socialRepositoryProvider).fetchFeed();
});

final offlinePeaksProvider = FutureProvider<List<Peak>>((ref) async {
  return ref.watch(offlinePeaksRepositoryProvider).all();
});

final offlinePeakIdsProvider = FutureProvider<Set<int>>((ref) async {
  final peaks = await ref.watch(offlinePeaksProvider.future);
  return peaks.map((p) => p.id).toSet();
});

Future<void> setPeakDownloaded(WidgetRef ref, int peakId, bool downloaded) async {
  final peaksRepo = ref.read(offlinePeaksRepositoryProvider);
  final routesRepo = ref.read(offlineRoutesRepositoryProvider);
  try {
    if (downloaded) {
      await peaksRepo.download([peakId]);
      await routesRepo.downloadForPeak(peakId);
    } else {
      await peaksRepo.remove(peakId);
      await routesRepo.removeForPeak(peakId);
    }
  } finally {
    ref.invalidate(offlinePeaksProvider);
    ref.invalidate(routesForPeakProvider(peakId));
  }
}

class PendingCheckInsNotifier extends AsyncNotifier<List<PendingCheckIn>> {
  bool _syncing = false;

  @override
  Future<List<PendingCheckIn>> build() async {
    ref.watch(sessionProvider);

    ref.listen<bool>(onlineStatusProvider, (wasOnline, isOnline) {
      if (isOnline && wasOnline != true) unawaited(sync());
    });

    if (ref.read(onlineStatusProvider)) {
      await _flush();
    }

    return ref.read(pendingCheckInsRepositoryProvider).all();
  }

  Future<void> sync() async {
    await _flush();
    state = AsyncData(await ref.read(pendingCheckInsRepositoryProvider).all());
  }

  Future<void> _flush() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final synced = await ref.read(checkInServiceProvider).flushPending();
      if (synced > 0) {
        ref.invalidate(visitedPeakIdsProvider);
        ref.invalidate(myVisitsProvider);
        ref.invalidate(myStatsProvider);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> discard(String clientId) async {
    await ref.read(pendingCheckInsRepositoryProvider).remove(clientId);
    state = AsyncData(await ref.read(pendingCheckInsRepositoryProvider).all());
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(pendingCheckInsRepositoryProvider).all());
  }
}

final pendingCheckInsProvider =
    AsyncNotifierProvider<PendingCheckInsNotifier, List<PendingCheckIn>>(
  PendingCheckInsNotifier.new,
);

final pendingPeakIdsProvider = Provider<Set<int>>((ref) {
  final pending = ref.watch(pendingCheckInsProvider).value ?? const <PendingCheckIn>[];
  return pending.map((c) => c.peakId).toSet();
});

final routesForPeakProvider =
    FutureProvider.family<List<HikingRoute>, int>((ref, peakId) async {
  final offlineRepo = ref.watch(offlineRoutesRepositoryProvider);
  if (!ref.watch(onlineStatusProvider)) return offlineRepo.forPeak(peakId);

  try {
    final routes =
        await ref.watch(routesRepositoryProvider).fetchForPeak(peakId).timeout(_fetchTimeout);
    if ((await ref.read(offlinePeakIdsProvider.future)).contains(peakId)) {
      await offlineRepo.cacheForPeak(peakId, routes);
    }
    return routes;
  } catch (_) {
    return offlineRepo.forPeak(peakId);
  }
});

final peakByIdProvider = FutureProvider.family<Peak?, int>((ref, peakId) async {
  final offlineRepo = ref.watch(offlinePeaksRepositoryProvider);
  try {
    final peaks = await ref.watch(peaksProvider.future);
    for (final p in peaks) {
      if (p.id == peakId) return p;
    }
    if (!ref.watch(onlineStatusProvider)) return await offlineRepo.byId(peakId);
    return await ref.watch(peaksRepositoryProvider).fetchById(peakId).timeout(_fetchTimeout);
  } catch (_) {
    final offline = await offlineRepo.byId(peakId);
    if (offline == null) rethrow;
    return offline;
  }
});

class PeakFocusRequest {
  final int peakId;
  PeakFocusRequest(this.peakId);
}

class PeakFocusNotifier extends Notifier<PeakFocusRequest?> {
  @override
  PeakFocusRequest? build() => null;

  void focus(int peakId) => state = PeakFocusRequest(peakId);
}

final peakFocusProvider =
    NotifierProvider<PeakFocusNotifier, PeakFocusRequest?>(PeakFocusNotifier.new);

Future<void> rememberLocationEnabled(WidgetRef ref, bool enabled) async {
  if (ref.read(myProfileProvider).value?.locationEnabled == enabled) return;
  try {
    await ref.read(profileRepositoryProvider).update(locationEnabled: enabled);
    ref.invalidate(myProfileProvider);
  } catch (_) {
  }
}

void invalidateUserData(WidgetRef ref) {
  ref.invalidate(visitedPeakIdsProvider);
  ref.invalidate(myVisitsProvider);
  ref.invalidate(myStatsProvider);
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_prefsKey)) {
      case 'light':
        state = ThemeMode.light;
      case 'dark':
        state = ThemeMode.dark;
    }
  }

  Future<void> setDark(bool dark) async {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, dark ? 'dark' : 'light');
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
