import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/strings.dart';
import '../../providers.dart';
import '../../theme.dart';
import 'auth_switch_link.dart';
import 'password_field.dart';

List<(String, bool)> _passwordRules(String value) => [
      (Strings.passwordRuleLength, value.length >= 8),
      (
        Strings.passwordRuleCase,
        value.contains(RegExp(r'[a-z]')) && value.contains(RegExp(r'[A-Z]')),
      ),
      (Strings.passwordRuleDigit, value.contains(RegExp(r'\d'))),
      (
        Strings.passwordRuleSymbol,
        value.contains(RegExp(r'''[!@#$%^&*()_+\-=\[\]{};'\\:"|<>?,./`~]''')),
      ),
    ];

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _awaitingConfirmation = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
    _confirmController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _passwordReady =>
      _passwordRules(_passwordController.text).every((rule) => rule.$2) &&
      _confirmController.text == _passwordController.text;

  Future<void> _submit() async {
    if (!_passwordReady) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final signedIn = await ref.read(authRepositoryProvider).signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
          );
      if (!signedIn && mounted) setState(() => _awaitingConfirmation = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = Strings.registerError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _awaitingConfirmation
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.mark_email_read_outlined, size: 64, color: colorScheme.primary),
                      const SizedBox(height: 24),
                      const Text(Strings.registerConfirmEmail, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => context.go('/login'),
                        child: const Text(Strings.loginButton),
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.terrain_rounded, size: 64, color: colorScheme.primary),
                        const SizedBox(height: 16),
                        const Text(
                          Strings.registerTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 40),
                        ShadowedField(
                          child: TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(labelText: Strings.displayName),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty) ? '—' : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ShadowedField(
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(labelText: Strings.email),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty) ? '—' : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _passwordController,
                          label: Strings.password,
                          autofillHints: const [AutofillHints.newPassword],
                        ),
                        if (_passwordController.text.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final (label, met) in _passwordRules(_passwordController.text))
                            _PasswordRule(label: label, met: met),
                        ],
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _confirmController,
                          label: Strings.confirmPassword,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: colorScheme.error)),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading || !_passwordReady ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(Strings.registerButton),
                        ),
                        const SizedBox(height: 8),
                        AuthSwitchLink(
                          prompt: Strings.haveAccount,
                          action: Strings.haveAccountAction,
                          onPressed: _loading ? null : () => context.go('/login'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PasswordRule extends StatelessWidget {
  const _PasswordRule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = met ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Icon(met ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
