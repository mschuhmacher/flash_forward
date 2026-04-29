import 'package:flutter/material.dart';

/// Yes/no prompt asking the user whether to apply a catalog edit to embedded
/// copies in session templates. The body lists the affected templates (and
/// optionally the workout each occurrence sits in) so the user knows what
/// they're about to change.
///
/// Returns true if the user chose Yes, false if No, null if dismissed.
Future<bool?> showPropagateChangesDialog({
  required BuildContext context,
  required String itemKind,
  required List<String> affectedItemLabels,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Apply changes elsewhere?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('This $itemKind is also used in:'),
            const SizedBox(height: 8),
            ...affectedItemLabels.map(
              (label) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                child: Text('• $label'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Update those too, or keep your changes local to this catalog item only?',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep local'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Update all'),
        ),
      ],
    ),
  );
}
