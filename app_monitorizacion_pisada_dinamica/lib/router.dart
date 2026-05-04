// lib/router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/widgets/app_scaffold.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/debug/presentation/screens/debug_screen.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'features/ota/presentation/screens/ota_screen.dart';

final router = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (_, __) =>
          const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: '/debug',
          pageBuilder: (_, __) =>
          const NoTransitionPage(child: DebugScreen()),
        ),
      ],
    ),
    // Pantallas modales — fuera del shell (sin bottom nav)
    GoRoute(
      path: '/profile',
      builder: (_, __) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/ota',
      builder: (_, __) => const OtaScreen(),
    ),
  ],
);