import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/catalog_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/widgets/auth_wall.dart';
import 'package:flash_forward/presentation/widgets/group_form_card.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/presentation/widgets/rename_on_collision_dialog.dart';
import 'package:flash_forward/presentation/widgets/unsaved_changes_dialog.dart';
import 'package:flash_forward/presentation/widgets/workout_card.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/catalog/edit_commit_controller.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/features/catalog/trash_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/features/session_active/session_state_provider.dart';
import 'package:flash_forward/core/nullable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

enum NewSessionScreenMode { create, editCatalog, editBeforeStart, editActive }

class NewSessionScreen extends StatefulWidget {
  final Session? session;
  final NewSessionScreenMode mode;
  // Required when mode == editBeforeStart. Called with the built session
  // so the callsite can push ActiveSessionScreen (avoids circular import).
  final void Function(Session)? onSaveAndStart;

  const NewSessionScreen({
    super.key,
    this.session,
    this.mode = NewSessionScreenMode.create,
    this.onSaveAndStart,
  });

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get _isNew => widget.mode == NewSessionScreenMode.create;

  late Session _session =
      widget.session?.deepCopy(keepId: true) ??
      Session(title: 'title', label: 'label', workouts: []);

  // Captured once at build time so dirty-check has a stable baseline.
  // New sessions have no widget.session, so the snapshot is empty — any
  // input will immediately read as dirty.
  late final Map<String, dynamic> _initialSnapshot =
      widget.session?.toJson() ?? {};

  bool get _isDirty {
    if (_titleController.text.trim() != (widget.session?.title ?? ''))
      return true;
    if (_itemLabelController.text != (widget.session?.label ?? '')) return true;
    if (_descriptionController.text.trim() !=
        (widget.session?.description ?? ''))
      return true;
    final initialWorkouts = _initialSnapshot['workouts'];
    final currentWorkouts = _session.toJson()['workouts'];
    return initialWorkouts.toString() != currentWorkouts.toString();
  }

  /// Accumulates workout and exercise edits from nested drilldowns.
  /// Flushed to the provider on Save via CatalogProvider.commitChanges.
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
    if (_session.workouts.isEmpty ||
        _session.workouts.any((w) => w.exercises.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Every workout must have at least one exercise before saving.',
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

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

    switch (widget.mode) {
      case NewSessionScreenMode.editActive:
        return _saveActiveEdit(session);
      case NewSessionScreenMode.editBeforeStart:
        return _saveAndStart(session);
      case NewSessionScreenMode.create:
      case NewSessionScreenMode.editCatalog:
        return _saveToCatalog(session);
    }
  }

  Future<void> _saveActiveEdit(Session session) async {
    context.read<SessionStateProvider>().replaceActiveSession(session);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveAndStart(Session session) async {
    if (mounted) widget.onSaveAndStart?.call(session);
  }

  Future<void> _saveToCatalog(Session session) async {
    // Reached only for create / editCatalog — both persist, so gate here.
    final allowed = await requireAuth(
      context,
      message: 'save sessions to your catalog',
    );
    if (!allowed || !mounted) return;

    final catalogProvider = Provider.of<CatalogProvider>(
      context,
      listen: false,
    );

    if (_isNew) {
      await catalogProvider.upsertSession(session);
    } else {
      final editCommit = context.read<EditCommitController>();
      final bag = PendingChangeBag()..setSession(session);
      for (final wc in _pending.workoutsById.values) {
        bag.addWorkout(wc.workout);
      }
      for (final ec in _pending.exercisesById.values) {
        bag.addExercise(ec.exercise);
      }
      final result = await editCommit.commitChanges(
        bag,
        excludeSessionId: session.id,
      );
      if (result.hasAny && mounted) {
        final sections = <PropagationSection>[
          for (final entry in result.affectedSessionsByWorkoutId.entries)
            PropagationSection(
              itemKind: 'workout',
              itemId: entry.key,
              itemTitle: bag.workoutsById[entry.key]!.workout.title,
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
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveWorkoutToCatalog(Workout workout) async {
    if (workout.exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one exercise before saving to catalog.'),
        ),
      );
      return;
    }
    final allowed = await requireAuth(
      context,
      message: 'save workouts to your catalog',
    );
    if (!allowed || !mounted) return;

    final catalog = Provider.of<CatalogProvider>(context, listen: false);
    final titles = catalog.presetWorkouts.map((w) => w.title).toList();
    String? finalTitle = workout.title;
    if (titles.contains(workout.title)) {
      finalTitle = await showRenameOnCollisionDialog(
        context: context,
        currentTitle: workout.title,
        existingTitles: titles,
      );
      if (finalTitle == null) return;
    }
    final toSave =
        finalTitle == workout.title
            ? workout
            : workout.copyWith(title: finalTitle);
    await catalog.upsertWorkout(toSave);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved to catalog')));
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_isDirty) {
          Navigator.of(context).pop();
          return;
        }
        final choice = await showUnsavedChangesDialog(context);
        if (choice == null) return; // cancelled — stay
        if (choice) {
          await _save(); // save then pops internally
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
              Text(_isNew ? 'New session' : 'Edit session'),
              ElevatedButton(
                onPressed: _save,
                style: ButtonStyle().copyWith(
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  ),
                ),
                child: Text(widget.mode == NewSessionScreenMode.editBeforeStart ? 'Save & Start' : 'Save'),
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
                        max: FieldLimits.sessionTitleMaxLength,
                      ),
                      child: TextFormField(
                        controller: _titleController,
                        maxLength: FieldLimits.sessionTitleMaxLength,
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
                          return FieldValidators.sessionTitle(
                            v,
                            existingTitles:
                                catalogProvider.presetSessions
                                    .map((s) => s.title)
                                    .toList(),
                            ownTitle: widget.session?.title,
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
                        max: FieldLimits.sessionDescriptionMaxLength,
                      ),
                      child: TextFormField(
                        controller: _descriptionController,
                        maxLength: FieldLimits.sessionDescriptionMaxLength,
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
                          final pp = Provider.of<CatalogProvider>(
                            context,
                            listen: false,
                          );
                          final trash = context.read<TrashProvider>();
                          final notInCatalog = pp.presetWorkouts.every(
                            (w) => w.id != workout.id,
                          );
                          final notInTrash = trash.trashedItems.every(
                            (e) => e.id != workout.id,
                          );
                          return _WorkoutCard(
                            workout: workout,
                            key: ValueKey(
                              '$index-${workout.id}',
                            ), // prefix index to workout.id to allow multiple instances of same workout in the reorderable list
                            onCopy: () => _copyWorkout(workout),
                            onDelete: () => _deleteWorkout(workout),
                            onSaveToCatalog:
                                (notInCatalog && notInTrash)
                                    ? () => _saveWorkoutToCatalog(workout)
                                    : null,
                            onTap: () async {
                              final result = await Navigator.push<
                                ({Workout workout, PendingChangeBag pending})
                              >(
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
