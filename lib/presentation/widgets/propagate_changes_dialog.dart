import 'package:flutter/material.dart';

class PropagationConsumer {
  final String id;
  final String label;

  const PropagationConsumer({required this.id, required this.label});
}

class PropagationSection {
  PropagationSection({
    required this.itemKind,
    required this.itemId,
    required this.itemTitle,
    required this.consumers,
    required this.consumerKind,
  });

  /// 'workout' or 'exercise' — what is being changed.
  final String itemKind;
  /// Stable id of the changed item.
  final String itemId;
  /// Display title of the changed item.
  final String itemTitle;
  /// What kind of consumer this section lists: 'sessions' | 'workouts'.
  final String consumerKind;
  final List<PropagationConsumer> consumers;

  /// Selection-map key — kind-prefixed to disambiguate same id in two consumer categories.
  String get selectionKey => '$itemKind-in-$consumerKind:$itemId';
}

class PropagationSelection {
  PropagationSelection(this._byKey);
  final Map<String, Set<String>> _byKey;

  Set<String> consumerIdsFor(PropagationSection section) =>
      _byKey[section.selectionKey] ?? const {};

  bool get isEmpty => _byKey.values.every((s) => s.isEmpty);

  Set<String>? sessionIdsFor(String itemKind, String itemId) =>
      _byKey['$itemKind-in-sessions:$itemId'];
  Set<String>? workoutIdsFor(String itemKind, String itemId) =>
      _byKey['$itemKind-in-workouts:$itemId'];
}

/// Per-consumer checkbox prompt asking the user which embedded copies to update.
///
/// Each [PropagationSection] renders its own group of checkboxes. All consumers
/// are checked by default (preserves the old "Update all" behaviour on a plain
/// confirm). Returns a [PropagationSelection] on confirm, or null on cancel.
Future<PropagationSelection?> showPropagateChangesDialog({
  required BuildContext context,
  required List<PropagationSection> sections,
}) {
  final selected = <String, Set<String>>{
    for (final s in sections)
      s.selectionKey: {for (final c in s.consumers) c.id},
  };
  return showDialog<PropagationSelection>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      return AlertDialog(
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
                  '${sections[i].itemTitle} (${sections[i].itemKind}) '
                  'is also used in:',
                ),
                ...sections[i].consumers.map((c) {
                  final key = sections[i].selectionKey;
                  final isChecked = selected[key]!.contains(c.id);
                  return CheckboxListTile(
                    visualDensity: VisualDensity(vertical: -4),
                    value: isChecked,
                    title: Text(c.label),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected[key]!.add(c.id);
                      } else {
                        selected[key]!.remove(c.id);
                      }
                    }),
                  );
                }),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  TextButton(
                    onPressed: () => setState(() {
                      selected[sections[i].selectionKey] = {
                        for (final c in sections[i].consumers) c.id,
                      };
                    }),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      selected[sections[i].selectionKey]!.clear();
                    }),
                    child: const Text('Select none'),
                  ),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(PropagationSelection(Map.of(selected))),
            child: const Text('Update selected'),
          ),
        ],
      );
    }),
  );
}
