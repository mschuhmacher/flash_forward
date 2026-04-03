import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class LabelBadge extends StatelessWidget {
  final String labelKey;
  const LabelBadge({super.key, required this.labelKey});

  @override
  Widget build(BuildContext context) {
    final label = kDefaultLabels[labelKey];
    if (label == null) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: label.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(label.icon, size: 12, color: label.color),
          SizedBox(width: 4),
          Text(
            label.name,
            style: context.bodyMedium.copyWith(
              color: label.color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
