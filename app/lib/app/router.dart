import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/app_providers.dart';
import '../features/capture/presentation/quick_add_page.dart';
import '../features/coach/presentation/coach_page.dart';
import '../features/diary/presentation/diary_page.dart';
import '../features/home/domain/day_totals.dart';
import '../features/home/presentation/home_page.dart';
import '../features/me/presentation/me_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/settings/presentation/data_sources_page.dart';

/// Router with an onboarding gate:
///   profile loading  -> /splash (never flash onboarding at a returning user)
///   not onboarded    -> /onboarding
///   onboarded        -> the 5-tab shell
/// The redirect reads profileProvider; refreshListenable re-runs it when the
/// profile changes (e.g. onboarding finishes and writes the record).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: _ProfileRefresh(ref),
    redirect: (context, state) {
      final async = ref.read(profileProvider);
      final loc = state.matchedLocation;
      if (async.isLoading) return loc == '/splash' ? null : '/splash';
      final onboarded = async.value?.onboardingComplete ?? false;
      if (!onboarded) return loc == '/onboarding' ? null : '/onboarding';
      // Onboarded: never sit on the gate routes.
      if (loc == '/onboarding' || loc == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      GoRoute(
          path: '/data-sources',
          builder: (_, _) => const DataSourcesPage()),
      GoRoute(
        path: '/add',
        builder: (context, state) {
          final mealKey = state.uri.queryParameters['meal'];
          final meal = Meal.values.where((m) => m.key == mealKey).firstOrNull;
          return QuickAddPage(initialMeal: meal);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/diary', builder: (_, _) => const DiaryPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/capture', builder: (_, _) => const QuickAddPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/coach', builder: (_, _) => const CoachPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/me', builder: (_, _) => const MePage()),
          ]),
        ],
      ),
    ],
  );
});

/// Bridges the Riverpod profile stream to go_router's Listenable-based refresh.
class _ProfileRefresh extends ChangeNotifier {
  _ProfileRefresh(Ref ref) {
    ref.listen(profileProvider, (_, _) => notifyListeners());
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        // Keys are the stable, locale-independent handles (CLAUDE.md a11y
        // convention) — tests and UI drivers must never find by visible label,
        // which breaks the day Hindi localization lands.
        destinations: const [
          NavigationDestination(key: Key('nav-home'), icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(key: Key('nav-diary'), icon: Icon(Icons.book_outlined), label: 'Diary'),
          NavigationDestination(key: Key('nav-capture'), icon: Icon(Icons.add_circle, size: 36), label: 'Log'),
          NavigationDestination(key: Key('nav-coach'), icon: Icon(Icons.chat_bubble_outline), label: 'Coach'),
          NavigationDestination(key: Key('nav-me'), icon: Icon(Icons.person_outline), label: 'Me'),
        ],
      ),
    );
  }
}
