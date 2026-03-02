import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final authNotifier = ref.read(authNotifierProvider.notifier);
      if (_isSignUp) {
        await authNotifier.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await authNotifier.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      }
    } catch (_) {
      // Error is already handled via ref.listen → SnackBar
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AsyncLoading;

    ref.listen<AsyncValue<void>>(authNotifierProvider, (_, state) {
      if (state is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${state.error}')),
        );
      }
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warehouse_rounded,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'PostHarvest Monitor',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'IoT Warehouse Monitoring System',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      v != null && v.contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) =>
                      v != null && v.length >= 6 ? null : 'Min 6 characters',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign In'
                        : "Don't have an account? Sign Up",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
