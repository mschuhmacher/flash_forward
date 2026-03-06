import 'package:flash_forward/presentation/screens/loading_screen.dart';
import 'package:flash_forward/presentation/screens/login_screen.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/services/auth_service.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/utils/timer_utils.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';

class EmailConfirmationScreen extends StatefulWidget {
  final String email;

  const EmailConfirmationScreen({required this.email, super.key});

  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  Timer? _countdownTimer;
  Timer? _pollingTimer;
  Duration _remainingToResend = Duration(seconds: 120);

  late final AuthProvider _authProvider;

  @override
  void initState() {
    super.initState();
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _startCountdownTimer();
    _startPollingTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingToResend > Duration.zero) {
        setState(() {
          _remainingToResend -= const Duration(seconds: 1);
        });
        return;
      }
      // Timed out — send the user back to login with the "please confirm" message
      timer.cancel();
      _pollingTimer?.cancel();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(showEmailConfirmationMessage: true),
          ),
        );
      }
    });
  }

  void _startPollingTimer() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!mounted) return;

      final EmailStatus emailStatus = await _authProvider.pollForEmailConfirmation(
        widget.email,
      );

      if (emailStatus == EmailStatus.confirmed && mounted) {
        timer.cancel();
        _countdownTimer?.cancel();
        final success = await _authProvider.autoSignInAfterConfirmation(widget.email);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => success ? const LoadingScreen() : const LoginScreen(showEmailConfirmedMessage: true),
          ),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _authProvider.clearPendingSignupPassword();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mail_outline_rounded,
              size: 80,
              color: context.colorScheme.primary,
            ),
            SizedBox(height: 16),
            Text('Check your email', style: context.h1),
            SizedBox(height: 16),
            Text('The confirmation email was sent to: \n${widget.email}'),
            SizedBox(height: 16),

            Text(formatDuration(_remainingToResend), style: context.h3),
            SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => LoginScreen()),
                );
              },
              child: Text('Go back to login', style: context.h3),
            ),
            SizedBox(height: 16),
            Text('Awaiting confirmation...', style: context.titleLarge),
            SizedBox(height: 16),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
