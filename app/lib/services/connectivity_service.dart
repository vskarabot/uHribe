import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class ConnectivityService {
  ConnectivityService() {
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        _retryDelay = _firstRetry;
        refresh();
      },
      onPause: () {
        _foreground = false;
        _timer?.cancel();
      },
    );
    _interfaceSub = Connectivity().onConnectivityChanged.listen((_) {
      _retryDelay = _firstRetry;
      refresh();
    });
    refresh();
  }

  static const _probeTimeout = Duration(seconds: 5);
  static const _firstRetry = Duration(seconds: 20);
  static const _maxRetry = Duration(minutes: 5);

  final _controller = StreamController<bool>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _interfaceSub;
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  Future<bool>? _inFlight;
  Duration _retryDelay = _firstRetry;
  bool _foreground = true;
  bool _noNetwork = false;

  bool _isOnline = true;

  bool get isOnline => _isOnline;

  Stream<bool> get onStatusChange => _controller.stream;

  Future<bool> refresh() {
    return _inFlight ??= _probe().whenComplete(() {
      _inFlight = null;
      _scheduleRetry();
    });
  }

  Future<bool> _probe() async {
    _noNetwork = false;

    final url = Config.supabaseUrl;
    if (url.isEmpty) {
      _noNetwork = true;
      _set(false);
      return false;
    }

    try {
      final interfaces = await Connectivity().checkConnectivity();
      if (interfaces.every((r) => r == ConnectivityResult.none)) {
        _noNetwork = true;
        _set(false);
        return false;
      }
    } catch (_) {
    }

    var reachable = false;
    try {
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
    if (online) _retryDelay = _firstRetry;
    if (_isOnline == online) return;
    _isOnline = online;
    if (!_controller.isClosed) _controller.add(online);
  }

  void _scheduleRetry() {
    _timer?.cancel();
    if (_isOnline || _noNetwork || !_foreground) return;
    _timer = Timer(_retryDelay, () => refresh());
    final next = _retryDelay * 2;
    _retryDelay = next > _maxRetry ? _maxRetry : next;
  }

  void dispose() {
    _timer?.cancel();
    _interfaceSub.cancel();
    _lifecycle.dispose();
    _controller.close();
  }
}
