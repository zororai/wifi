import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../features/scanner/scanner_screen.dart';

/// Route paths. Further routes are added by the phase that implements them.
abstract final class AppRoutes {
  static const dashboard = '/';
  static const scanner = '/scanner';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      GoRoute(
        path: AppRoutes.dashboard,
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
        routes: [
          GoRoute(
            path: 'scanner',
            name: 'scanner',
            builder: (context, state) => const ScannerScreen(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
