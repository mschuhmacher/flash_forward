import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/presentation/screens/auth_flow/login_screen.dart';
import 'package:flash_forward/presentation/screens/auth_flow/signup_screen.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<bool> requireAuth(
  BuildContext context, {
  required String message,
}) async {
  if (context.read<AuthProvider>().isAuthenticated) return true;

  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: context.colorScheme.surfaceBright,
    builder: (BuildContext modalContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16),
          Text(
            'In order to $message you need to be signed in.',
            style: context.titleLargePrimary,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(modalContext).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SignUpScreen(popOnSuccess: true),
                ),
              );
              if (!modalContext.mounted) return;
              Navigator.pop(modalContext, result);
            },
            child: Text('Create account', style: context.h4.copyWith(color: context.colorScheme.onPrimary)),
          ),
          SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              final result = await Navigator.of(modalContext).push<bool>(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(popOnSuccess: true, guestMode: true,),
                ),
              );
              if (!modalContext.mounted) return;
              Navigator.pop(modalContext, result);
            },
            child: Text('Log in', style: context.titleLargePrimary),
          ),
          SizedBox(height: 40),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(modalContext, null);
            },
            child: Text('Not now', style: context.bodyLarge),
          ),
          SizedBox(height: 16),
        ],
      );
    },
  );
  if (result == null) {
    return false;
  }
  return result;
}
