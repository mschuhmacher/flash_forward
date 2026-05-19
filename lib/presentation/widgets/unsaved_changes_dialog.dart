import 'package:flutter/material.dart';

/// Shows a dialog warning the user about unsaved changes.
/// Returns `true` to save, `false` to discard, `null` if cancelled (stay).
Future<bool?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have unsaved changes. Do you want to save or discard them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Discard'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
  );
}
