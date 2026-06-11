import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Empirical verification for the router architecture (2026-06-11 paywall
/// incident review): does recreating the GoRouter instance (the consequence
/// of `routerProvider` ref.watch-ing auth state) reset navigation to
/// initialLocation, and does the stable-router + refreshListenable pattern
/// preserve the stack while still re-evaluating redirects?

// Simulated auth state — every assignment notifies (like AuthNotifier).
final _authTickProvider = StateProvider<int>((ref) => 0);
final _hasAccessProvider = StateProvider<bool>((ref) => true);

Widget _page(String label) => Scaffold(body: Text(label));

List<RouteBase> _routes() => [
      GoRoute(path: '/events', builder: (_, __) => _page('events')),
      GoRoute(path: '/events/detail', builder: (_, __) => _page('detail')),
      GoRoute(path: '/paywall', builder: (_, __) => _page('paywall')),
    ];

void main() {
  testWidgets(
      'OLD pattern: provider-watching router is recreated on state churn '
      'and navigation resets to initialLocation', (tester) async {
    final recreatedRouterProvider = Provider<GoRouter>((ref) {
      ref.watch(_authTickProvider); // the app's pattern pre-fix
      ref.watch(_hasAccessProvider);
      return GoRouter(initialLocation: '/events', routes: _routes());
    });

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return MaterialApp.router(routerConfig: ref.watch(recreatedRouterProvider));
        }),
      ),
    );

    capturedRef.read(recreatedRouterProvider).go('/events/detail');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    // Simulate a benign auth-state assignment (background verify / avatar
    // update / refreshEntitlement): same user, no redirect-relevant change.
    capturedRef.read(_authTickProvider.notifier).state++;
    await tester.pumpAndSettle();

    // Documents the defect: the user is yanked back to initialLocation.
    expect(find.text('events'), findsOneWidget,
        reason: 'router recreation resets navigation — this is the bug the '
            'stable-router pattern fixes; if this assertion ever FAILS, '
            'go_router behavior changed and the refactor can be revisited');
    expect(find.text('detail'), findsNothing);
  });

  testWidgets(
      'NEW pattern: stable router + refreshListenable preserves location on '
      'state churn AND still applies redirects when access flips',
      (tester) async {
    final stableRouterProvider = Provider<GoRouter>((ref) {
      final refresh = ValueNotifier(0);
      ref.listen<int>(_authTickProvider, (_, __) => refresh.value++);
      ref.listen<bool>(_hasAccessProvider, (_, __) => refresh.value++);
      ref.onDispose(refresh.dispose);
      return GoRouter(
        initialLocation: '/events',
        refreshListenable: refresh,
        redirect: (context, state) {
          final hasAccess = ref.read(_hasAccessProvider);
          final loc = state.matchedLocation;
          if (!hasAccess && loc != '/paywall') return '/paywall';
          if (hasAccess && loc == '/paywall') return '/events';
          return null;
        },
        routes: _routes(),
      );
    });

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return MaterialApp.router(routerConfig: ref.watch(stableRouterProvider));
        }),
      ),
    );

    capturedRef.read(stableRouterProvider).go('/events/detail');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    // Benign churn: location must be preserved.
    capturedRef.read(_authTickProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget,
        reason: 'stable router must NOT reset navigation on auth churn');

    // Access lost: redirect must engage the paywall via refreshListenable.
    capturedRef.read(_hasAccessProvider.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.text('paywall'), findsOneWidget,
        reason: 'refreshListenable must re-run redirect when access changes');

    // Access regained while on the paywall: released into the app.
    capturedRef.read(_hasAccessProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.text('events'), findsOneWidget,
        reason: 'regaining access must release the user from /paywall');
  });
}
