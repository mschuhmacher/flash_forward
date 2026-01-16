import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/presentation/screens/home_screen.dart';
import 'package:flash_forward/themes/app_text_styles.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _pageController = PageController();

  // Form keys for each step
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();
  final _step3FormKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  // State
  int _currentPage = 0;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _selectedCountry;
  bool _marketingConsent = false;

  // Country list (simplified - expand as needed)
  final List<String> _countries = [
    'United States',
    'United Kingdom',
    'Canada',
    'Australia',
    'Germany',
    'France',
    'Spain',
    'Netherlands',
    'Belgium',
    'Switzerland',
    'Austria',
    'Italy',
    'Other',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _nextPage() {
    GlobalKey<FormState> currentFormKey;
    switch (_currentPage) {
      case 0:
        currentFormKey = _step1FormKey;
        break;
      case 1:
        currentFormKey = _step2FormKey;
        break;
      case 2:
        currentFormKey = _step3FormKey;
        break;
      default:
        return;
    }

    if (currentFormKey.currentState!.validate()) {
      if (_currentPage < 2) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _signUp();
      }
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _signUp() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phoneNumber:
          _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
      country: _selectedCountry,
      marketingConsent: _marketingConsent,
    );

    if (!mounted) return;

    if (success) {
      // Initialize providers with the newly authenticated user
      final userId = authProvider.userId;
      final sessionLogProvider = Provider.of<SessionLogProvider>(context, listen: false);
      final presetProvider = Provider.of<PresetProvider>(context, listen: false);

      await sessionLogProvider.init(userId: userId);
      await presetProvider.init(userId: userId);

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to home
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Sign up failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Account', style: context.h4),
        leading:
            _currentPage > 0
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _previousPage,
                )
                : null,
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (_currentPage + 1) / 3,
            backgroundColor: Colors.grey[200],
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) {
                setState(() => _currentPage = page);
              },
              children: [_buildStep1(), _buildStep2(), _buildStep3()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return ElevatedButton(
                onPressed: authProvider.isLoading ? null : _nextPage,
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
                          _currentPage < 2 ? 'Continue' : 'Create Account',
                          style: context.titleLarge.copyWith(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Step 1: Email and Password
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _step1FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Account Credentials', style: context.h3),
            const SizedBox(height: 8),
            Text('Create your login credentials', style: context.bodyMedium),
            const SizedBox(height: 32),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email *',
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
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password *',
                labelStyle: context.bodyMedium,
                prefixIcon: const Icon(Icons.lock),
                fillColor: Theme.of(context).colorScheme.surfaceBright,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password *',
                labelStyle: context.bodyMedium,
                prefixIcon: const Icon(Icons.lock),
                fillColor: Theme.of(context).colorScheme.surfaceBright,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    );
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  // Step 2: Personal Information
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _step2FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Personal Information', style: context.h3),
            const SizedBox(height: 8),
            Text('Tell us a bit about yourself', style: context.bodyMedium),
            const SizedBox(height: 32),
            TextFormField(
              controller: _firstNameController,
              decoration: InputDecoration(
                labelText: 'First Name *',
                labelStyle: context.bodyMedium,
                prefixIcon: const Icon(Icons.person),
                fillColor: Theme.of(context).colorScheme.surfaceBright,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your first name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lastNameController,
              decoration: InputDecoration(
                labelText: 'Last Name *',
                labelStyle: context.bodyMedium,
                prefixIcon: const Icon(Icons.person_outline),
                fillColor: Theme.of(context).colorScheme.surfaceBright,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your last name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCountry,
              decoration: InputDecoration(
                labelText: 'Country *',
                labelStyle: context.bodyMedium,
                prefixIcon: const Icon(Icons.public),
                fillColor: Theme.of(context).colorScheme.surfaceBright,
              ),
              items:
                  _countries.map((country) {
                    return DropdownMenuItem(
                      value: country,
                      child: Text(country),
                    );
                  }).toList(),
              onChanged: (value) {
                setState(() => _selectedCountry = value);
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select your country';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  // Step 3: Optional Information
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _step3FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Additional Details', style: context.h3),
            const SizedBox(height: 8),
            Text('Optional information', style: context.bodyMedium),
            const SizedBox(height: 32),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                labelStyle: context.bodyMedium,
                prefixIcon: const Icon(Icons.phone),
                fillColor: Theme.of(context).colorScheme.surfaceBright,
                helperText: 'For account recovery',
              ),
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              value: _marketingConsent,
              onChanged: (value) {
                setState(() => _marketingConsent = value ?? false);
              },
              title: Text(
                'Marketing Communications',
                style: context.bodyMedium,
              ),
              subtitle: Text(
                'I agree to receive training tips, updates, and promotional emails',
                style: context.bodyMedium.copyWith(fontSize: 12),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(25),
              ),
              child: RichText(
                text: TextSpan(
                  style: context.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ), // Base style
                  children: [
                    TextSpan(text: 'By signing up, you agree to our '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: context.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),

                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              final url = Uri.parse(
                                'https://studiofoam.dev/terms-of-service.html',
                              );
                              await launchUrl(url);
                            },
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: context.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              final url = Uri.parse(
                                'https://studiofoam.dev/privacy-policy.html',
                              );
                              await launchUrl(url);
                            },
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
              // Column(
              //   crossAxisAlignment: CrossAxisAlignment.start,
              //   children: [
              //     Row(
              //       children: [
              //         Icon(
              //           Icons.info_outline,
              //           color: Theme.of(context).colorScheme.onPrimary,
              //         ),
              //         const SizedBox(width: 8),
              //         Text(
              //           'Privacy Notice',
              //           style: context.titleMedium.copyWith(
              //             color:
              //                 Theme.of(context).colorScheme.onPrimary,
              //           ),
              //         ),
              //       ],
              //     ),
              //     const SizedBox(height: 8),
              //     Text(
              //       'Your data is encrypted and stored securely. We never share your personal information with third parties.',
              //       style: context.bodyMedium.copyWith(fontSize: 12),
              //     ),
              //   ],
              // ),
            ),
          ],
        ),
      ),
    );
  }
}
