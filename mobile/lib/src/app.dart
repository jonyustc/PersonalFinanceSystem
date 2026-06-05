import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/login_page.dart';
import 'features/home/home_shell.dart';
import 'state/app_controller.dart';
import 'theme/app_theme.dart';

class PersonalFinanceApp extends ConsumerWidget {
  const PersonalFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);

    final snapshot = state.asData?.value;

    return MaterialApp(
      title: 'Personal Finance',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: _themeMode(snapshot?.themeMode ?? 'system'),
      home: state.when(
        data: (snapshot) =>
            snapshot.isAuthenticated ? const HomeShell() : const LoginPage(),
        error: (error, _) => StartupError(message: error.toString()),
        loading: () => const StartupLoading(),
      ),
    );
  }

  ThemeMode _themeMode(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

class StartupLoading extends StatelessWidget {
  const StartupLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class StartupError extends StatelessWidget {
  const StartupError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error, size: 42),
              const SizedBox(height: 16),
              Text('Could not start the app',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}
