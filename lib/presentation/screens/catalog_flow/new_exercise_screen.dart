import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/pending_change.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/group_form_card.dart';
import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flash_forward/presentation/widgets/keyboard_dismiss_button.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/propagate_changes_dialog.dart';
import 'package:flash_forward/presentation/widgets/auth_wall.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/catalog/edit_commit_controller.dart';
import 'package:flash_forward/features/catalog/catalog_provider.dart';
import 'package:flash_forward/presentation/widgets/unsaved_changes_dialog.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/core/superset_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Returned from [NewExerciseScreen] on save. [exercise] always carries the
/// final exercise. [supersetSetsChange] is non-null only when the screen was
/// opened with a [parentWorkout], the edited exercise is a superset member,
/// AND the user changed the sets field — in that case [exercise.sets] is the
/// pre-existing value (untouched) and [supersetSetsChange] is the new value
/// the caller should write to the parent superset's `supersetSets` field.
class NewExerciseResult {
  final Exercise exercise;
  final int? supersetSetsChange;
  const NewExerciseResult({required this.exercise, this.supersetSetsChange});

  /// Decides what value (if any) to surface as `supersetSetsChange`.
  /// - Returns `null` when the exercise is not in a superset (saves go to
  ///   the exercise's own `sets`).
  /// - Returns `null` when the displayed sets value equals the existing
  ///   `supersetSets` (no-op edit).
  /// - Returns the new value otherwise.
  ///
  /// Extracted as a pure function so the contract — "non-null only on actual
  /// change" — is unit-testable without spinning up the full edit screen.
  static int? computeSupersetSetsChange({
    required SupersetConfig? membership,
    required int displayedSets,
    required int? existingSupersetSets,
    required int exerciseSetsFallback,
  }) {
    if (membership == null) return null;
    final existing = existingSupersetSets ?? exerciseSetsFallback;
    return displayedSets != existing ? displayedSets : null;
  }
}

class NewExerciseScreen extends StatefulWidget {
  final Exercise? exercise;

  /// When true, saving will persist the exercise to [CatalogProvider] (add or
  /// update). Use this when opening the screen standalone (e.g. from the FAB).
  /// Leave false when used as a sub-editor inside another form.
  final bool persistToProvider;

  /// When non-null, the screen knows the editing context — i.e. the workout
  /// that contains this exercise. If the exercise is a superset member, the
  /// sets field reads/writes the superset's `supersetSets` rather than
  /// `exercise.sets`, and the result includes a `supersetSetsChange` for the
  /// caller to apply.
  final Workout? parentWorkout;

  const NewExerciseScreen({
    super.key,
    this.exercise,
    this.persistToProvider = false,
    this.parentWorkout,
  });

  @override
  State<NewExerciseScreen> createState() => _NewExerciseScreenState();
}

