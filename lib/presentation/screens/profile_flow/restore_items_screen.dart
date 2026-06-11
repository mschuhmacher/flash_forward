import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings screen for restoring deleted items.
///
/// Entries are shown newest-deletion first. Deleted *defaults* are tagged
/// "default" and never expire, so the long tail (older than the 90-day TTL —
/// necessarily all defaults, since user items are purged by then) is tucked
/// into a collapsed "Older" section. That section also offers a low-emphasis
/// "Restore all defaults" reset-to-factory action.
///
/// When restoring, if an item's title clashes with an existing catalog entry
/// the user is asked to pick a new title via [showRenameOnCollisionDialog]
/// before the restore proceeds.
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

  // ── Restore actions ─────────────────────────────────────────────────────────

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

  Future<void> _restoreAllDefaults(TrashProvider trash) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore all defaults?'),
        content: const Text(
          'This brings back every deleted built-in preset, resetting your '
          'catalog to the factory defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await trash.restoreAllDefaults();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restored all default presets')),
    );
    setState(() => _selected.clear());
  }

  // ── Row builder ─────────────────────────────────────────────────────────────

  Widget _row(RestorableEntry r) {
    final entry = r.entry;
    final String subtitle;
    if (r.isDefault) {
      subtitle = 'Hidden default';
    } else {
      final days = _daysRemaining(entry.deletedAt);
      subtitle = days == 0
          ? 'Expires today'
          : 'Expires in $days day${days == 1 ? '' : 's'}';
    }
    final isUrgent = !r.isDefault && _daysRemaining(entry.deletedAt) <= 7;

    return CheckboxListTile(
      value: _selected.contains(entry.id),
      onChanged: (checked) => setState(() {
        if (checked == true) {
          _selected.add(entry.id);
        } else {
          _selected.remove(entry.id);
        }
      }),
      title: Row(
        children: [
          Expanded(child: Text(entry.title, style: context.bodyLarge)),
          if (r.isDefault) const _DefaultChip(),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isUrgent
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore items')),
      body: Consumer2<CatalogProvider, TrashProvider>(
        builder: (context, catalog, trash, _) {
          final all = trash.entriesByRecency;
          if (all.isEmpty) {
            return const Center(child: Text('Trash is empty'));
          }

          final cutoff = DateTime.now().subtract(const Duration(days: 90));
          final recent =
              all.where((r) => r.entry.deletedAt.isAfter(cutoff)).toList();
          // Older than the TTL — necessarily all defaults (user items purge).
          final older =
              all.where((r) => !r.entry.deletedAt.isAfter(cutoff)).toList();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    ...recent.map(_row),
                    if (older.isNotEmpty)
                      ExpansionTile(
                        title: Text('Older (${older.length})', style: context.h3),
                        children: [
                          ...older.map(_row),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => _restoreAllDefaults(trash),
                                child: const Text('Restore all defaults'),
                              ),
                            ),
                          ),
                        ],
                      ),
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
        style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
      ),
    );
  }
}
