import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flash_forward/utils/superset_utils.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/superset_modal.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class NewWorkoutScreen extends StatefulWidget {
  final Workout? workout;

  /// When true, saving will persist the workout to [PresetProvider] (add or
  /// update). Use this when opening the screen standalone (e.g. from the FAB
  /// or catalog). Leave false when used as a sub-editor inside another form
  /// (e.g. editing a workout within a session).
  final bool persistToProvider;

  const NewWorkoutScreen({super.key, this.workout, this.persistToProvider = false});

  @override
  State<NewWorkoutScreen> createState() => _NewWorkoutScreenState();
}

class _NewWorkoutScreenState extends State<NewWorkoutScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get _isNew => widget.workout == null;

  late Workout _workout =
      widget.workout?.deepCopy(keepId: true) ??
      Workout(
        title: 'title',
        label: 'label',
        exercises: [],
        timeBetweenExercises: 120,
      );

  /// Accumulates exercise edits made via nested NewExerciseScreen drilldowns.
  /// Flushed to the provider on Save (standalone) or returned to the parent (nested).
  final PendingChangeBag _pending = PendingChangeBag();

  late final _titleController = TextEditingController(
    text: widget.workout?.title,
  );
  late final _itemLabelController = TextEditingController(
    text: widget.workout?.label,
  );
  late final _descriptionController = TextEditingController(
    text: widget.workout?.description,
  );

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _itemLabelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Defense-in-depth: every editing path validates contiguity, but a
    // future code change could slip through. Refuse to persist a broken
    // state.
    if (!supersetsRemainContiguous(_workout.exercises, _workout.supersets)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A superset is broken — please re-create it')),
      );
      return;
    }
    if (_formKey.currentState!.validate()) {
      final workout = _workout.copyWith(
        title: _titleController.text.trim(),
        label: _itemLabelController.text,
        description: Nullable(
          _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        ),
        userId:
            _workout.userId ??
            Provider.of<AuthProvider>(context, listen: false).userId,
      );
      if (widget.persistToProvider) {
        final presetProvider = Provider.of<PresetProvider>(
          context,
          listen: false,
        );

        if (_isNew) {
          await presetProvider.addPresetWorkout(workout);
        } else {
          final bag = PendingChangeBag()..addWorkout(workout);
          for (final ec in _pending.exercisesById.values) {
            bag.addExercise(ec.exercise);
          }
          // excludeWorkoutId filters the parent workout out of each exercise's
          // affected-workouts list — those edits ride along with the workout
          // commit and don't need a separate propagation entry.
          final result = await presetProvider.commitChanges(
            bag,
            excludeWorkoutId: workout.id,
          );

          if (result.hasAny && mounted) {
            final sections = <PropagationSection>[
              for (final entry in result.affectedSessionsByWorkoutId.entries)
                PropagationSection(
                  itemKind: 'workout',
                  itemTitle: workout.title,
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
      }
      if (mounted) {
        Navigator.pop(context, (workout: workout, pending: _pending));
      }
    }
  }

  Future<void> _saveExerciseToCatalog(Exercise exercise) async {
    final pp = Provider.of<PresetProvider>(context, listen: false);
    final titles = pp.presetExercises.map((e) => e.title).toList();
    String? finalTitle = exercise.title;
    if (titles.contains(exercise.title)) {
      finalTitle = await showRenameOnCollisionDialog(
        context: context,
        currentTitle: exercise.title,
        existingTitles: titles,
      );
      if (finalTitle == null) return;
    }
    await pp.liftToCatalog(
      item: finalTitle == exercise.title ? exercise : exercise.copyWith(title: finalTitle),
      kind: TrashKind.exercise,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to catalog')),
    );
  }

  // Slidable Copy means divergence. Fresh UUID so this card evolves
  // independently of the original (e.g. a circuits use case where the same
  // template appears twice with different reps/loads).
  // Per design rule: a copy never joins the original's superset. If the
  // source is in a superset, insert the copy *after* the entire block so the
  // contiguity invariant is preserved.
  _copyExercise(Exercise exercise) {
    final newExercise = exercise.deepCopy();
    setState(() {
      final ss = supersetForExercise(_workout, exercise.id);
      int insertAt;
      if (ss != null) {
        var lastMemberIndex = -1;
        for (var i = 0; i < _workout.exercises.length; i++) {
          if (ss.exerciseIds.contains(_workout.exercises[i].id)) {
            lastMemberIndex = i;
          }
        }
        insertAt = lastMemberIndex + 1;
      } else {
        insertAt = _workout.exercises.indexOf(exercise) + 1;
      }
      final newList = List<Exercise>.from(_workout.exercises)
        ..insert(insertAt, newExercise);
      _workout = _workout.copyWith(exercises: newList);
    });
  }

  _deleteExercise(Exercise exercise) {
    setState(() {
      _workout = _workout.copyWith(
        exercises:
            _workout.exercises.where((e) => e.id != exercise.id).toList(),
        supersets: removeExerciseFromSupersets(exercise.id, _workout.supersets),
      );
    });
  }

  // ── Superset management ─────────────────────────────────────────────────

  SupersetConfig? _supersetForExercise(Exercise exercise) =>
      supersetForExercise(_workout, exercise.id);

  int? _supersetIndexForExercise(Exercise exercise) {
    for (var i = 0; i < _workout.supersets.length; i++) {
      if (_workout.supersets[i].exerciseIds.contains(exercise.id)) return i;
    }
    return null;
  }

  Future<void> _onSupersetSlidableTap(Exercise exercise) async {
    final ss = _supersetForExercise(exercise);
    if (ss != null) {
      await _editSuperset(ss);
    } else {
      await _addToSuperset(exercise);
    }
  }

  Future<void> _addToSuperset(Exercise exercise) async {
    final supersets = _workout.supersets;
    if (supersets.isEmpty) {
      await _openCreateModal(initialExercise: exercise);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        100,
        200,
        100,
        box == null ? 200 : box.size.height - 200,
      ),
      items: [
        for (var i = 0; i < supersets.length; i++)
          PopupMenuItem<String>(
            value: supersets[i].id,
            child: Row(children: [
              Container(
                  width: 4, height: 24, color: supersetColorForIndex(i)),
              const SizedBox(width: 8),
              Text(_supersetMenuLabel(supersets[i], exercise)),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__new__',
          child: Text('Create new superset'),
        ),
      ],
    );
    if (picked == null) return;
    if (picked == '__new__') {
      await _openCreateModal(initialExercise: exercise);
    } else {
      final existing = supersets.firstWhere((s) => s.id == picked);
      await _editSuperset(existing, joining: exercise);
    }
  }

  String _supersetMenuLabel(SupersetConfig ss, Exercise fallbackExercise) {
    final firstId = ss.exerciseIds.first;
    final firstTitle = _workout.exercises
        .firstWhere(
          (e) => e.id == firstId,
          orElse: () => fallbackExercise,
        )
        .title;
    return '${ss.exerciseIds.length} exercises: $firstTitle';
  }

  Future<void> _openCreateModal({required Exercise initialExercise}) async {
    final result = await showSupersetModal(
      context: context,
      workoutExercises: _workout.exercises,
      otherSupersets: _workout.supersets,
      initialMembers: [initialExercise],
      existing: null,
    );
    if (result == null || result.dissolveRequested) return;
    if (result.memberIds.length < 2) return;

    final newSs = SupersetConfig(
      exerciseIds: result.memberIds,
      restSeconds: result.restSeconds,
      supersetSets: result.supersetSets,
    );
    setState(() {
      _workout = _workout.copyWith(
        exercises:
            _reorderToContiguous(_workout.exercises, result.memberIds),
        supersets: [..._workout.supersets, newSs],
      );
    });
  }

  Future<void> _editSuperset(SupersetConfig ss, {Exercise? joining}) async {
    final initialMembers = _workout.exercises
        .where((e) => ss.exerciseIds.contains(e.id))
        .toList();
    if (joining != null && !initialMembers.any((m) => m.id == joining.id)) {
      initialMembers.add(joining);
    }
    final otherSupersets =
        _workout.supersets.where((s) => s.id != ss.id).toList();
    final result = await showSupersetModal(
      context: context,
      workoutExercises: _workout.exercises,
      otherSupersets: otherSupersets,
      initialMembers: initialMembers,
      existing: ss,
      joiningExercise: joining,
    );
    if (result == null) return;

    if (result.dissolveRequested || result.memberIds.length < 2) {
      setState(() {
        _workout = _workout.copyWith(
          supersets:
              _workout.supersets.where((s) => s.id != ss.id).toList(),
        );
      });
      return;
    }

    final updated = ss.copyWith(
      exerciseIds: result.memberIds,
      restSeconds: result.restSeconds,
      supersetSets: result.supersetSets,
    );
    setState(() {
      _workout = _workout.copyWith(
        exercises:
            _reorderToContiguous(_workout.exercises, result.memberIds),
        supersets: _workout.supersets
            .map((s) => s.id == ss.id ? updated : s)
            .toList(),
      );
    });
  }

  /// Reorder handler for the workout list. Solo exercises move single-item.
  /// Superset members drag the entire block as a unit. Drops that would
  /// break a superset's contiguity (placing a solo exercise inside a block,
  /// or placing one block inside another) snap back with a snackbar.
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;

      final exercises = List<Exercise>.from(_workout.exercises);
      final dragged = exercises[oldIndex];
      final draggedSuperset = supersetForExercise(_workout, dragged.id);

      if (draggedSuperset == null) {
        final candidate = List<Exercise>.from(exercises)
          ..removeAt(oldIndex)
          ..insert(newIndex, dragged);
        if (!supersetsRemainContiguous(candidate, _workout.supersets)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot drop inside a superset')),
          );
          return;
        }
        _workout = _workout.copyWith(exercises: candidate);
        return;
      }

      // Whole-block drag: extract every member of the dragged superset and
      // re-insert them as a contiguous block at the target position.
      final memberIds = draggedSuperset.exerciseIds.toSet();
      final blockIndices = <int>[];
      for (var i = 0; i < exercises.length; i++) {
        if (memberIds.contains(exercises[i].id)) blockIndices.add(i);
      }
      final blockStart = blockIndices.first;
      final blockEnd = blockIndices.last;
      final blockExercises = exercises.sublist(blockStart, blockEnd + 1);
      final remainder = [
        ...exercises.sublist(0, blockStart),
        ...exercises.sublist(blockEnd + 1),
      ];
      int targetInRemainder;
      if (newIndex <= blockStart) {
        targetInRemainder = newIndex;
      } else if (newIndex > blockEnd) {
        targetInRemainder = newIndex - blockExercises.length;
      } else {
        // Drop landed inside the block itself — no-op (a block can't move
        // into itself).
        return;
      }
      targetInRemainder = targetInRemainder.clamp(0, remainder.length);

      final candidate = List<Exercise>.from(remainder)
        ..insertAll(targetInRemainder, blockExercises);

      if (!supersetsRemainContiguous(candidate, _workout.supersets)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot drop inside another superset')),
        );
        return;
      }
      _workout = _workout.copyWith(exercises: candidate);
    });
  }

  /// Pulls all members listed in [memberIds] to be contiguous in the exercise
  /// list, anchored at the position of the first member already in the list.
  /// Members are placed in the modal-defined order.
  List<Exercise> _reorderToContiguous(
      List<Exercise> exercises, List<String> memberIds) {
    if (memberIds.length < 2) return exercises;
    final memberSet = memberIds.toSet();
    final firstAnchor = exercises.indexWhere((e) => memberSet.contains(e.id));
    if (firstAnchor == -1) return exercises;
    final members = <Exercise>[];
    final others = <Exercise>[];
    for (final e in exercises) {
      if (memberSet.contains(e.id)) {
        members.add(e);
      } else {
        others.add(e);
      }
    }
    members.sort(
        (a, b) => memberIds.indexOf(a.id).compareTo(memberIds.indexOf(b.id)));
    final insertAt = exercises
        .sublist(0, firstAnchor)
        .where((e) => !memberSet.contains(e.id))
        .length;
    return [...others]..insertAll(insertAt, members);
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    final Set<String> existingExerciseIds = {};

    if (workout.exercises.isNotEmpty) {
      for (var i = 0; i < workout.exercises.length; i++) {
        existingExerciseIds.add(workout.exercises[i].id);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox.shrink(),
            Text(_isNew ? 'New workout' : 'Edit workout'),
            ElevatedButton(
              onPressed: _save,
              style: ButtonStyle().copyWith(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
              child: Text('Save'),
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
                      maxLength: FieldLimits.workoutTitleMaxLength,
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
                        return FieldValidators.workoutTitle(
                          v,
                          existingTitles: presetProvider.presetWorkouts.map((w) => w.title).toList(),
                          ownTitle: widget.workout?.title,
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
                      maxLength: FieldLimits.workoutDescriptionMaxLength,
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
                      validator: FieldValidators.workoutDescription,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              workout.exercises.isEmpty
                  ? Expanded(
                    child: Center(
                      child: Text(
                        'No exercises yet',
                        style: context.bodyMedium.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                  : Expanded(
                    child: ReorderableListView.builder(
                      padding: EdgeInsets.only(top: 4, bottom: 16),
                      itemCount: workout.exercises.length,
                      itemBuilder: (BuildContext context, int index) {
                        final exercise = workout.exercises[index];
                        final pp = Provider.of<PresetProvider>(context, listen: false);
                        final notInCatalog = pp.presetExercises.every((e) => e.id != exercise.id);
                        final notInTrash = pp.trashedItems.every((e) => e.id != exercise.id);
                        final paletteIndex = _supersetIndexForExercise(exercise);
                        final ss = _supersetForExercise(exercise);
                        return _ExerciseCard(
                          exercise: exercise,
                          key: ValueKey(
                            '$index-${exercise.id}',
                          ), // prefix index to exercise.id to allow multiple instances of same exercise in the reorderable list
                          onCopy: () => _copyExercise(exercise),
                          onDelete: () => _deleteExercise(exercise),
                          onSuperset: () => _onSupersetSlidableTap(exercise),
                          onSaveToCatalog: (notInCatalog && notInTrash)
                              ? () => _saveExerciseToCatalog(exercise)
                              : null,
                          supersetPaletteIndex: paletteIndex,
                          supersetSets: ss?.supersetSets,
                          onTap: () async {
                            final result =
                                await Navigator.push<NewExerciseResult>(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => NewExerciseScreen(
                                          exercise: exercise,
                                          parentWorkout: _workout,
                                        ),
                                  ),
                                );
                            if (result == null) return;
                            setState(() {
                              _workout.exercises[index] = result.exercise;
                              if (result.supersetSetsChange != null) {
                                _workout = _workout.copyWith(
                                  supersets: _workout.supersets
                                      .map(
                                        (ss) => ss.exerciseIds
                                                .contains(result.exercise.id)
                                            ? ss.copyWith(
                                                supersetSets:
                                                    result.supersetSetsChange,
                                              )
                                            : ss,
                                      )
                                      .toList(),
                                );
                              }
                            });
                            // Track the exercise change so Save can propagate it.
                            // Copies (from _copyExercise) are brand-new ids with
                            // no existing consumers, so they are never added here.
                            _pending.addExercise(result.exercise);
                          },
                        );
                      },
                      onReorder: _onReorder,
                      proxyDecorator: (child, index, animation) {
                        final exercise = _workout.exercises[index];
                        final ss = _supersetForExercise(exercise);
                        if (ss == null) return child;
                        final siblingCount = ss.exerciseIds.length - 1;
                        return Material(
                          color: Colors.transparent,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (var i = siblingCount; i > 0; i--)
                                Positioned(
                                  top: i * 4.0,
                                  left: i * 2.0,
                                  right: i * 2.0,
                                  child: Container(
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: context.colorScheme.surface,
                                      border: Border.all(
                                        color: context.colorScheme.outline
                                            .withValues(alpha: 0.3),
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.05),
                                          blurRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              child,
                            ],
                          ),
                        );
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          List<Exercise>? newExercises = await Navigator.push(
            context,
            MaterialPageRoute<List<Exercise>>(
              builder:
                  (context) => AddItemScreen(
                    itemType: ItemType.exercises,
                    existingItemIds: existingExerciseIds,
                  ),
            ),
          );

          if (newExercises != null && newExercises.isNotEmpty) {
            setState(() {
              _workout = _workout.copyWith(
                exercises: [..._workout.exercises, ...newExercises],
              );
            });
          }
        },

        child: Icon(Icons.add),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onSuperset;

  /// When non-null, a "Save to catalog" slidable action is shown. Null means
  /// the action is hidden (the exercise is already in the catalog or in trash).
  final VoidCallback? onSaveToCatalog;

  /// Non-null when the exercise is a member of a superset. Drives the leading
  /// color bar and the slidable label ("Edit superset" vs "Add to superset").
  final int? supersetPaletteIndex;

  /// When non-null, the displayed sets value is overridden by the superset's
  /// supersetSets — so members of a superset show the shared count.
  final int? supersetSets;

  const _ExerciseCard({
    super.key,
    required this.exercise,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
    required this.onSuperset,
    this.onSaveToCatalog,
    this.supersetPaletteIndex,
    this.supersetSets,
  });

  @override
  Widget build(BuildContext context) {
    final saveVisible = onSaveToCatalog != null;
    return GestureDetector(
      onTap: onTap,
      child: Slidable(
        key: ValueKey(exercise.id),
        // Left-to-right swipe — additive actions (Save, Copy).
        startActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.22 * (saveVisible ? 2 : 1),
          children: [
            if (saveVisible)
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (_) => onSaveToCatalog!(),
                backgroundColor: context.colorScheme.tertiary,
                foregroundColor: context.colorScheme.onTertiary,
                icon: Icons.save_alt_rounded,
                label: 'Save to\ncatalog',
              ),
            SlidableAction(
              borderRadius: BorderRadius.circular(12),
              onPressed: (_) => onCopy(),
              backgroundColor: context.colorScheme.secondary,
              foregroundColor: context.colorScheme.onSecondary,
              icon: Icons.copy_rounded,
              label: 'Copy',
            ),
          ],
        ),
        // Right-to-left swipe — modifying / destructive actions.
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.22 * 2,
          children: [
            SlidableAction(
              borderRadius: BorderRadius.circular(12),
              onPressed: (_) => onSuperset(),
              backgroundColor: context.colorScheme.tertiary,
              foregroundColor: context.colorScheme.onTertiary,
              icon: supersetPaletteIndex != null
                  ? Icons.edit_rounded
                  : Icons.link_rounded,
              label: supersetPaletteIndex != null
                  ? 'Edit\nsuperset'
                  : 'Add to\nsuperset',
            ),
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
        child: _cardBody(context),
      ),
    );
  }

  Widget _cardBody(BuildContext context) {
    final body = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
        boxShadow: context.shadowSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(exercise.title, style: context.titleMedium),
              _LabelBadge(labelKey: exercise.label),
            ],
          ),
          if (exercise.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              exercise.description,
              style: context.bodyMedium.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _StatPill(label: 'Sets', value: '${supersetSets ?? exercise.sets}'),
              if (exercise.reps != null)
                _StatPill(label: 'Reps', value: '${exercise.reps}'),
              if (exercise.load > 0)
                _StatPill(
                  label: 'Load',
                  value: exercise.loadUnit != null
                      ? '${exercise.load} ${exercise.loadUnit}'
                      : '${exercise.load}',
                ),
              _StatPill(
                label: 'Rest',
                value: '${exercise.timeBetweenSets}s',
              ),
              _StatPill(
                label: 'Active',
                value: switch (exercise.type) {
                  ExerciseType.timedReps =>
                    '${exercise.timePerRep * (exercise.reps ?? 1)}s',
                  ExerciseType.fixedDuration => '${exercise.activeTime}s',
                  ExerciseType.manual => '-',
                },
              ),
            ],
          ),
        ],
      ),
    );
    if (supersetPaletteIndex == null) return body;
    return Stack(
      children: [
        body,
        Positioned(
          left: 0,
          top: 0,
          bottom: 8,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: supersetColorForIndex(supersetPaletteIndex!),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: context.bodyMedium.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: context.bodyMedium),
      ],
    );
  }
}

class _LabelBadge extends StatelessWidget {
  final String labelKey;
  const _LabelBadge({required this.labelKey});

  @override
  Widget build(BuildContext context) {
    final label = kDefaultLabels[labelKey];
    if (label == null) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: label.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(label.icon, size: 12, color: label.color),
          SizedBox(width: 4),
          Text(
            label.name,
            style: context.bodyMedium.copyWith(
              color: label.color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
