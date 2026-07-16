import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/presentation/capture_page.dart';
import '../features/coach/presentation/coach_page.dart';
import '../features/diary/presentation/diary_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/me/presentation/me_page.dart';

/// Five tabs per docs/DESIGN.md: Home · Diary · [+] Capture · Coach · Me.
/// Capture becomes a modal sheet in M3; it is a plain tab until then.
final router = GoRouter(
  initialLocation: '/home',
  routes: [
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
          GoRoute(path: '/capture', builder: (_, _) => const CapturePage()),
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
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.book_outlined), label: 'Diary'),
          NavigationDestination(icon: Icon(Icons.add_circle, size: 36), label: 'Log'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Coach'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
        ],
      ),
    );
  }
}
