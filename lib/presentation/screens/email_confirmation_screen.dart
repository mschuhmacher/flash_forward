import 'package:flash_forward/presentation/screens/login_screen.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/utils/timer_utils.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';

class EmailConfirmationScreen extends StatefulWidget {
  final String email;

  const EmailConfirmationScreen({
    required this.email,
    super.key,
  });

  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  Timer? _countdownTimer;
  Timer? _pollingTimer;
  Duration _remainingToResend = Duration(seconds: 120);
  bool _canResend = false; // True when resend button should be visible
  bool _hasResent = false; // True after user has used their one resend
  bool _resendExhausted =
      false; // True after second countdown ends (no more resends)

  @override
  void initState() {
    super.initState();
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
      // Countdown reached zero
      if (!_hasResent) {
        // First timeout - show resend button
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      } else {
        // Second timeout (after resend) - hide resend permanently
        setState(() {
          _canResend = false;
          _resendExhausted = true;
        });
        timer.cancel();
      }
    });
  }

  void _startPollingTimer() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) return;

      final isConfirmed = await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).checkEmailConfirmed(widget.email);

      // If confirmed, navigate to login screen with success message
      if (isConfirmed == true && mounted) {
        timer.cancel();
        _countdownTimer?.cancel();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(
              showEmailConfirmationMessage: true,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
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
            if (_canResend)
              OutlinedButton(
                onPressed: () async {
                  final authProvider = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  );
                  final messenger = ScaffoldMessenger.of(context);

                  await authProvider.resendConfirmationEmail(widget.email);

                  if (!mounted) return;

                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Confirmation email resent!'),
                      backgroundColor: Colors.green,
                    ),
                  );

                  setState(() {
                    _hasResent = true;
                    _canResend = false;
                    _remainingToResend = Duration(seconds: 120);
                  });
                  _startCountdownTimer();
                },
                child: Text('Resend email', style: context.titleLarge),
              )
            else if (_resendExhausted)
              Text(
                'Please check your email and return to login',
                style: context.bodyMedium,
                textAlign: TextAlign.center,
              )
            else
              Text('Awaiting confirmation...', style: context.titleLarge),
            SizedBox(height: 16),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
