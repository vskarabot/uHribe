import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class ConnectivityService {
  ConnectivityService() {
    _lifecycle = AppLifecycleListener(onResume: () => refresh());
    _interfaceSub = Connectivity().onConnectivityChanged.listen((results) {
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

  bool _isOnline = true;

  bool get isOnline => _isOnline;

  Stream<bool> get onStatusChange => _controller.stream;

  Future<bool> refresh() {
    return _inFlight ??= _probe().whenComplete(() => _inFlight = null);
  }

  Future<bool> _probe() async {
    final url = Config.supabaseUrl;
    if (url.isEmpty) {
      _set(false);
      return false;
    }

    try {
      final interfaces = await Connectivity().checkConnectivity();
      if (interfaces.every((r) => r == ConnectivityResult.none)) {
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
