import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos.dart';
import '../../core/theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _err;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final supa = ref.read(supaServiceProvider);
      if (_register) {
        await supa.signUp(
            _email.text.trim(), _pass.text.trim(), _name.text.trim());
      } else {
        await supa.signIn(_email.text.trim(), _pass.text.trim());
      }
      // AuthGate reacts to the auth stream automatically.
    } catch (e) {
      setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 56, color: AppTheme.primary),
                const SizedBox(height: 16),
                Text('Devniques Finance',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                    _register
                        ? 'New account — starts with view-only access'
                        : 'Sign in to continue',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.muted),
                    textAlign: TextAlign.center),
                const SizedBox(height: 28),
                if (_register)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(labelText: 'Full name'),
                    ),
                  ),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _submit(),
                ),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_err!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : Text(_register ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _register = !_register),
                  child: Text(_register
                      ? 'Already have an account? Sign in'
                      : 'New here? Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
