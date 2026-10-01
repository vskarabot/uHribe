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
import 'data/visits_repository.dart';
import 'models/elevation_bracket.dart';
import 'models/hiking_route.dart';
import 'models/peak.dart';
import 'models/pending_checkin.dart';
import 'models/profile.dart';
import 'models/stats.dart';
import 'models/visit.dart';
import 'services/checkin_service.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';

// ---- Infrastructure ----

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

/// Long-lived: it keeps a connectivity subscription, a lifecycle listener and
/// a poll timer running for the whole session, which is the point — the app
/// has to notice signal coming back on the descent without being reopened.
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

// ---- Connectivity ----

/// Whether the app can currently reach Supabase, as a plain bool that
/// rebuilds its watchers on every change.
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

// ---- Auth ----

/// Emits whenever Supabase's auth state changes (sign-in, sign-out, token
/// refresh). The router watches this to redirect between /login and the app.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

/// The current session, kept in sync with [authStateChangesProvider] but
/// also readable synchronously (falls back to the client's current session
/// before the stream has emitted).
final sessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.maybeWhen(
    data: (state) => state.session,
    orElse: () => ref.watch(authRepositoryProvider).currentSession,
  );
});

// ---- Data ----

/// Every peak, or — with no network — the ones the user downloaded.
///
/// Offline the device's copy is read straight away rather than after a
/// request that was never going to answer: a Supabase call on a phone with no
/// signal doesn't fail fast, it hangs until its socket gives up, and the list
/// spent that whole time on a spinner before showing what it had all along.
final peaksProvider = FutureProvider<List<Peak>>((ref) async {
  final offlineRepo = ref.watch(offlinePeaksRepositoryProvider);
  // Watched, not read, so the list refills itself the moment signal returns.
  if (!ref.watch(onlineStatusProvider)) {
    final offline = await offlineRepo.all();
    if (offline.isNotEmpty) return offline;
  }

  try {
    return await ref.watch(peaksRepositoryProvider).fetchAll().timeout(_fetchTimeout);
  } catch (_) {
    // Either connectivity was wrong or nothing was downloaded — without this
    // the peak list and map are empty exactly where the check-in matters.
    final offline = await offlineRepo.all();
    if (offline.isEmpty) rethrow;
    return offline;
  }
});

/// The cap on any fetch that has an on-device fallback. Long enough for a
/// slow valley connection, short enough that the screen stops promising
/// something it isn't going to get.
const _fetchTimeout = Duration(seconds: 12);

/// The mountain area currently selected for filtering, shared between the
/// peaks list and map screens. `null` means no filter (show everything).
class SelectedMountainAreaNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? area) => state = area;
}

final selectedMountainAreaProvider =
    NotifierProvider<SelectedMountainAreaNotifier, String?>(SelectedMountainAreaNotifier.new);

/// The elevation bracket currently selected for filtering peaks.
/// `null` means no filter (show everything).
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
  // Re-fetch whenever the session changes (e.g. after login/logout).
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

// ---- Offline ----

/// Peaks the user downloaded for a hike, read from the device.
final offlinePeaksProvider = FutureProvider<List<Peak>>((ref) async {
  return ref.watch(offlinePeaksRepositoryProvider).all();
});

/// Just the ids, for the download toggle on a peak.
final offlinePeakIdsProvider = FutureProvider<Set<int>>((ref) async {
  final peaks = await ref.watch(offlinePeaksProvider.future);
  return peaks.map((p) => p.id).toSet();
});

/// Downloads [peakId] for offline use — the peak *and* its routes — or
/// removes both again.
Future<void> setPeakDownloaded(WidgetRef ref, int peakId, bool downloaded) async {
  final peaksRepo = ref.read(offlinePeaksRepositoryProvider);
  final routesRepo = ref.read(offlineRoutesRepositoryProvider);
  try {
    if (downloaded) {
      // Peak first: it's what the check-in needs, so if only one of the two
      // makes it onto the device, that's the one worth having.
      await peaksRepo.download([peakId]);
      await routesRepo.downloadForPeak(peakId);
    } else {
      await peaksRepo.remove(peakId);
      await routesRepo.removeForPeak(peakId);
    }
  } finally {
    // In the `finally` so a half-finished download still shows what did land
    // rather than a toggle that disagrees with the device.
    ref.invalidate(offlinePeaksProvider);
    ref.invalidate(routesForPeakProvider(peakId));
  }
}

/// The queue of check-ins waiting for a network, plus the syncing of it.
///
/// Syncs itself on three occasions: when the app starts, whenever
/// connectivity comes back, and whenever the user asks. The second is the one
/// that matters — it's what turns "checked in on the summit at 11:40" into a
/// verified visit hours later, on the walk down, with nobody touching the
/// phone.
class PendingCheckInsNotifier extends AsyncNotifier<List<PendingCheckIn>> {
  bool _syncing = false;

