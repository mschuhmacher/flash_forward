import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/presentation/screens/signup_screen.dart';
import 'package:flash_forward/presentation/screens/home_screen.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

class LoginScreen extends StatefulWidget {
  final bool showEmailConfirmationMessage;

  const LoginScreen({super.key, this.showEmailConfirmationMessage = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return email.isNotEmpty && email.contains('@') && email.contains('.');
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();

    if (_isValidEmail(email)) {
      // Email is valid, send reset email directly
      await _sendPasswordReset(email);
    } else {
      // Show dialog to enter email
      final enteredEmail = await _showEmailDialog();
      if (enteredEmail != null && _isValidEmail(enteredEmail)) {
        await _sendPasswordReset(enteredEmail);
      }
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    await authProvider.resetPassword(email);

    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text('Password reset email sent to $email'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<String?> _showEmailDialog() async {
    final dialogEmailController = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Reset Password', style: context.h3),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter your email address to receive a password reset link.',
                    style: context.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dialogEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final email = dialogEmailController.text.trim();
                    if (!_isValidEmail(email)) {
                      setDialogState(() {
                        errorText = 'Please enter a valid email address';
                      });
                    } else {
                      Navigator.of(dialogContext).pop(email);
                    }
                  },
                  child: const Text('Send Reset Email'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      // Initialize providers with the newly authenticated user
      final userId = authProvider.userId;
      final sessionLogProvider = Provider.of<SessionLogProvider>(
        context,
        listen: false,
      );
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );

      await sessionLogProvider.init(userId: userId);
      await presetProvider.init(userId: userId);

      if (!mounted) return;

      // Navigate to home screen
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else if (authProvider.errorMessage?.contains('email not confirmed') ==
        true) {
      // Show email not confirmed error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.errorMessage ??
                'Your email address was not confirmed, please check your inbox',
          ), //TODO: show better error message.
          backgroundColor: context.colorScheme.error,
        ),
      );
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.errorMessage ?? 'Login failed',
          ), //TODO: show better error message. if possible show whether email was not registered, or password was wrong.
          backgroundColor: context.colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Image.asset(
                    'assets/images/bouldering_logo.png',
                    width: 100,
                    height: 100,
                    color: context.colorScheme.onSurface,
                  ),
                  const SizedBox(height: 24),

                  // Welcome text
                  Text(
                    'Welcome',
                    style: context.h1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue your training',
                    style: context.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Email confirmation message
                  if (widget.showEmailConfirmationMessage)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.mail_outline,
                            color: context.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Please check your email to confirm your account before logging in.',
                              style: context.bodyMedium.copyWith(
                                color: context.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: context.bodyMedium,
                      prefixIcon: const Icon(Icons.email),
                      fillColor: context.colorScheme.surfaceBright,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: context.bodyMedium,
                      prefixIcon: const Icon(Icons.lock),
                      fillColor: context.colorScheme.surfaceBright,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Sign in button
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return ElevatedButton(
                        onPressed: authProvider.isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child:
                            authProvider.isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : Text(
                                  'Sign In',
                                  style: context.titleLarge.copyWith(
                                    color: context.colorScheme.onPrimary,
                                  ),
                                ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _handleForgotPassword,
                    child: Text('Forgot password?', style: context.bodyLarge),
                  ),
                  const SizedBox(height: 16),

                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: context.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SignUpScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Sign up',
                          style: context.bodyMedium.copyWith(
                            color: context.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
