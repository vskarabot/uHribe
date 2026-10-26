import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/login_screen.dart';
import 'features/routes/route_detail_screen.dart';
import 'features/shell/home_shell.dart';
import 'models/hiking_route.dart';
import 'providers.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider) != null;
      final loggingIn = state.matchedLocation == '/login';

      if (!loggedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/route',
        builder: (context, state) {
          return RouteDetailScreen(route: state.extra as HikingRoute);
        },
      ),
    ],
  );
});
