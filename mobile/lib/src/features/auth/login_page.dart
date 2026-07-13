import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _googleBusy = false;
  bool _restoring = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authNotice =
        ref.watch(appControllerProvider).asData?.value.authNotice;
    final googleConfigured = ref.read(googleAuthServiceProvider).isConfigured;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colorful gradient hero — sets the friendly, vibrant tone.
            Container(
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.paddingOf(context).top + 56,
                24,
                40,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.secondary, scheme.tertiary],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(36),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: scheme.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Welcome back',
                    style: textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Track spending, budgets and investments — all in one place.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (authNotice != null) ...[
                          _AuthNotice(message: authNotice),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) =>
                              value == null || !value.contains('@')
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(_busy ? 'Signing in…' : 'Sign in'),
                        ),
                        if (googleConfigured) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'or continue with',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _googleBusy ? null : _googleSubmit,
                            icon: _googleBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.account_circle_outlined),
                            label: const Text('Continue with Google'),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'no connection?',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _restoring ? null : _restoreOffline,
                          icon: _restoring
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.restore_outlined),
                          label: Text(
                            _restoring
                                ? 'Opening backup…'
                                : 'Use a backup file (offline)',
                          ),
                        ),
                        Text(
                          'Opens the app from a backup with no sign-in. '
                          'Sign in later to sync.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .login(_email.text.trim(), _password.text);
      _dismissIfModal();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Login failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restores a backup and enters the app offline (no server needed). On the
  /// root login screen the app switches to the home shell automatically once a
  /// session exists; when shown as a re-login sheet, close it.
  Future<void> _restoreOffline() async {
    setState(() => _restoring = true);
    try {
      final ok = await ref
          .read(appControllerProvider.notifier)
          .restoreBackupOffline();
      if (ok) _dismissIfModal();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open backup: $error')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// When this page was pushed as a modal (e.g. "Sign in to sync" from offline
  /// mode), pop it on success. As the root page it can't pop — the app rebuilds
  /// to the home shell from the new session instead.
  void _dismissIfModal() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _googleSubmit() async {
    setState(() => _googleBusy = true);
    try {
      await ref.read(appControllerProvider.notifier).loginWithGoogle();
      _dismissIfModal();
    } catch (error) {
      if (!mounted) return;
      // The user dismissing the Google sheet is not an error worth surfacing.
      if (error.toString().toLowerCase().contains('cancel')) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_googleErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  // Translate the common Google sign-in failure modes into actionable
  // messages instead of a generic "sign-in failed".
  String _googleErrorMessage(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 503) {
        return 'Google login is not enabled on the server '
            '(GOOGLE_CLIENT_IDS is not configured).';
      }
      if (status == 401) {
        return 'The server rejected the Google credential — the backend '
            'GOOGLE_CLIENT_IDS must include this app\'s web client ID.';
      }
      if (status != null) {
        return 'Google sign-in failed: HTTP $status';
      }
      return 'Google sign-in failed: could not reach the server.';
    }
    final text = error.toString();
    if (text.contains('10:') || text.toUpperCase().contains('DEVELOPER_ERROR')) {
      return 'Google sign-in is misconfigured for this build — register the '
          'app\'s package name and signing SHA-1 as an Android OAuth client '
          'in Google Cloud Console.';
    }
    return 'Google sign-in failed: $text';
  }
}

class _AuthNotice extends StatelessWidget {
  const _AuthNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
