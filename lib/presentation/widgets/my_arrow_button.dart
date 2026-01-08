import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_shadow.dart';

class MyArrowButton extends StatelessWidget {
  const MyArrowButton({required this.icon, this.size = 30, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = 2 * size / 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: 0.25,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          color: Theme.of(context).colorScheme.surfaceBright,
          boxShadow: context.shadowSmall,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize),
        ),
      ),
    );
  }
}
