import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cliques/presentation/cliques_list_screen.dart';
import '../../features/cliques/presentation/create_clique_screen.dart';
import '../../features/cliques/presentation/clique_detail_screen.dart';
import '../../features/cliques/presentation/invite_screen.dart';
import '../../features/cliques/presentation/join_clique_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/events/presentation/events_home_screen.dart';
import '../../features/events/presentation/events_list_screen.dart';
import '../../features/events/presentation/create_event_screen.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/photos/presentation/camera_capture_screen.dart';
import '../../features/photos/presentation/photo_detail_screen.dart';
import '../../features/videos/presentation/video_capture_screen.dart';
import '../../features/videos/presentation/video_upload_screen.dart';
import '../../features/videos/presentation/video_player_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/dm/presentation/dm_thread_list_screen.dart';
import '../../features/dm/presentation/dm_chat_screen.dart';
import '../../features/dm/presentation/dm_member_picker.dart';
import '../../app/shell_screen.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/auth_providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/events',
    redirect: (context, state) {
      final isAuthenticated = authState is AuthAuthenticated;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isAuthenticated && !isLoginRoute) {
        final redirect = state.matchedLocation;
        if (redirect != '/events') {
          return '/login?redirect=$redirect';
        }
        return '/login';
      }
      if (isAuthenticated && isLoginRoute) {
        final redirect = state.uri.queryParameters['redirect'];
        return redirect ?? '/events';
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
        builder: (context, state) => JoinCliqueScreen(
          inviteCode: state.pathParameters['inviteCode']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ShellScreen(
          navigationShell: navigationShell,
        ),
        branches: [
          // Tab 1: Home (dashboard)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => CreateEventScreen(
                      cliqueId: state.uri.queryParameters['cliqueId'],
                    ),
                  ),
                  GoRoute(
                    path: 'all',
                    builder: (context, state) => const EventsHomeScreen(),
                  ),
                ],
              ),
            ],
          ),
          // Tab 2: Cliques
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cliques',
                builder: (context, state) => const CliquesListScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateCliqueScreen(),
                  ),
                  GoRoute(
                    path: ':cliqueId',
                    builder: (context, state) => CliqueDetailScreen(
                      cliqueId: state.pathParameters['cliqueId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'invite',
                        builder: (context, state) => InviteScreen(
                          cliqueId: state.pathParameters['cliqueId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'events',
                        builder: (context, state) => EventsListScreen(
                          cliqueId: state.pathParameters['cliqueId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Tab 3: Notifications
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          // Tab 4: Profile
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
      // Top-level routes (outside shell for clean back-navigation)
      GoRoute(
        path: '/view-clique/:cliqueId',
        builder: (context, state) => CliqueDetailScreen(
          cliqueId: state.pathParameters['cliqueId']!,
        ),
      ),
      GoRoute(
        path: '/invite-to-clique/:cliqueId',
        builder: (context, state) => InviteScreen(
          cliqueId: state.pathParameters['cliqueId']!,
        ),
      ),
      // Event detail routes (outside shell for full-screen experience)
      GoRoute(
        path: '/events/:eventId',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>?;
          return EventDetailScreen(
            eventId: state.pathParameters['eventId']!,
            promptInviteCliqueId: extra?['cliqueId'],
            promptInviteCliqueName: extra?['cliqueName'],
          );
        },
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
          GoRoute(
            path: 'video-capture',
            builder: (context, state) => VideoCaptureScreen(
              eventId: state.pathParameters['eventId']!,
            ),
          ),
          GoRoute(
            path: 'videos/upload',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>;
              return VideoUploadScreen(
                eventId: state.pathParameters['eventId']!,
                videoFile: extra['file'] as File,
                durationSeconds: extra['durationSeconds'] as int,
              );
            },
          ),
          GoRoute(
            path: 'videos/:videoId',
            builder: (context, state) => VideoPlayerScreen(
              videoId: state.pathParameters['videoId']!,
            ),
          ),
          GoRoute(
            path: 'dm-threads',
            builder: (context, state) => DmThreadListScreen(
              eventId: state.pathParameters['eventId']!,
            ),
          ),
          GoRoute(
            path: 'dm/new',
            builder: (context, state) => DmMemberPickerScreen(
              eventId: state.pathParameters['eventId']!,
              cliqueId: state.uri.queryParameters['cliqueId'] ?? '',
            ),
          ),
          GoRoute(
            path: 'dm/:threadId',
            builder: (context, state) => DmChatScreen(
              threadId: state.pathParameters['threadId']!,
              eventId: state.pathParameters['eventId']!,
            ),
          ),
        ],
      ),
    ],
  );
});
