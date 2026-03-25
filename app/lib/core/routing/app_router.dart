import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/circles/presentation/circles_list_screen.dart';
import '../../features/circles/presentation/create_circle_screen.dart';
import '../../features/circles/presentation/circle_detail_screen.dart';
import '../../features/circles/presentation/invite_screen.dart';
import '../../features/circles/presentation/join_circle_screen.dart';
import '../../features/events/presentation/events_list_screen.dart';
import '../../features/events/presentation/create_event_screen.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/photos/presentation/camera_capture_screen.dart';
import '../../features/photos/presentation/photo_detail_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../app/shell_screen.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/auth_providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/circles',
    redirect: (context, state) {
      final isAuthenticated = authState is AuthAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login';
      final isInviteRoute = state.matchedLocation.startsWith('/invite/');

      if (!isAuthenticated && !isLoginRoute && !isInviteRoute) {
        return '/login';
      }
      if (isAuthenticated && isLoginRoute) {
        return '/circles';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/invite/:inviteCode',
        builder: (context, state) => JoinCircleScreen(
          inviteCode: state.pathParameters['inviteCode']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ShellScreen(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/circles',
                builder: (context, state) => const CirclesListScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateCircleScreen(),
                  ),
                  GoRoute(
                    path: ':circleId',
                    builder: (context, state) => CircleDetailScreen(
                      circleId: state.pathParameters['circleId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'invite',
                        builder: (context, state) => InviteScreen(
                          circleId: state.pathParameters['circleId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'events',
                        builder: (context, state) => EventsListScreen(
                          circleId: state.pathParameters['circleId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'create',
                            builder: (context, state) => CreateEventScreen(
                              circleId: state.pathParameters['circleId']!,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/events/:eventId',
        builder: (context, state) => EventDetailScreen(
          eventId: state.pathParameters['eventId']!,
        ),
        routes: [
          GoRoute(
            path: 'capture',
            builder: (context, state) => CameraCaptureScreen(
              eventId: state.pathParameters['eventId']!,
            ),
          ),
          GoRoute(
            path: 'photos/:photoId',
            builder: (context, state) => PhotoDetailScreen(
              photoId: state.pathParameters['photoId']!,
            ),
          ),
        ],
      ),
    ],
  );
});