class _NewExerciseScreenState extends State<NewExerciseScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _titleController = TextEditingController(
    text: widget.exercise?.title,
  );
  late final _descriptionController = TextEditingController(
    text: widget.exercise?.description,
  );
  late final _equipmentController = TextEditingController(
    text: widget.exercise?.equipment,
  );
  late final _muscleGroupsController = TextEditingController(
    text: widget.exercise?.muscleGroups,
  );
  late final _loadController = TextEditingController(
    text:
        widget.exercise != null && widget.exercise!.load > 0
            ? widget.exercise!.load.toString()
            : '',
  );
  late final _notesController = TextEditingController(
    text: widget.exercise?.notes,
  );

  late String? _label = widget.exercise?.label;
  late String? _difficulty = widget.exercise?.difficulty;
  late String? _loadUnit = widget.exercise?.loadUnit;

  late ExerciseType _exerciseType =
      widget.exercise?.type ?? ExerciseType.timedReps;
  // For superset members the displayed sets are supersetSets, not the
  // exercise's own sets. Caller routes the new value back to the superset
  // on save.
  late int _sets =
      widget.parentWorkout != null && widget.exercise != null
          ? setsForExerciseInWorkout(widget.parentWorkout!, widget.exercise!)
          : widget.exercise?.sets ?? 3;
  late int? _reps =
      widget.exercise?.reps ?? 10; // null = no target for fixedDuration/manual
  late bool _repsEnabled =
      widget.exercise?.reps != null; // only used for fixedDuration/manual
  late int _timeBetweenSets = widget.exercise?.timeBetweenSets ?? 60;
  late int _timePerRep = widget.exercise?.timePerRep ?? 3;
  late int _timeBetweenReps = widget.exercise?.timeBetweenReps ?? 0;
  late int _activeTime = widget.exercise?.activeTime ?? 30;
  late int _rpe = widget.exercise?.rpe ?? 5;
  late bool _rpeEnabled = widget.exercise?.rpe != null;
  late bool _detailsExpanded =
      widget.exercise?.equipment != null ||
      widget.exercise?.muscleGroups != null ||
      widget.exercise?.difficulty != null ||
      widget.exercise?.rpe != null;

  bool get _isNew => widget.exercise == null;

  // Captured once so dirty-check has a stable baseline. New exercises have no
  // widget.exercise, so any input immediately reads as dirty.
  bool get _isDirty {
    final e = widget.exercise;
    if (_titleController.text.trim() != (e?.title ?? '')) return true;
    if (_descriptionController.text.trim() != (e?.description ?? ''))
      return true;
    if (_label != (e?.label)) return true;
    if (_equipmentController.text.trim() != (e?.equipment ?? '')) return true;
    if (_muscleGroupsController.text.trim() != (e?.muscleGroups ?? ''))
      return true;
    if (_difficulty != e?.difficulty) return true;
    if (_loadUnit != e?.loadUnit) return true;
    final initialLoad = e != null && e.load > 0 ? e.load.toString() : '';
    if (_loadController.text.trim() != initialLoad) return true;
    if (_notesController.text.trim() != (e?.notes ?? '')) return true;
    if (_exerciseType != (e?.type ?? ExerciseType.timedReps)) return true;
    final initialSets =
        widget.parentWorkout != null && e != null
            ? setsForExerciseInWorkout(widget.parentWorkout!, e)
            : e?.sets ?? 3;
    if (_sets != initialSets) return true;
    if (_reps != (e?.reps ?? 10)) return true;
    if (_repsEnabled != (e?.reps != null)) return true;
    if (_timeBetweenSets != (e?.timeBetweenSets ?? 60)) return true;
    if (_timePerRep != (e?.timePerRep ?? 3)) return true;
    if (_timeBetweenReps != (e?.timeBetweenReps ?? 0)) return true;
    if (_activeTime != (e?.activeTime ?? 30)) return true;
    if (_rpeEnabled != (e?.rpe != null)) return true;
    if (_rpeEnabled && _rpe != (e?.rpe ?? 5)) return true;
    return false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _equipmentController.dispose();
    _muscleGroupsController.dispose();
    _loadController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      // If this exercise is a superset member, the sets field is controlled
      // by the parent superset's supersetSets — keep exercise.sets at its
      // original value and surface the new value separately, but only when
      // it actually differs from the existing supersetSets.
      final supersetMembership =
          widget.parentWorkout != null && widget.exercise != null
              ? supersetForExercise(widget.parentWorkout!, widget.exercise!.id)
              : null;
      final preservedSets =
          supersetMembership != null ? widget.exercise!.sets : _sets;
      final supersetSetsChange = NewExerciseResult.computeSupersetSetsChange(
        membership: supersetMembership,
        displayedSets: _sets,
        existingSupersetSets: supersetMembership?.supersetSets,
        exerciseSetsFallback: widget.exercise?.sets ?? _sets,
      );

      final exercise = Exercise(
        id: widget.exercise?.id,
        templateId: widget.exercise?.templateId,
        // userID is null for default exercises and has a value for user-generated ones. This is retained when editing and the user's ID is attached for new exercises.
        userId:
            widget.exercise?.userId ??
            Provider.of<AuthProvider>(context, listen: false).userId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        label: _label ?? '',
        equipment:
            _equipmentController.text.trim().isEmpty
                ? null
                : _equipmentController.text.trim(),
        muscleGroups:
            _muscleGroupsController.text.trim().isEmpty
                ? null
                : _muscleGroupsController.text.trim(),
        difficulty: _difficulty,
        type: _exerciseType,
        sets: preservedSets,
        reps:
            _exerciseType == ExerciseType.timedReps
                ? (_reps ?? 10)
                : (_repsEnabled ? _reps : null),
        timeBetweenSets: _timeBetweenSets,
        timePerRep: _timePerRep,
        timeBetweenReps: _timeBetweenReps,
        activeTime: _activeTime,
        load: double.tryParse(_loadController.text.trim()) ?? 0.0,
        loadUnit: _loadUnit,
        rpe: _rpeEnabled ? _rpe.clamp(1, 10) : null,
        notes:
            _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
      );
      if (widget.persistToProvider) {
        // Gate only the persisting path — a nested editor (persistToProvider
        // false) pops its result up without saving and must not gate.
        final allowed = await requireAuth(
          context,
          message: 'save exercises to your catalog',
        );
        if (!allowed || !mounted) return;

        final catalogProvider = Provider.of<CatalogProvider>(
          context,
          listen: false,
        );
        if (_isNew) {
          await catalogProvider.upsertExercise(exercise);
        } else {
          final editCommit = context.read<EditCommitController>();
          final bag = PendingChangeBag()..addExercise(exercise);
          final result = await editCommit.commitChanges(bag);
          if (result.hasAny && mounted) {
            final sections = <PropagationSection>[
              for (final entry in result.affectedWorkoutsByExerciseId.entries)
                PropagationSection(
                  itemKind: 'exercise',
                  itemId: entry.key,
                  itemTitle: exercise.title,
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
        Navigator.pop(
          context,
          NewExerciseResult(
            exercise: exercise,
            supersetSetsChange: supersetSetsChange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox.shrink(),
                Text(_isNew ? 'New Exercise' : 'Edit Exercise'),
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
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              children: [
                const KeyboardDismissButton(),

                // ── Title / Label / Info grouped card ─────────────
                GroupFormCard(
                  children: [
                    GroupFormRow(
                      label: 'Title',
                      trailing: GroupFormCounter(
                        current: _titleController.text.length,
                        max: FieldLimits.exerciseTitleMaxLength,
                      ),
                      child: TextFormField(
                        controller: _titleController,
                        autofocus: _isNew,
                        maxLength: FieldLimits.exerciseTitleMaxLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        textInputAction: TextInputAction.next,
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
                        validator: (value) {
                          final catalogProvider = Provider.of<CatalogProvider>(
                            context,
                            listen: false,
                          );
                          return FieldValidators.exerciseTitle(
                            value,
                            existingTitles:
                                catalogProvider.presetExercises
                                    .map((e) => e.title)
                                    .toList(),
                            ownTitle: widget.exercise?.title,
                          );
                        },
                      ),
                    ),
                    GroupFormRow(
                      label: 'Label',
                      child: MyLabelDropdownButton(
                        value: _label,
                        onChanged: (value) => setState(() => _label = value),
                        validator: FieldValidators.label,
                        flat: true,
                      ),
                    ),
                    GroupFormRow(
                      label: 'Info',
                      trailing: GroupFormCounter(
                        current: _descriptionController.text.length,
                        max: FieldLimits.exerciseDescriptionMaxLength,
                      ),
                      child: TextFormField(
                        controller: _descriptionController,
                        maxLength: FieldLimits.exerciseDescriptionMaxLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        maxLines: null,
                        textInputAction: TextInputAction.next,
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
                        validator: FieldValidators.exerciseDescription,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),

                // ── Training section ───────────────────────────────
                _SectionHeader(title: 'Training'),
                SizedBox(height: 8),
                _SectionCard(
                  header: _ExerciseTypeSelector(
                    value: _exerciseType,
                    onChanged:
                        (type) => setState(() {
                          _exerciseType = type;
                          if (type == ExerciseType.timedReps) {
                            _repsEnabled = true;
                            _reps ??= 10;
                          } else {
                            _repsEnabled = widget.exercise?.reps != null;
                          }
                        }),
                  ),
                  children: [
                    // ── Sets (all types) ──
                    _CounterRow(
                      label: 'Sets',
                      value: _sets,
                      minimum: 1,
                      maximum: FieldLimits.setLimit,
                      onDecrement: () => setState(() => _sets--),
                      onIncrement:
                          () => setState(
                            () =>
                                _sets = (_sets + 1).clamp(
                                  1,
                                  FieldLimits.setLimit,
                                ),
                          ),
                    ),
                    if (widget.parentWorkout != null &&
                        widget.exercise != null &&
                        supersetForExercise(
                              widget.parentWorkout!,
                              widget.exercise!.id,
                            ) !=
                            null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Sets are controlled by the superset — changes apply to all members.',
                          style: context.bodyMedium.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 8),

                    // ── Type-specific fields ──
                    if (_exerciseType == ExerciseType.timedReps) ...[
                      _CounterRow(
                        label: 'Reps',
                        value: _reps ?? 10,
                        minimum: 1,
                        maximum: FieldLimits.repLimit,
                        onDecrement:
                            () => setState(
                              () =>
                                  _reps = ((_reps ?? 10) - 1).clamp(
                                    1,
                                    FieldLimits.repLimit,
                                  ),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _reps = ((_reps ?? 10) + 1).clamp(
                                    1,
                                    FieldLimits.repLimit,
                                  ),
                            ),
                      ),
                      _Divider(),
                      _CounterRow(
                        label: 'Rest between sets',
                        value: _timeBetweenSets,
                        minimum: 0,
                        maximum: FieldLimits.timeLimit,
                        onDecrement:
                            () => setState(
                              () =>
                                  _timeBetweenSets = (_timeBetweenSets - 5)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _timeBetweenSets = (_timeBetweenSets + 5)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                      ),
                      SizedBox(height: 8),
                      _CounterRow(
                        label: 'Time per rep',
                        value: _timePerRep,
                        minimum: 0,
                        maximum: FieldLimits.timeLimit,
                        onDecrement: () => setState(() => _timePerRep--),
                        onIncrement:
                            () => setState(
                              () =>
                                  _timePerRep = (_timePerRep + 1).clamp(
                                    0,
                                    FieldLimits.timeLimit,
                                  ),
                            ),
                      ),
                      SizedBox(height: 8),
                      _CounterRow(
                        label: 'Rest between reps',
                        value: _timeBetweenReps,
                        minimum: 0,
                        maximum: FieldLimits.timeLimit,
                        onDecrement: () => setState(() => _timeBetweenReps--),
                        onIncrement:
                            () => setState(
                              () =>
                                  _timeBetweenReps = (_timeBetweenReps + 1)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                      ),
                    ] else if (_exerciseType == ExerciseType.fixedDuration) ...[
                      _CounterRow(
                        label: 'Active time (s)',
                        value: _activeTime,
                        minimum: 5,
                        maximum: FieldLimits.timeLimit,
                        onDecrement:
                            () => setState(
                              () =>
                                  _activeTime = (_activeTime - 5).clamp(
                                    5,
                                    FieldLimits.timeLimit,
                                  ),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _activeTime = (_activeTime + 5).clamp(
                                    5,
                                    FieldLimits.timeLimit,
                                  ),
                            ),
                      ),
                      _Divider(),
                      _CounterRow(
                        label: 'Rest between sets',
                        value: _timeBetweenSets,
                        minimum: 0,
                        maximum: FieldLimits.timeLimit,
                        onDecrement:
                            () => setState(
                              () =>
                                  _timeBetweenSets = (_timeBetweenSets - 5)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _timeBetweenSets = (_timeBetweenSets + 5)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                      ),
                      _Divider(),
                      _OptionalRepsRow(
                        enabled: _repsEnabled,
                        reps: _reps ?? 5,
                        maximum: FieldLimits.repLimit,
                        onToggle:
                            (enabled) => setState(() {
                              _repsEnabled = enabled;
                              if (enabled) _reps ??= 5;
                            }),
                        onDecrement:
                            () => setState(
                              () =>
                                  _reps = ((_reps ?? 5) - 1).clamp(
                                    1,
                                    FieldLimits.repLimit,
                                  ),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _reps = ((_reps ?? 5) + 1).clamp(
                                    1,
                                    FieldLimits.repLimit,
                                  ),
                            ),
                      ),
                    ] else ...[
                      // manual
                      _CounterRow(
                        label: 'Rest between sets',
                        value: _timeBetweenSets,
                        minimum: 0,
                        maximum: FieldLimits.timeLimit,
                        onDecrement:
                            () => setState(
                              () =>
                                  _timeBetweenSets = (_timeBetweenSets - 5)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _timeBetweenSets = (_timeBetweenSets + 5)
                                      .clamp(0, FieldLimits.timeLimit),
                            ),
                      ),
                      _Divider(),
                      _OptionalRepsRow(
                        enabled: _repsEnabled,
                        reps: _reps ?? 5,
                        maximum: FieldLimits.repLimit,
                        onToggle:
                            (enabled) => setState(() {
                              _repsEnabled = enabled;
                              if (enabled) _reps ??= 5;
                            }),
                        onDecrement:
                            () => setState(
                              () =>
                                  _reps = ((_reps ?? 5) - 1).clamp(
                                    1,
                                    FieldLimits.repLimit,
                                  ),
                            ),
                        onIncrement:
                            () => setState(
                              () =>
                                  _reps = ((_reps ?? 5) + 1).clamp(
                                    1,
                                    FieldLimits.repLimit,
                                  ),
                            ),
                      ),
                    ],
                    _Divider(),

                    // Load
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _loadController,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) => newValue.copyWith(
                                  text: newValue.text.replaceAll(',', '.'),
                                ),
                              ),
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'),
                              ),
                            ],
                            validator: FieldValidators.load,
                            decoration: InputDecoration(
                              fillColor: context.colorScheme.surfaceBright,
                              labelText: 'Load',
                              labelStyle: context.bodyMedium,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Wrap(
                          spacing: 6,
                          children:
                              ['kg', 'lbs'].map((unit) {
                                return ChoiceChip(
                                  label: Text(unit),
                                  selected: _loadUnit == unit,
                                  onSelected:
                                      (selected) => setState(
                                        () =>
                                            _loadUnit = selected ? unit : null,
                                      ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20),

                // ── Details section ────────────────────────────────
                _SectionHeader(
                  title: 'Details',
                  trailing: Switch(
                    value: _detailsExpanded,
                    activeThumbColor: context.colorScheme.secondary,
                    onChanged:
                        (value) => setState(() => _detailsExpanded = value),
                  ),
                ),
                if (_detailsExpanded) ...[
                  SizedBox(height: 8),
                  _SectionCard(
                    children: [
                      GroupFormStackRow(
                        label: 'Equipment',
                        accentColor: context.colorScheme.secondary,
                        child: TextFormField(
                          controller: _equipmentController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'e.g. Barbell, Dumbbells',
                            hintStyle: context.bodyMedium.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      _Divider(),
                      GroupFormStackRow(
                        label: 'Muscle Groups',
                        accentColor: context.colorScheme.secondary,
                        child: TextFormField(
                          controller: _muscleGroupsController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            hintText: 'e.g. Chest, Triceps',
                            hintStyle: context.bodyMedium.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      _Divider(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DIFFICULTY',
                            style: context.label.copyWith(
                              color: context.colorScheme.secondary,
                            ),
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children:
                                ['Easy', 'Medium', 'Hard'].map((d) {
                                  return ChoiceChip(
                                    label: Text(d),
                                    selected: _difficulty == d,
                                    selectedColor:
                                        context.colorScheme.secondary,
                                    onSelected:
                                        (selected) => setState(
                                          () =>
                                              _difficulty = selected ? d : null,
                                        ),
                                  );
                                }).toList(),
                          ),
                        ],
                      ),
                      _Divider(),

                      // RPE
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('RPE', style: context.titleMedium),
                              Text(
                                'Rate of Perceived Exertion',
                                style: context.bodyMedium.copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: _rpeEnabled,
                            activeThumbColor: context.colorScheme.secondary,
                            onChanged:
                                (value) => setState(() => _rpeEnabled = value),
                          ),
                        ],
                      ),
                      if (_rpeEnabled) ...[
                        SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _rpeLabel(_rpe),
                              style: context.bodyMedium.copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            IncrementDecrementNumberWidget(
                              value: _rpe.clamp(1, 10),
                              minimum: 1,
                              decrement: () {
                                if (_rpe > 1) setState(() => _rpe--);
                              },
                              increment: () {
                                if (_rpe < 10) setState(() => _rpe++);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
                SizedBox(height: 20),

                // ── Notes section ──────────────────────────────────
                _SectionHeader(title: 'Notes'),
                SizedBox(height: 8),
                TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    fillColor: context.colorScheme.surfaceBright,
                    labelText: 'Notes',
                    labelStyle: context.bodyMedium,
                    hintText: 'Any additional notes...',
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                  ),
                ),
                SizedBox(height: 32),
                const KeyboardDismissButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rpeLabel(int rpe) {
    return switch (rpe) {
      1 || 2 => 'Very light',
      3 || 4 => 'Light',
      5 || 6 => 'Moderate',
      7 || 8 => 'Hard',
      9 => 'Very hard',
      _ => 'Maximum',
    };
  }
}

// ── Private helper widgets ──────────────────────────────────────

class _ExerciseTypeSelector extends StatelessWidget {
  final ExerciseType value;
  final ValueChanged<ExerciseType> onChanged;

  const _ExerciseTypeSelector({required this.value, required this.onChanged});

  static const _types = [
    (ExerciseType.timedReps, 'Timed reps'),
    (ExerciseType.fixedDuration, 'Fixed'),
    (ExerciseType.manual, 'Manual'),
  ];

  @override
  Widget build(BuildContext context) {
    final secondary = context.colorScheme.secondary;
    return Row(
      children:
          _types.map((entry) {
            final (type, label) = entry;
            final selected = value == type;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(type),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: selected ? secondary : Colors.transparent,
                  child: Center(
                    child: Text(
                      label,
                      style: context.titleMedium.copyWith(
                        color:
                            selected
                                ? context.colorScheme.onSurface
                                : context.colorScheme.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

class _OptionalRepsRow extends StatelessWidget {
  final bool enabled;
  final int reps;
  final int? maximum;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _OptionalRepsRow({
    required this.enabled,
    required this.reps,
    this.maximum,
    required this.onToggle,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rep target', style: context.titleMedium),
                Text(
                  'Optional — shown during exercise',
                  style: context.bodyMedium.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Switch(
              value: enabled,
              activeThumbColor: context.colorScheme.secondary,
              onChanged: onToggle,
            ),
          ],
        ),
        if (enabled) ...[
          SizedBox(height: 8),
          _CounterRow(
            label: 'Reps',
            value: reps,
            minimum: 1,
            maximum: maximum,
            onDecrement: onDecrement,
            onIncrement: onIncrement,
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4),
      child:
          trailing != null
              ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(title, style: context.titleLarge), trailing!],
              )
              : Text(title, style: context.titleLarge),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  final Widget? header;
  const _SectionCard({required this.children, this.header});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: context.colorScheme.primary.withValues(alpha: 0.08),
        ),
        boxShadow: context.shadowSmall,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[header!, Divider(height: 1)],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  final String label;
  final int value;
  final int minimum;
  final int? maximum;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _CounterRow({
    required this.label,
    required this.value,
    required this.minimum,
    this.maximum,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.titleMedium),
        IncrementDecrementNumberWidget(
          value: value,
          minimum: minimum,
          maximum: maximum,
          decrement: onDecrement,
          increment: onIncrement,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1),
    );
  }
}
