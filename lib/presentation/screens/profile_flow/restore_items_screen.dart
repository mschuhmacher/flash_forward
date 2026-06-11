import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings screen for restoring deleted items.
///
/// Two lists:
///  - "Recent removals": everything deleted in the last 90 days, newest first.
///    Each row labels the kind (Session/Workout/Exercise) and whether it is a
///    default, with a right-aligned box showing days until expiry (user items)
///    or days since removal (defaults, which never expire).
///  - "Removed default data": collapsed by default; the >90-day tail, which is
///    necessarily all defaults (user items are purged by then).
///
/// Below them, an error-coloured outlined "Factory reset" button wipes all
/// user-generated items (local + cloud) and restores every deleted default to
/// stock, gated behind a type-"factory reset"-to-confirm prompt.
class RestoreItemsScreen extends StatefulWidget {
  const RestoreItemsScreen({super.key});

  @override
  State<RestoreItemsScreen> createState() => _RestoreItemsScreenState();
}

class _RestoreItemsScreenState extends State<RestoreItemsScreen> {
  final Set<String> _selected = {};

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _daysSinceRemoval(DateTime deletedAt) =>
      DateTime.now().difference(deletedAt).inDays.clamp(0, 1 << 31);

  String _kindLabel(TrashKind kind) => switch (kind) {
        TrashKind.session => 'Session',
        TrashKind.workout => 'Workout',
        TrashKind.exercise => 'Exercise',
      };

  bool _titleClashes(CatalogProvider catalog, TrashEntry entry) =>
      _existingTitlesForKind(catalog, entry.kind).contains(entry.title);

  List<String> _existingTitlesForKind(CatalogProvider catalog, TrashKind kind) {
    return switch (kind) {
      TrashKind.session => catalog.presetSessions.map((s) => s.title).toList(),
      TrashKind.workout => catalog.presetWorkouts.map((w) => w.title).toList(),
      TrashKind.exercise =>
        catalog.presetExercises.map((e) => e.title).toList(),
    };
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

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

  Future<void> _factoryReset(CatalogProvider catalog, TrashProvider trash) async {
    final controller = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Factory reset?', style: context.h3),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This deletes all your created sessions, workouts and exercises '
                'and restores every removed default. This is irreversible.',
                style: context.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text("Type 'factory reset' to confirm.", style: context.bodyMedium),
              const SizedBox(height: 8),
              TextField(controller: controller),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                return ElevatedButton(
                  onPressed: value.text == 'factory reset'
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Factory reset'),
                );
              },
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    await catalog.factoryReset();
    await trash.clearAll();
    if (!mounted) return;
    setState(() => _selected.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Catalog reset to factory defaults')),
    );
  }

  // ── Row ──────────────────────────────────────────────────────────────────────

  Widget _row(RestorableEntry r) {
    final entry = r.entry;

    return CheckboxListTile(
      value: _selected.contains(entry.id),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (checked) => setState(() {
        if (checked == true) {
          _selected.add(entry.id);
        } else {
          _selected.remove(entry.id);
        }
      }),
      title: Text(entry.title, style: context.bodyLarge),
      subtitle: Text(_kindLabel(entry.kind), style: context.bodyMedium),
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Reserve the chip's space even when absent so the day count below
          // stays vertically aligned across rows.
          Visibility(
            visible: r.isDefault,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: const _DefaultChip(),
          ),
          const SizedBox(height: 4),
          // De-emphasised: the day count is only the sorting cue, not the focus.
          Text(
            '${_daysSinceRemoval(entry.deletedAt)}d ago',
            style: context.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore trash')),
      body: Consumer2<CatalogProvider, TrashProvider>(
        builder: (context, catalog, trash, _) {
          final all = trash.entriesByRecency;
          final cutoff = DateTime.now().subtract(const Duration(days: 90));
          final recent =
              all.where((r) => r.entry.deletedAt.isAfter(cutoff)).toList();
          final older =
              all.where((r) => !r.entry.deletedAt.isAfter(cutoff)).toList();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _SectionHeader('Recent removals'),
                    if (recent.isEmpty)
                      const _EmptyHint('Nothing removed in the last 90 days')
                    else
                      ...recent.map(_row),
                    ExpansionTile(
                      title: Text('Removed default data', style: context.h3),
                      childrenPadding: EdgeInsets.zero,
                      children: older.isEmpty
                          ? [const _EmptyHint('No older removed defaults')]
                          : older.map(_row).toList(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _factoryReset(catalog, trash),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          child: const Text('Factory reset'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 80), // room above pinned button
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selected.isEmpty
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: context.h3),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          text,
          style: context.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Small "default" pill shown next to a deleted default's title.
class _DefaultChip extends StatelessWidget {
  const _DefaultChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'default',
        style: context.bodyMedium.copyWith(
          fontSize: 12,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
