import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_theme.dart';

class MyIconButton extends StatelessWidget {
  MyIconButton({
    required this.icon,
    this.size = 30,
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  });

  final IconData icon;
  final double size;
  Color? foregroundColor;
  Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final iconSize = 2 * size / 3;

    foregroundColor ??= Theme.of(context).colorScheme.onSurface;
    backgroundColor ??= Theme.of(context).colorScheme.surfaceBright;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(width: 0.25, color: foregroundColor!),
          color: backgroundColor!,
          boxShadow: context.shadowSmall,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: foregroundColor!),
        ),
      ),
    );
  }
}
