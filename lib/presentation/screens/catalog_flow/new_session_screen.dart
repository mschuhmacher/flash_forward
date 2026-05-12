import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/presentation/widgets/workout_card.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/presentation/screens/session_flow/session_active_screen.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class NewSessionScreen extends StatefulWidget {
  final Session? session;
  final bool startAfterSave;

  const NewSessionScreen({
    super.key,
    this.session,
    this.startAfterSave = false,
  });

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get _isNew => widget.session == null;

  late Session _session =
      widget.session?.deepCopy(keepId: true) ??
      Session(title: 'title', label: 'label', workouts: []);

  /// Accumulates workout and exercise edits from nested drilldowns.
  /// Flushed to the provider on Save via PresetProvider.commitChanges.
  final PendingChangeBag _pending = PendingChangeBag();

  late final _titleController = TextEditingController(
    text: widget.session?.title,
  );
  late final _itemLabelController = TextEditingController(
    text: widget.session?.label,
  );
  late final _descriptionController = TextEditingController(
    text: widget.session?.description,
  );

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _itemLabelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final session = _session.copyWith(
        title: _titleController.text.trim(),
        label: _itemLabelController.text,
        description: Nullable(
          _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        ),
        userId:
            _session.userId ??
            Provider.of<AuthProvider>(context, listen: false).userId,
      );

      if (widget.startAfterSave) {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => ActiveSessionScreen(session: session),
            ),
            (route) => route.isFirst,
          );
        }
        return;
      }

      final presetProvider = Provider.of<PresetProvider>(context, listen: false);

      if (_isNew) {
        await presetProvider.addPresetSession(session);
      } else {
        final bag = PendingChangeBag()..setSession(session);
        for (final wc in _pending.workoutsById.values) {
          bag.addWorkout(wc.workout);
        }
        for (final ec in _pending.exercisesById.values) {
          bag.addExercise(ec.exercise);
        }
        final result = await presetProvider.commitChanges(
          bag,
          excludeSessionId: session.id,
        );
        if (result.hasAny && mounted) {
          final sections = <PropagationSection>[
            for (final entry in result.affectedSessionsByWorkoutId.entries)
              PropagationSection(
                itemKind: 'workout',
                itemTitle: bag.workoutsById[entry.key]!.workout.title,
                consumerLabels: entry.value.map((s) => s.title).toList(),
              ),
            for (final entry in result.affectedWorkoutsByExerciseId.entries)
              PropagationSection(
                itemKind: 'exercise',
                itemTitle: bag.exercisesById[entry.key]!.exercise.title,
                consumerLabels: entry.value.map((w) => w.title).toList(),
              ),
          ];
          final yes = await showPropagateChangesDialog(
            context: context,
            sections: sections,
          );
          if (yes == true) await presetProvider.propagateBag(bag);
        }
      }
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _saveWorkoutToCatalog(Workout workout) async {
    final pp = Provider.of<PresetProvider>(context, listen: false);
    final titles = pp.presetWorkouts.map((w) => w.title).toList();
    String? finalTitle = workout.title;
    if (titles.contains(workout.title)) {
      finalTitle = await showRenameOnCollisionDialog(
        context: context,
        currentTitle: workout.title,
        existingTitles: titles,
      );
      if (finalTitle == null) return;
    }
    await pp.liftToCatalog(
      item: finalTitle == workout.title ? workout : workout.copyWith(title: finalTitle),
      kind: TrashKind.workout,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to catalog')),
    );
  }

  // Slidable Copy means divergence. Fresh UUID so this card evolves
  // independently of the original (e.g. a circuits use case where the same
  // template appears twice with different reps/loads).
  _copyWorkout(Workout workout) {
    final newWorkout = workout.deepCopy();
    setState(() {
      final index = _session.workouts.indexOf(workout);
      _session.workouts.insert(index + 1, newWorkout);
    });
  }

  _deleteWorkout(Workout workout) {
    setState(() {
      final index = _session.workouts.indexOf(workout);
      _session.workouts.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final Set<String> existingWorkoutIds = {};

    if (session.workouts.isNotEmpty) {
      for (var i = 0; i < session.workouts.length; i++) {
        existingWorkoutIds.add(session.workouts[i].id);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox.shrink(),
            Text(_isNew ? 'New session' : 'Edit session'),
            ElevatedButton(
              onPressed: _save,
              style: ButtonStyle().copyWith(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
              child: Text(widget.startAfterSave ? 'Save & Start' : 'Save'),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Column(
            children: [
              SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _titleController,
                      maxLength: FieldLimits.sessionTitleMaxLength,
                      decoration: InputDecoration(
                        fillColor: context.colorScheme.surfaceBright,
                        labelText: 'Title',
                        labelStyle: context.bodyMedium,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 8,
                        ),
                      ),
                      validator: (v) {
                        final presetProvider = Provider.of<PresetProvider>(context, listen: false);
                        return FieldValidators.sessionTitle(
                          v,
                          existingTitles: presetProvider.presetSessions.map((s) => s.title).toList(),
                          ownTitle: widget.session?.title,
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: MyLabelDropdownButton(
                      value:
                          _itemLabelController.text.isNotEmpty
                              ? _itemLabelController.text
                              : null,
                      onChanged: (value) {
                        setState(() {
                          _itemLabelController.text = value ?? '';
                        });
                      },
                      validator: FieldValidators.label,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _descriptionController,
                      // autofocus: true,
                      maxLength: FieldLimits.sessionDescriptionMaxLength,
                      maxLines: null,
                      decoration: InputDecoration(
                        fillColor: context.colorScheme.surfaceBright,
                        labelText: 'Description',
                        labelStyle: context.bodyMedium,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                      ),
                      validator: FieldValidators.sessionDescription,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              session.workouts.isEmpty
                  ? Expanded(
                    child: Center(
                      child: Text(
                        'No workouts yet',
                        style: context.bodyMedium.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                  : Expanded(
                    child: ReorderableListView.builder(
                      padding: EdgeInsets.only(top: 4, bottom: 16),
                      itemCount: session.workouts.length,
                      itemBuilder: (BuildContext context, int index) {
                        final workout = session.workouts[index];
                        final pp = Provider.of<PresetProvider>(context, listen: false);
                        final notInCatalog = pp.presetWorkouts.every((w) => w.id != workout.id);
                        final notInTrash = pp.trashedItems.every((e) => e.id != workout.id);
                        return _WorkoutCard(
                          workout: workout,
                          key: ValueKey(
                            '$index-${workout.id}',
                          ), // prefix index to workout.id to allow multiple instances of same workout in the reorderable list
                          onCopy: () => _copyWorkout(workout),
                          onDelete: () => _deleteWorkout(workout),
                          onSaveToCatalog: (notInCatalog && notInTrash)
                              ? () => _saveWorkoutToCatalog(workout)
                              : null,
                          onTap: () async {
                            final result = await Navigator.push<
                                ({Workout workout, PendingChangeBag pending})>(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) =>
                                        NewWorkoutScreen(workout: workout),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _session.workouts[index] = result.workout;
                              });
                              _pending.addWorkout(result.workout);
                              // Merge the inner bag so nested exercise edits
                              // also flow up to the session save.
                              _pending.merge(result.pending);
                            }
                          },
                        );
                      },
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -=
                                1; // Since the widget if removed from its old index
                          }
                          final Workout workout = session.workouts.removeAt(
                            oldIndex,
                          );
                          session.workouts.insert(newIndex, workout);
                        });
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          List<Workout>? addedWorkouts = await Navigator.push(
            context,
            MaterialPageRoute<List<Workout>>(
              builder:
                  (context) => AddItemScreen(
                    itemType: ItemType.workouts,
                    existingItemIds: existingWorkoutIds,
                  ),
            ),
          );

          if (addedWorkouts != null && addedWorkouts.isNotEmpty) {
            setState(() {
              _session = _session.copyWith(
                workouts: [..._session.workouts, ...addedWorkouts],
              );
            });
          }
        },
        child: Icon(Icons.add),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final Workout workout;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  /// When non-null, a "Save to catalog" slidable action is shown. Null means
  /// the action is hidden (the workout is already in the catalog or in trash).
  final VoidCallback? onSaveToCatalog;

  const _WorkoutCard({
    super.key,
    required this.workout,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
    this.onSaveToCatalog,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Slidable(
        key: ValueKey(workout.id),
        endActionPane: ActionPane(
          motion: ScrollMotion(),
          children: [
            if (onSaveToCatalog != null) ...[
              SizedBox(width: 8),
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (_) => onSaveToCatalog!(),
                backgroundColor: context.colorScheme.tertiary,
                foregroundColor: context.colorScheme.onTertiary,
                icon: Icons.save_alt_rounded,
                label: 'Save to catalog',
              ),
            ],
            SizedBox(width: 8),
            SlidableAction(
              borderRadius: BorderRadius.circular(12),
              onPressed: (_) => onCopy(),
              backgroundColor: context.colorScheme.secondary,
              foregroundColor: context.colorScheme.onError,
              icon: Icons.copy_rounded,
              label: 'Copy',
            ),
            SizedBox(width: 8),
            SlidableAction(
              borderRadius: BorderRadius.circular(12),
              onPressed: (_) => onDelete(),
              backgroundColor: context.colorScheme.error,
              foregroundColor: context.colorScheme.onError,
              icon: Icons.delete_rounded,
              label: 'Delete',
            ),
          ],
        ),
        child: SessionWorkoutCard(workout: workout),
      ),
    );
  }
}