  @override
  Future<List<PendingCheckIn>> build() async {
    ref.watch(sessionProvider);

    // Registered before the first await, while the notifier is still building.
    ref.listen<bool>(onlineStatusProvider, (wasOnline, isOnline) {
      if (isOnline && wasOnline != true) unawaited(sync());
    });

    // Catch up on anything left from a previous session *inside* build rather
    // than deferring it, so the result is already settled when this returns
    // and nothing writes `state` before the notifier finishes building.
    if (ref.read(onlineStatusProvider)) {
      await _flush();
    }

    return ref.read(pendingCheckInsRepositoryProvider).all();
  }

  /// Flushes the queue and republishes it. Safe to call at any time —
  /// overlapping calls collapse into the one already running.
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

  /// Drops a queued check-in the server refused, once the user has decided
  /// what to do about it.
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

/// Peak ids with a check-in still queued, so the UI can show them as climbed
/// even before the server has heard about it.
final pendingPeakIdsProvider = Provider<Set<int>>((ref) {
  final pending = ref.watch(pendingCheckInsProvider).value ?? const <PendingCheckIn>[];
  return pending.map((c) => c.peakId).toSet();
});

/// Routes for a single peak, parameterized by peak id.
///
/// Offline this reads the device's copy instead of waiting on a request that
/// will never answer — a Supabase call on a phone with no signal doesn't fail
/// fast, it sits there, which left the peak sheet's routes section spinning
/// for the whole hike. Watching [onlineStatusProvider] also means the section
/// fills itself in the moment signal comes back.
final routesForPeakProvider =
    FutureProvider.family<List<HikingRoute>, int>((ref, peakId) async {
  final offlineRepo = ref.watch(offlineRoutesRepositoryProvider);
  if (!ref.watch(onlineStatusProvider)) return offlineRepo.forPeak(peakId);

  try {
    final routes =
        await ref.watch(routesRepositoryProvider).fetchForPeak(peakId).timeout(_fetchTimeout);
    // Refresh the cache for free: a peak downloaded before routes were cached
    // at all, or one whose paths changed upstream, catches up here rather
    // than needing the user to re-download it.
    if ((await ref.read(offlinePeakIdsProvider.future)).contains(peakId)) {
      await offlineRepo.cacheForPeak(peakId, routes);
    }
    return routes;
  } catch (_) {
    // Connectivity said online but the request didn't land — the cache is
    // still a better answer than an error, and an empty one reads as
    // "nothing downloaded" in the sheet.
    return offlineRepo.forPeak(peakId);
  }
});

/// A single peak by id — looks it up in the already-cached [peaksProvider]
/// list first, falling back to a direct fetch (e.g. for a deep link) and,
/// failing that, to the device's downloaded copy. The last step is what keeps
/// the peak sheet — and its check-in button — working on a summit with no
/// signal.
final peakByIdProvider = FutureProvider.family<Peak?, int>((ref, peakId) async {
  final offlineRepo = ref.watch(offlinePeaksRepositoryProvider);
  try {
    final peaks = await ref.watch(peaksProvider.future);
    for (final p in peaks) {
      if (p.id == peakId) return p;
    }
    // A peak the list doesn't carry (a deep link, or an offline list holding
    // only the downloads) is worth one request — but only where a request can
    // land at all.
    if (!ref.watch(onlineStatusProvider)) return await offlineRepo.byId(peakId);
    return await ref.watch(peaksRepositoryProvider).fetchById(peakId).timeout(_fetchTimeout);
  } catch (_) {
    final offline = await offlineRepo.byId(peakId);
    if (offline == null) rethrow;
    return offline;
  }
});

/// A request to center the map on [peakId] and show its details, e.g. from
/// the peak list. Wrapped in a fresh instance each time (rather than just
/// the id) so re-selecting the same peak still triggers a new fly-to.
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

/// Persists the user's "show my location on the map" choice on their profile,
/// so a later app start can show the location puck straight away instead of
/// prompting again. Shared by the map's locate button and the profile toggle.
///
/// Best-effort: the OS permission is what actually gates the puck, so a
/// preference that fails to save isn't worth interrupting the user for.
Future<void> rememberLocationEnabled(WidgetRef ref, bool enabled) async {
  if (ref.read(myProfileProvider).value?.locationEnabled == enabled) return;
  try {
    await ref.read(profileRepositoryProvider).update(locationEnabled: enabled);
    ref.invalidate(myProfileProvider);
  } catch (_) {
    // Ignored on purpose — see above.
  }
}

/// Call after adding/removing a visit or editing the profile to refresh
/// everything that depends on it.
void invalidateUserData(WidgetRef ref) {
  ref.invalidate(visitedPeakIdsProvider);
  ref.invalidate(myVisitsProvider);
  ref.invalidate(myStatsProvider);
}

// ---- Theme ----

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
