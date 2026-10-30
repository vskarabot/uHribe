import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/onboarding/location_permission_screen.dart';
import 'features/routes/route_detail_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/social/friends_screen.dart';
import 'models/hiking_route.dart';
import 'providers.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
    ref.listen(locationPromptSeenProvider, (_, _) => notifyListeners());
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
      final loggingIn =
          state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (!loggedIn) return loggingIn ? null : '/login';

      final onPrompt = state.matchedLocation == '/location';
      if (!ref.read(locationPromptSeenProvider)) return onPrompt ? null : '/location';
      if (loggingIn || onPrompt) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/location',
        builder: (context, state) => const LocationPermissionScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/friends',
        builder: (context, state) => const FriendsScreen(),
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
