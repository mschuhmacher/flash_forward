import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class SkipOnboarding extends StatelessWidget {
  const SkipOnboarding({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: context.colorScheme.surfaceBright,
        ),
        child: Text('SKIP', style: context.bodyLarge),
      ),
    );
  }
}
