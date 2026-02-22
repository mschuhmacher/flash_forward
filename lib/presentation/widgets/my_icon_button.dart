import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_colors.dart';

class MyIconButton extends StatelessWidget {
  const MyIconButton({
    required this.icon,
    this.size = 30,
    this.foregroundColor,
    this.backgroundColor,
    super.key,
  });

  final IconData icon;
  final double size;
  final Color? foregroundColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final iconSize = 2 * size / 3;

    final fgColor = foregroundColor ?? context.colorScheme.onSurface;
    final bgColor = backgroundColor ?? context.colorScheme.surfaceBright;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(width: 0.25, color: fgColor),
          color: bgColor,
          boxShadow: context.shadowSmall,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: fgColor),
        ),
      ),
    );
  }
}
