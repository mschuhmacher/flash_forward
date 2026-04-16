import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows a one-time educational dialog the first time the user edits a default
/// item. After it has been shown once, it never appears again (tracked via
/// SharedPreferences key `pref_seen_default_edit_tip`).
///
/// Rationale: the copy-on-edit flow is silent by design, but that silence
/// hides two important facts from the user — (1) their edit became a new
/// personal copy, not an in-place modification of the default, and (2) the
/// original can be brought back via Settings > Restore defaults. Showing
/// this once builds the user's mental model for the whole feature.
Future<void> showDefaultEditTipIfNeeded(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('pref_seen_default_edit_tip') == true) return;
  // Persist before showing so even if the user force-quits mid-dialog we
  // don't annoy them with it again on next launch.
  await prefs.setBool('pref_seen_default_edit_tip', true);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Default item customized'),
      content: const Text(
        "You just edited a default item. Your changes were saved as a personal "
        "copy — the original default has been hidden from your catalog. "
        "You can bring all default content back anytime via "
        "Settings > Restore defaults.",
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
