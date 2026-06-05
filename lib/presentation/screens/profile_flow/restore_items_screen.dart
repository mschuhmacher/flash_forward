import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings screen that lets users review items in the trash and restore
/// selected ones. Items are grouped into three sections (Sessions / Workouts /
/// Exercises). Each row shows the item title and how many days remain before
/// it is permanently purged (90-day TTL). Rows expiring in 7 days or fewer
/// are flagged in the error colour to prompt action.
///
/// When restoring, if an item's title clashes with an existing catalog entry
/// the user is asked to pick a new title via [showRenameOnCollisionDialog]
/// before the restore proceeds. The user can also cancel a single collision
/// without aborting the rest of the batch.
class RestoreItemsScreen extends StatefulWidget {
  const RestoreItemsScreen({super.key});

  @override
  State<RestoreItemsScreen> createState() => _RestoreItemsScreenState();
}

class _RestoreItemsScreenState extends State<RestoreItemsScreen> {
  final Set<String> _selected = {};

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _daysRemaining(DateTime deletedAt) {
    final expiresAt = deletedAt.add(const Duration(days: 90));
    final diff = expiresAt.difference(DateTime.now());
    return diff.inDays.clamp(0, 90);
  }

  bool _titleClashes(CatalogProvider catalog, TrashEntry entry) {
    return _existingTitlesForKind(catalog, entry.kind).contains(entry.title);
  }

  List<String> _existingTitlesForKind(
    CatalogProvider catalog,
    TrashKind kind,
  ) {
    return switch (kind) {
      TrashKind.session => catalog.presetSessions.map((s) => s.title).toList(),
      TrashKind.workout => catalog.presetWorkouts.map((w) => w.title).toList(),
      TrashKind.exercise =>
        catalog.presetExercises.map((e) => e.title).toList(),
    };
  }

  // ── Restore action ────────────────────────────────────────────────────────

  Future<void> _restoreSelected(
    CatalogProvider catalog,
    TrashProvider trash,
  ) async {
    final ids = Set<String>.from(_selected);
    int restoredCount = 0;

    for (final id in ids) {
      final matchIndex = trash.trashedItems.indexWhere((e) => e.id == id);
      if (matchIndex == -1) continue;
      final entry = trash.trashedItems[matchIndex];

      String? overrideTitle;
      if (_titleClashes(catalog, entry)) {
        if (!mounted) return;
        overrideTitle = await showRenameOnCollisionDialog(
          context: context,
          currentTitle: entry.title,
          existingTitles: _existingTitlesForKind(catalog, entry.kind),
        );
        if (overrideTitle == null) continue; // user cancelled this one; skip
      }

      await trash.restoreFromTrash(id, overrideTitle: overrideTitle);
      restoredCount++;
    }

    if (!mounted) return;
    if (restoredCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored $restoredCount item(s)')),
      );
    }
    setState(() => _selected.clear());
  }

  // ── Section builder ───────────────────────────────────────────────────────

  Widget _buildSection({
    required String heading,
    required List<TrashEntry> entries,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(heading, style: context.h3),
        ),
        ...entries.map((entry) {
          final days = _daysRemaining(entry.deletedAt);
          final isUrgent = days <= 7;
          final subtitleStyle = TextStyle(
            color:
                isUrgent
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          );

          return CheckboxListTile(
            value: _selected.contains(entry.id),
            onChanged:
                (checked) => setState(() {
                  if (checked == true) {
                    _selected.add(entry.id);
                  } else {
                    _selected.remove(entry.id);
                  }
                }),
            title: Text(entry.title, style: context.bodyLarge),
            subtitle: Text(
              days == 0
                  ? 'Expires today'
                  : 'Expires in $days day${days == 1 ? '' : 's'}',
              style: subtitleStyle,
            ),
            controlAffinity: ListTileControlAffinity.leading,
          );
        }),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore items')),
      body: Consumer2<CatalogProvider, TrashProvider>(
        builder: (context, catalog, trash, _) {
          final sessions =
              trash.trashedItems
                  .where((e) => e.kind == TrashKind.session)
                  .toList();
          final workouts =
              trash.trashedItems
                  .where((e) => e.kind == TrashKind.workout)
                  .toList();
          final exercises =
              trash.trashedItems
                  .where((e) => e.kind == TrashKind.exercise)
                  .toList();

          final isEmpty =
              sessions.isEmpty && workouts.isEmpty && exercises.isEmpty;

          if (isEmpty) {
            return const Center(child: Text('Trash is empty'));
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _buildSection(heading: 'Sessions', entries: sessions),
                    _buildSection(heading: 'Workouts', entries: workouts),
                    _buildSection(heading: 'Exercises', entries: exercises),
                    const SizedBox(height: 80), // breathing room above button
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _selected.isEmpty
                              ? null
                              : () => _restoreSelected(catalog, trash),
                      child: const Text('Restore selected'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
