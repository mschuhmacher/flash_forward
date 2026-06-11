import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_colors.dart';

class MyIconButton extends StatelessWidget {
  const MyIconButton({
    required this.icon,
    this.size = 30,
    this.iconSize,
    this.foregroundColor,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final IconData icon;
  final double size;
  final double? iconSize;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final icSize = iconSize ?? 2 * size / 3;

    final fgColor = foregroundColor ?? context.colorScheme.onSurface;
    final bgColor = backgroundColor ?? context.colorScheme.surfaceBright;
    final boColor = borderColor ?? context.colorScheme.surfaceBright;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(width: 0.25, color: boColor),
            color: bgColor,
            boxShadow: context.shadowSmall,
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: icSize, color: fgColor),
          ),
        ),
      ),
    );
  }
}
