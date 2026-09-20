import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'ui/login_page.dart';
import 'ui/shell.dart';

class App extends StatelessWidget {
  const App({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Emby Player',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        scrollBehavior: const AppScrollBehavior(),
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: app.emby == null
          ? const LoginPage(key: ValueKey('login'))
          : const Shell(key: ValueKey('shell')),
    );
  }
}
