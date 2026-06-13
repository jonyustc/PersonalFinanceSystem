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
      themeMode: _themeMode(snapshot?.themeMode ?? 'light'),
      builder: (context, child) {
        // Slightly smaller, denser typography overall, and cap the system font
        // scale so long labels (e.g. bottom-nav "Transactions") never overflow.
        final media = MediaQuery.of(context);
        final scaled = (media.textScaler.scale(1) * 0.94).clamp(0.85, 1.05);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scaled)),
          child: child ?? const SizedBox.shrink(),
        );
      },
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: scheme.primary,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Personal Finance',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
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
