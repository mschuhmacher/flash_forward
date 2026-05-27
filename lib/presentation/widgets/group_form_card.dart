import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';

class GroupFormCard extends StatelessWidget {
  final List<Widget> children;

  const GroupFormCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final dividerColor = context.colorScheme.primary.withValues(alpha: 0.08);
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: dividerColor, width: 1),
        boxShadow: context.shadowSmall,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _withDividers(context, children),
        ),
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context, List<Widget> items) {
    final dividerColor = context.colorScheme.primary.withValues(alpha: 0.07);
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(Divider(height: 1, thickness: 1, color: dividerColor));
      }
    }
    return result;
  }
}

/// Inline row: fixed-width muted label left, child fills the rest, optional trailing.
class GroupFormRow extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;

  const GroupFormRow({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            child: Text(label, style: context.titleMedium),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

/// Stacked row: small-caps colored label above, child below.
class GroupFormStackRow extends StatelessWidget {
  final String label;
  final Widget child;
  final Color accentColor;

  const GroupFormStackRow({
    super.key,
    required this.label,
    required this.child,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: context.label.copyWith(color: accentColor),
          ),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }
}

/// Horizontal row: muted label left, IncrementDecrementNumberWidget right.
class GroupFormRestRow extends StatelessWidget {
  final String label;
  final int value;
  final int minimum;
  final int? maximum;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const GroupFormRestRow({
    super.key,
    required this.label,
    required this.value,
    this.minimum = 0,
    this.maximum,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.titleMedium)),
          IncrementDecrementNumberWidget(
            value: value,
            minimum: minimum,
            maximum: maximum,
            decrement: onDecrement,
            increment: onIncrement,
          ),
        ],
      ),
    );
  }
}

/// Inline character counter, shown as trailing inside a GroupFormRow.
class GroupFormCounter extends StatelessWidget {
  final int current;
  final int max;

  const GroupFormCounter({super.key, required this.current, required this.max});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$current/$max',
      style: context.bodyMedium.copyWith(
        fontSize: 12,
        color: context.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
