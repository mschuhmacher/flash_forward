import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/core/nullable.dart';
import 'package:flash_forward/core/superset_utils.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/superset_modal.dart';
import 'package:flash_forward/presentation/widgets/auth_wall.dart';
import 'package:flash_forward/presentation/widgets/group_form_card.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/presentation/widgets/unsaved_changes_dialog.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/catalog/edit_commit_controller.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class NewWorkoutScreen extends StatefulWidget {
  final Workout? workout;

  /// When true, saving will persist the workout to [CatalogProvider] (add or
  /// update). Use this when opening the screen standalone (e.g. from the FAB
  /// or catalog). Leave false when used as a sub-editor inside another form
  /// (e.g. editing a workout within a session).
  final bool persistToProvider;

  const NewWorkoutScreen({
    super.key,
    this.workout,
    this.persistToProvider = false,
  });

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

  // Captured once so dirty-check has a stable baseline. Empty map for new workouts
  // so any input immediately reads as dirty.
  late final Map<String, dynamic> _initialSnapshot =
      widget.workout?.toJson() ?? {};

  bool get _isDirty {
    if (_titleController.text.trim() != (widget.workout?.title ?? ''))
      return true;
    if (_itemLabelController.text != (widget.workout?.label ?? '')) return true;
    if (_descriptionController.text.trim() !=
        (widget.workout?.description ?? ''))
      return true;
    final initialRest = widget.workout?.timeBetweenExercises ?? 120;
    if (_timeBetweenExercises != initialRest) return true;
    final initialExercises = _initialSnapshot['exercises'];
    final currentExercises = _workout.toJson()['exercises'];
    return initialExercises.toString() != currentExercises.toString();
  }

  /// Accumulates exercise edits made via nested NewExerciseScreen drilldowns.
  /// Flushed to the provider on Save (standalone) or returned to the parent (nested).
  final PendingChangeBag _pending = PendingChangeBag();

  /// While the user is dragging an exercise that belongs to a superset, this
  /// holds that superset's id; the other members of the same superset fade
  /// to invisible to communicate "the whole block moves together." Null when
  /// no drag is active or when a solo exercise is being dragged.
  String? _draggingSupersetId;
  int? _draggingExerciseIndex;

  late final _titleController = TextEditingController(
    text: widget.workout?.title,
  );
  late final _itemLabelController = TextEditingController(
    text: widget.workout?.label,
  );
  late final _descriptionController = TextEditingController(
    text: widget.workout?.description,
  );
  late int _timeBetweenExercises = widget.workout?.timeBetweenExercises ?? 120;

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
          content: Text('A superset is broken — please re-create it'),
        ),
      );
      return;
    }
    if (_workout.exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one exercise before saving.'),
        ),
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
        timeBetweenExercises: _timeBetweenExercises,
        userId:
            _workout.userId ??
            Provider.of<AuthProvider>(context, listen: false).userId,
      );
      if (widget.persistToProvider) {
        // Gate only the persisting path; a nested editor never gates.
        final allowed = await requireAuth(
          context,
          message: 'save workouts to your catalog',
        );
        if (!allowed || !mounted) return;

        final catalogProvider = Provider.of<CatalogProvider>(
          context,
          listen: false,
        );

        if (_isNew) {
          await catalogProvider.upsertWorkout(workout);
        } else {
          final editCommit = context.read<EditCommitController>();
          final bag = PendingChangeBag()..addWorkout(workout);
          for (final ec in _pending.exercisesById.values) {
            bag.addExercise(ec.exercise);
          }
          // excludeWorkoutId filters the parent workout out of each exercise's
          // affected-workouts list — those edits ride along with the workout
          // commit and don't need a separate propagation entry.
          final result = await editCommit.commitChanges(
            bag,
            excludeWorkoutId: workout.id,
          );

          if (result.hasAny && mounted) {
            final sections = <PropagationSection>[
              for (final entry in result.affectedSessionsByWorkoutId.entries)
                PropagationSection(
                  itemKind: 'workout',
                  itemId: entry.key,
                  itemTitle: workout.title,
                  consumerKind: 'sessions',
                  consumers: [
                    for (final s in entry.value)
                      PropagationConsumer(id: s.id, label: s.title),
                  ],
                ),
              for (final entry in result.affectedWorkoutsByExerciseId.entries)
                PropagationSection(
                  itemKind: 'exercise',
                  itemId: entry.key,
                  itemTitle: bag.exercisesById[entry.key]!.exercise.title,
                  consumerKind: 'workouts',
                  consumers: [
                    for (final w in entry.value)
                      PropagationConsumer(id: w.id, label: w.title),
                  ],
                ),
            ];
            final selection = await showPropagateChangesDialog(
              context: context,
              sections: sections,
            );
            if (selection == null) return; // user cancelled — stay on screen
            if (!selection.isEmpty) {
              await editCommit.propagateBag(bag, selection: selection);
            }
          }
        }
      }
      if (mounted) {
        Navigator.pop(context, (workout: workout, pending: _pending));
      }
    }
  }

  Future<void> _saveExerciseToCatalog(Exercise exercise) async {
    final catalog = Provider.of<CatalogProvider>(context, listen: false);
    final titles = catalog.presetExercises.map((e) => e.title).toList();
    String? finalTitle = exercise.title;
    if (titles.contains(exercise.title)) {
      finalTitle = await showRenameOnCollisionDialog(
        context: context,
        currentTitle: exercise.title,
        existingTitles: titles,
      );
      if (finalTitle == null) return;
    }
    final toSave =
        finalTitle == exercise.title
            ? exercise
            : exercise.copyWith(title: finalTitle);
    await catalog.upsertExercise(toSave);
    
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved to catalog')));
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
    final picked = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add to superset'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < supersets.length; i++)
                    ListTile(
                      dense: true,
                      leading: Container(
                        width: 4,
                        height: 24,
                        color: supersetColorForIndex(i),
                      ),
                      title: Text(_supersetMenuLabel(supersets[i], exercise)),
                      onTap: () => Navigator.of(ctx).pop(supersets[i].id),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_link_rounded),
                    title: const Text('Create new superset'),
                    onTap: () => Navigator.of(ctx).pop('__new__'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
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
    final firstTitle =
        _workout.exercises
            .firstWhere((e) => e.id == firstId, orElse: () => fallbackExercise)
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
      supersetSetRest: result.supersetSetRest,
    );
    setState(() {
      _workout = _workout.copyWith(
        exercises: _reorderToContiguous(_workout.exercises, result.memberIds),
        supersets: [..._workout.supersets, newSs],
      );
    });
  }

  Future<void> _editSuperset(SupersetConfig ss, {Exercise? joining}) async {
    final initialMembers =
        _workout.exercises.where((e) => ss.exerciseIds.contains(e.id)).toList();
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
    );
    if (result == null) return;

    if (result.dissolveRequested || result.memberIds.length < 2) {
      setState(() {
        _workout = _workout.copyWith(
          supersets: _workout.supersets.where((s) => s.id != ss.id).toList(),
        );
      });
      return;
    }

    final updated = ss.copyWith(
      exerciseIds: result.memberIds,
      restSeconds: result.restSeconds,
      supersetSets: result.supersetSets,
      supersetSetRest: result.supersetSetRest,
    );
    setState(() {
      _workout = _workout.copyWith(
        exercises: _reorderToContiguous(_workout.exercises, result.memberIds),
        supersets:
            _workout.supersets.map((s) => s.id == ss.id ? updated : s).toList(),
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
        final candidate =
            List<Exercise>.from(exercises)
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
      // Translating the post-`-= 1` newIndex (computed by Flutter as if a
      // single item had been removed at oldIndex) into a target index in
      // the remainder list (with the *whole block* removed). For positions
      // before the block, indices match. For positions past the block end,
      // Flutter's single-item-removed view shifts every item down by 1; the
      // block-removed view shifts them down by `blockExercises.length`, so
      // we subtract the difference plus one (the +1 because newIndex past
      // blockEnd in the single-item view points at the slot AFTER the
      // dragged item's original neighbor in the remainder).
      int targetInRemainder;
      if (newIndex <= blockStart) {
        targetInRemainder = newIndex;
      } else if (newIndex > blockEnd) {
        targetInRemainder = newIndex - blockExercises.length + 1;
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

  /// Shallow value-equal comparison for two JSON-shaped maps. Used to detect
  /// whether an Exercise edit actually changed anything before tracking it
  /// for propagation. List-typed fields (e.g. exercises) compare by element.
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      final av = entry.value;
      final bv = b[entry.key];
      if (av is List && bv is List) {
        if (av.length != bv.length) return false;
        for (var i = 0; i < av.length; i++) {
          if (av[i] != bv[i]) return false;
        }
      } else if (av != bv) {
        return false;
      }
    }
    return true;
  }

  /// Pulls all members listed in [memberIds] to be contiguous in the exercise
  /// list, anchored at the position of the first member already in the list.
  /// Members are placed in the modal-defined order.
  List<Exercise> _reorderToContiguous(
    List<Exercise> exercises,
    List<String> memberIds,
  ) {
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
      (a, b) => memberIds.indexOf(a.id).compareTo(memberIds.indexOf(b.id)),
    );
    final insertAt =
        exercises
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_isDirty) {
          Navigator.of(context).pop();
          return;
        }
        final choice = await showUnsavedChangesDialog(context);
        if (choice == null) return;
        if (choice) {
          await _save();
        } else {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
                GroupFormCard(
                  children: [
                    GroupFormRow(
                      label: 'Title',
                      trailing: GroupFormCounter(
                        current: _titleController.text.length,
                        max: FieldLimits.workoutTitleMaxLength,
                      ),
                      child: TextFormField(
                        controller: _titleController,
                        maxLength: FieldLimits.workoutTitleMaxLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        validator: (v) {
                          final catalogProvider = Provider.of<CatalogProvider>(
                            context,
                            listen: false,
                          );
                          return FieldValidators.workoutTitle(
                            v,
                            existingTitles:
                                catalogProvider.presetWorkouts
                                    .map((w) => w.title)
                                    .toList(),
                            ownTitle: widget.workout?.title,
                          );
                        },
                      ),
                    ),
                    GroupFormRow(
                      label: 'Label',
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
                        flat: true,
                      ),
                    ),
                    GroupFormRow(
                      label: 'Info',
                      trailing: GroupFormCounter(
                        current: _descriptionController.text.length,
                        max: FieldLimits.workoutDescriptionMaxLength,
                      ),
                      child: TextFormField(
                        controller: _descriptionController,
                        maxLength: FieldLimits.workoutDescriptionMaxLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        maxLines: null,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        validator: FieldValidators.workoutDescription,
                      ),
                    ),
                    GroupFormRestRow(
                      label: 'Rest between exercises',
                      value: _timeBetweenExercises,
                      minimum: 0,
                      maximum: FieldLimits.timeLimit,
                      onDecrement:
                          () => setState(
                            () =>
                                _timeBetweenExercises = (_timeBetweenExercises -
                                        5)
                                    .clamp(0, FieldLimits.timeLimit),
                          ),
                      onIncrement:
                          () => setState(
                            () =>
                                _timeBetweenExercises = (_timeBetweenExercises +
                                        5)
                                    .clamp(0, FieldLimits.timeLimit),
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
                          final catalogProvider = Provider.of<CatalogProvider>(
                            context,
                            listen: false,
                          );
                          final trash = context.read<TrashProvider>();
                          final notInCatalog = catalogProvider.presetExercises
                              .every((e) => e.id != exercise.id);
                          final notInTrash = trash.trashedItems.every(
                            (e) => e.id != exercise.id,
                          );
                          final paletteIndex = _supersetIndexForExercise(
                            exercise,
                          );
                          final superset = _supersetForExercise(exercise);
                          // While dragging a superset member, fade the OTHER
                          // members of the same block so the user reads the
                          // dragged card (with its peek-stack proxy) as
                          // representing the whole group.
                          final fadeSibling =
                              _draggingSupersetId != null &&
                              superset?.id == _draggingSupersetId &&
                              index != _draggingExerciseIndex;
                          final card = _ExerciseCard(
                            exercise: exercise,
                            onCopy: () => _copyExercise(exercise),
                            onDelete: () => _deleteExercise(exercise),
                            onSuperset: () => _onSupersetSlidableTap(exercise),
                            onSaveToCatalog:
                                (notInCatalog && notInTrash)
                                    ? () => _saveExerciseToCatalog(exercise)
                                    : null,
                            supersetPaletteIndex: paletteIndex,
                            supersetSets: superset?.supersetSets,
                            supersetSetRest: superset?.supersetSetRest,
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
                                    supersets:
                                        _workout.supersets
                                            .map(
                                              (ss) =>
                                                  ss.exerciseIds.contains(
                                                        result.exercise.id,
                                                      )
                                                      ? ss.copyWith(
                                                        supersetSets:
                                                            result
                                                                .supersetSetsChange,
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
                              // Skip when nothing actually changed — avoids
                              // spurious propagation prompts on no-op edits.
                              final changed =
                                  !_mapsEqual(
                                    exercise.toJson(),
                                    result.exercise.toJson(),
                                  );
                              if (changed ||
                                  result.supersetSetsChange != null) {
                                _pending.addExercise(result.exercise);
                              }
                            },
                          );
                          return KeyedSubtree(
                            // Keep the same key contract on the outer widget
                            // so ReorderableListView identifies items
                            // consistently across rebuilds.
                            key: ValueKey('$index-${exercise.id}'),
                            child: AnimatedOpacity(
                              opacity: fadeSibling ? 0.2 : 1.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: card,
                            ),
                          );
                        },
                        onReorder: _onReorder,
                        onReorderStart: (index) {
                          final exercise = _workout.exercises[index];
                          final ss = _supersetForExercise(exercise);
                          setState(() {
                            _draggingSupersetId = ss?.id;
                            _draggingExerciseIndex = index;
                          });
                        },
                        onReorderEnd: (_) {
                          setState(() {
                            _draggingSupersetId = null;
                            _draggingExerciseIndex = null;
                          });
                        },
                        proxyDecorator: (child, index, animation) {
                          final exercise = _workout.exercises[index];
                          final ss = _supersetForExercise(exercise);
                          if (ss == null) return child;
                          // Cap visible stack edges so very large supersets
                          // don't render an unwieldy tower of peeks.
                          final siblingCount = (ss.exerciseIds.length - 1)
                              .clamp(0, 3);
                          // Peeks render BELOW the lifted card via negative
                          // `bottom` + Clip.none, fanning out from underneath.
                          // Stack with no `bottom` clipping means hit-test
                          // bounds equal the card's intrinsic size.
                          return Material(
                            color: Colors.transparent,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (var i = siblingCount; i > 0; i--)
                                  Positioned(
                                    bottom: -i * 4.0,
                                    left: i * 3.0,
                                    right: i * 3.0,
                                    child: Container(
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color:
                                            context.colorScheme.surfaceBright,
                                        border: Border.all(
                                          color: context.colorScheme.outline
                                              .withValues(alpha: 0.3),
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.08,
                                            ),
                                            blurRadius: 3,
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

  /// When non-null, the displayed Rest value is overridden by the superset's
  /// supersetSetRest (between-rounds rest). Members of a superset show the
  /// shared between-rounds value rather than the underlying exercise's
  /// `timeBetweenSets`.
  final int? supersetSetRest;

  const _ExerciseCard({
    required this.exercise,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
    required this.onSuperset,
    this.onSaveToCatalog,
    this.supersetPaletteIndex,
    this.supersetSets,
    this.supersetSetRest,
  });

  @override
  Widget build(BuildContext context) {
    final saveVisible = onSaveToCatalog != null;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
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
              SizedBox(width: 4),
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (_) => onCopy(),
                backgroundColor: context.colorScheme.secondary,
                foregroundColor: context.colorScheme.onSecondary,
                icon: Icons.copy_rounded,
                label: 'Copy',
              ),
              SizedBox(width: 4),
            ],
          ),
          // Right-to-left swipe — modifying / destructive actions.
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.22 * 2,
            children: [
              SizedBox(width: 4),
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (_) => onSuperset(),
                backgroundColor:
                    supersetPaletteIndex != null
                        ? supersetColorForIndex(supersetPaletteIndex!)
                        : kDefaultLabels[exercise.label]?.color ??
                            context.colorScheme.secondary,
                foregroundColor: context.colorScheme.onPrimary,
                icon:
                    supersetPaletteIndex != null
                        ? Icons.edit_rounded
                        : Icons.link_rounded,
                label:
                    supersetPaletteIndex != null
                        ? 'Edit\nsuperset'
                        : 'Add to\nsuperset',
              ),
              SizedBox(width: 4),
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (_) => onDelete(),
                backgroundColor: context.colorScheme.error,
                foregroundColor: context.colorScheme.onError,
                icon: Icons.delete_rounded,
                label: 'Delete',
              ),
              SizedBox(width: 4),
            ],
          ),
          child: _cardBody(context),
        ),
      ),
    );
  }

  Widget _cardBody(BuildContext context) {
    final supersetColor =
        supersetPaletteIndex != null
            ? supersetColorForIndex(supersetPaletteIndex!)
            : null;
    final content = Padding(
      padding: EdgeInsets.only(
        left: supersetColor != null ? 10 : 14,
        right: 14,
        top: 14,
        bottom: 14,
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
              _StatPill(
                label: 'Sets',
                value: '${supersetSets ?? exercise.sets}',
              ),
              if (exercise.reps != null)
                _StatPill(label: 'Reps', value: '${exercise.reps}'),
              if (exercise.load > 0)
                _StatPill(
                  label: 'Load',
                  value:
                      exercise.loadUnit != null
                          ? '${exercise.load} ${exercise.loadUnit}'
                          : '${exercise.load}',
                ),
              _StatPill(
                label: 'Rest',
                value: '${supersetSetRest ?? exercise.timeBetweenSets}s',
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

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
        boxShadow: context.shadowSmall,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child:
            supersetColor != null
                ? Stack(
                  children: [
                    content,
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 4, color: supersetColor),
                    ),
                  ],
                )
                : content,
      ),
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
