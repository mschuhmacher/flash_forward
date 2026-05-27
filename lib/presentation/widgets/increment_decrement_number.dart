import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class IncrementDecrementNumberWidget extends StatelessWidget {
  final int value;
  final int minimum;
  final int? maximum;
  final VoidCallback decrement;
  final VoidCallback increment;

  const IncrementDecrementNumberWidget({
    required this.value,
    required this.minimum,
    this.maximum,
    required this.decrement,
    required this.increment,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrement = value > minimum;
    final canIncrement = maximum == null || value < maximum!;
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colorScheme.primary.withValues(alpha: 0.14),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: canDecrement ? decrement : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(15)),
              ),
              width: 50,
              height: 50,
              child: Center(
                child: Icon(
                  Icons.remove_rounded,
                  color: canDecrement
                      ? context.colorScheme.onSurface
                      : context.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 50,
            height: 50,
            child: Center(
              child: Text(value.toString(), style: context.titleLarge),
            ),
          ),
          GestureDetector(
            onTap: canIncrement ? increment : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(right: Radius.circular(15)),
              ),
              width: 50,
              height: 50,
              child: Center(
                child: Icon(
                  Icons.add_rounded,
                  color: canIncrement
                      ? context.colorScheme.onSurface
                      : context.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
