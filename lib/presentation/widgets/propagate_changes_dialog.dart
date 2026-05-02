import 'package:flutter/material.dart';

/// One group within the propagate-changes prompt: a single edited catalog
/// item ([itemTitle], described by [itemKind]) and the list of session
/// templates ([consumerLabels]) that embed a copy of it.
class PropagationSection {
  PropagationSection({
    required this.itemKind,
    required this.itemTitle,
    required this.consumerLabels,
  });

  final String itemKind;
  final String itemTitle;
  final List<String> consumerLabels;
}

/// Yes/no prompt asking the user whether to apply catalog edits to embedded
/// copies in session templates.
///
/// Accepts a list of [PropagationSection]s so a single confirmation can cover
/// several kinds of changes at once (e.g. an edited workout plus an edited
/// exercise inside it). Each section renders its own heading and consumer
/// list; sections are visually separated so the user can tell them apart.
///
/// Returns true if the user chose Update all, false for Keep local, null if
/// the dialog was dismissed.
Future<bool?> showPropagateChangesDialog({
  required BuildContext context,
  required List<PropagationSection> sections,
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
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) ...const [
                SizedBox(height: 12),
                Divider(height: 1),
                SizedBox(height: 12),
              ],
              Text(
                '${sections[i].itemTitle} (${sections[i].itemKind}) is also used in:',
              ),
              const SizedBox(height: 8),
              ...sections[i].consumerLabels.map(
                (label) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                  child: Text('• $label'),
                ),
              ),
            ],
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
