import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Tracks whether the app can actually reach Supabase, continuously.
///
/// Deliberately not a check-on-open: the whole point is a phone that loses
/// signal on the way up and finds it again on the way down, hours later,
/// without the user ever reopening the app.
///
/// Three things drive a re-check, because none of them is sufficient alone:
///
///  * `connectivity_plus` events — instant, but they report the *interface*
///    changing, not reachability. A phone can hold one bar of GPRS on a ridge
///    and carry no usable data at all.
///  * App resume — catches the case where the OS suspended us through the
///    entire transition.
///  * A timer — the fallback for a signal that comes back while the app sits
///    in the foreground with no interface change to announce it. Fast while
///    offline (that's when the answer is about to change and the user is
///    waiting on it), slow while online (just a sanity check).
class ConnectivityService {
  ConnectivityService() {
    _lifecycle = AppLifecycleListener(onResume: () => refresh());
    _interfaceSub = Connectivity().onConnectivityChanged.listen((results) {
      // No interface at all is conclusive — skip the probe and its timeout.
      if (results.every((r) => r == ConnectivityResult.none)) {
        _set(false);
        _restartTimer();
      } else {
        refresh();
      }
    });
    refresh();
    _restartTimer();
  }

  static const _probeTimeout = Duration(seconds: 5);
  static const _pollWhileOffline = Duration(seconds: 20);
  static const _pollWhileOnline = Duration(minutes: 3);

  final _controller = StreamController<bool>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _interfaceSub;
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  Future<bool>? _inFlight;

  // Assumed online until proven otherwise, so a first action isn't needlessly
  // queued while the opening probe is still in the air.
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  /// Emits only on change, so listeners aren't woken by every poll.
  Stream<bool> get onStatusChange => _controller.stream;

  /// Probes now and returns the result. Concurrent callers share one probe
  /// rather than each opening their own socket.
  Future<bool> refresh() {
    return _inFlight ??= _probe().whenComplete(() => _inFlight = null);
  }

  Future<bool> _probe() async {
    final url = Config.supabaseUrl;
    if (url.isEmpty) {
      _set(false);
      return false;
    }

    // Ask the OS before opening a socket. In airplane mode the probe would
    // otherwise spend its full timeout finding out what the radio already
    // knows — and that wait is the whole startup delay on a mountain, with
    // every screen holding a spinner until it ends.
    try {
      final interfaces = await Connectivity().checkConnectivity();
      if (interfaces.every((r) => r == ConnectivityResult.none)) {
        _set(false);
        return false;
      }
    } catch (_) {
      // Couldn't ask — fall through and let the probe decide.
    }

    var reachable = false;
    try {
      // GoTrue's health endpoint is the cheapest thing Supabase will answer.
      // Any HTTP response means the round trip worked, so the status code
      // itself doesn't matter — only that something came back.
      await http.get(
        Uri.parse('$url/auth/v1/health'),
        headers: {'apikey': Config.supabasePublishableKey},
      ).timeout(_probeTimeout);
      reachable = true;
    } catch (_) {
      reachable = false;
    }

    _set(reachable);
    return reachable;
  }

  void _set(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    if (!_controller.isClosed) _controller.add(online);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      _isOnline ? _pollWhileOnline : _pollWhileOffline,
      (_) => refresh(),
    );
  }

  void dispose() {
    _timer?.cancel();
    _interfaceSub.cancel();
    _lifecycle.dispose();
    _controller.close();
  }
}
