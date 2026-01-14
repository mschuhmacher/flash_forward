import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/presentation/screens/signup_screen.dart';
import 'package:flash_forward/presentation/screens/home_screen.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      // Navigate to home screen
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Login failed'),
          backgroundColor: Colors.red,
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
                    color: Theme.of(context).colorScheme.onSurface,
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
                  const SizedBox(height: 48),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: context.bodyMedium,
                      prefixIcon: const Icon(Icons.email),
                      fillColor: Theme.of(context).colorScheme.surfaceBright,
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
                      fillColor: Theme.of(context).colorScheme.surfaceBright,
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
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                      );
                    },
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
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // TODO: Add "Forgot Password?" link here later if needed
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
