import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class IncrementDecrementNumberWidget extends StatelessWidget {
  final int value;
  final VoidCallback decrement;
  final VoidCallback increment;

  const IncrementDecrementNumberWidget({
    required this.value,
    required this.decrement,
    required this.increment,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            // TODO: add in safeguard that user cannot decrement beyond current set/rep
            if (value > 1) {
              decrement();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
              color: context.colorScheme.onPrimary,
            ),
            width: 50,
            height: 50,
            child: Center(child: Icon(Icons.remove_rounded)),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: context.colorScheme.onPrimary),
          width: 50,
          height: 50,
          child: Center(
            child: Text(value.toString(), style: context.titleLarge),
          ),
        ),
        GestureDetector(
          onTap: increment,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
              color: context.colorScheme.onPrimary,
            ),
            width: 50,
            height: 50,
            child: Center(child: Icon(Icons.add_rounded)),
          ),
        ),
      ],
    );
  }
}
