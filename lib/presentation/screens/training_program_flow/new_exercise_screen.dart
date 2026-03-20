import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/presentation/widgets/increment_decrement_number.dart';
import 'package:flash_forward/presentation/widgets/keyboard_dismiss_button.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class NewExerciseScreen extends StatefulWidget {
  final Exercise? exercise;

  const NewExerciseScreen({super.key, this.exercise});

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
  late int _sets = widget.exercise?.sets ?? 3;
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

  // Catalog exercises have no userId — title/label/description are locked.
  bool get _canEditMetadata =>
      widget.exercise == null || widget.exercise!.userId != null;

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

  void _save() {
    if (_formKey.currentState!.validate()) {
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
        sets: _sets,
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
      Navigator.pop(context, exercise);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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

              // ── Title + Label ──────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _titleController,
                      autofocus: _isNew,
                      enabled: _canEditMetadata,
                      maxLength: FieldLimits.exerciseTitleMaxLength,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        fillColor: context.colorScheme.surfaceBright,
                        labelText: 'Title',
                        labelStyle: context.bodyMedium,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 8,
                        ),
                      ),
                      validator:
                          _canEditMetadata
                              ? FieldValidators.exerciseTitle
                              : null,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Opacity(
                      opacity: _canEditMetadata ? 1.0 : 0.5,
                      child: IgnorePointer(
                        ignoring: !_canEditMetadata,
                        child: MyLabelDropdownButton(
                          value: _label,
                          onChanged: (value) => setState(() => _label = value),
                          validator:
                              _canEditMetadata ? FieldValidators.label : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),

              // ── Description ────────────────────────────────────
              TextFormField(
                controller: _descriptionController,
                enabled: _canEditMetadata,
                maxLength: FieldLimits.exerciseDescriptionMaxLength,
                maxLines: null,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  fillColor: context.colorScheme.surfaceBright,
                  labelText: 'Description',
                  labelStyle: context.bodyMedium,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                ),
                validator:
                    _canEditMetadata
                        ? FieldValidators.exerciseDescription
                        : null,
              ),
              SizedBox(height: 20),

              // ── Training section ───────────────────────────────
              _SectionHeader(title: 'Training'),
              SizedBox(height: 8),
              _SectionCard(
                children: [
                  // ── Exercise type selector ──
                  _ExerciseTypeSelector(
                    value: _exerciseType,
                    onChanged:
                        (type) => setState(() {
                          _exerciseType = type;
                          // Reset reps enablement when switching types
                          if (type == ExerciseType.timedReps) {
                            _repsEnabled = true;
                            _reps ??= 10;
                          } else {
                            _repsEnabled = widget.exercise?.reps != null;
                          }
                        }),
                  ),
                  _Divider(),

                  // ── Sets (all types) ──
                  _CounterRow(
                    label: 'Sets',
                    value: _sets,
                    minimum: 1,
                    onDecrement: () => setState(() => _sets--),
                    onIncrement: () => setState(() => _sets++),
                  ),
                  SizedBox(height: 8),

                  // ── Type-specific fields ──
                  if (_exerciseType == ExerciseType.timedReps) ...[
                    _CounterRow(
                      label: 'Reps',
                      value: _reps ?? 10,
                      minimum: 1,
                      onDecrement:
                          () => setState(
                            () => _reps = ((_reps ?? 10) - 1).clamp(1, 9999),
                          ),
                      onIncrement:
                          () => setState(() => _reps = (_reps ?? 10) + 1),
                    ),
                    _Divider(),
                    _CounterRow(
                      label: 'Rest between sets',
                      value: _timeBetweenSets,
                      minimum: 0,
                      onDecrement:
                          () => setState(
                            () =>
                                _timeBetweenSets = (_timeBetweenSets - 5).clamp(
                                  0,
                                  9999,
                                ),
                          ),
                      onIncrement: () => setState(() => _timeBetweenSets += 5),
                    ),
                    SizedBox(height: 8),
                    _CounterRow(
                      label: 'Time per rep',
                      value: _timePerRep,
                      minimum: 0,
                      onDecrement: () => setState(() => _timePerRep--),
                      onIncrement: () => setState(() => _timePerRep++),
                    ),
                    SizedBox(height: 8),
                    _CounterRow(
                      label: 'Rest between reps',
                      value: _timeBetweenReps,
                      minimum: 0,
                      onDecrement: () => setState(() => _timeBetweenReps--),
                      onIncrement: () => setState(() => _timeBetweenReps++),
                    ),
                  ] else if (_exerciseType == ExerciseType.fixedDuration) ...[
                    _CounterRow(
                      label: 'Active time (s)',
                      value: _activeTime,
                      minimum: 5,
                      onDecrement:
                          () => setState(
                            () =>
                                _activeTime = (_activeTime - 5).clamp(5, 9999),
                          ),
                      onIncrement: () => setState(() => _activeTime += 5),
                    ),
                    _Divider(),
                    _CounterRow(
                      label: 'Rest between sets',
                      value: _timeBetweenSets,
                      minimum: 0,
                      onDecrement:
                          () => setState(
                            () =>
                                _timeBetweenSets = (_timeBetweenSets - 5).clamp(
                                  0,
                                  9999,
                                ),
                          ),
                      onIncrement: () => setState(() => _timeBetweenSets += 5),
                    ),
                    _Divider(),
                    _OptionalRepsRow(
                      enabled: _repsEnabled,
                      reps: _reps ?? 5,
                      onToggle:
                          (enabled) => setState(() {
                            _repsEnabled = enabled;
                            if (enabled) _reps ??= 5;
                          }),
                      onDecrement:
                          () => setState(
                            () => _reps = ((_reps ?? 5) - 1).clamp(1, 9999),
                          ),
                      onIncrement:
                          () => setState(() => _reps = (_reps ?? 5) + 1),
                    ),
                  ] else ...[
                    // manual
                    _CounterRow(
                      label: 'Rest between sets',
                      value: _timeBetweenSets,
                      minimum: 0,
                      onDecrement:
                          () => setState(
                            () =>
                                _timeBetweenSets = (_timeBetweenSets - 5).clamp(
                                  0,
                                  9999,
                                ),
                          ),
                      onIncrement: () => setState(() => _timeBetweenSets += 5),
                    ),
                    _Divider(),
                    _OptionalRepsRow(
                      enabled: _repsEnabled,
                      reps: _reps ?? 5,
                      onToggle:
                          (enabled) => setState(() {
                            _repsEnabled = enabled;
                            if (enabled) _reps ??= 5;
                          }),
                      onDecrement:
                          () => setState(
                            () => _reps = ((_reps ?? 5) - 1).clamp(1, 9999),
                          ),
                      onIncrement:
                          () => setState(() => _reps = (_reps ?? 5) + 1),
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
                                      () => _loadUnit = selected ? unit : null,
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
                  onChanged:
                      (value) => setState(() => _detailsExpanded = value),
                ),
              ),
              if (_detailsExpanded) ...[
                SizedBox(height: 8),
                _SectionCard(
                  children: [
                    TextFormField(
                      controller: _equipmentController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        fillColor: context.colorScheme.surfaceBright,
                        labelText: 'Equipment',
                        labelStyle: context.bodyMedium,
                        hintText: 'e.g. Barbell, Dumbbells',
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _muscleGroupsController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        fillColor: context.colorScheme.surfaceBright,
                        labelText: 'Muscle Groups',
                        labelStyle: context.bodyMedium,
                        hintText: 'e.g. Chest, Triceps',
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Difficulty',
                          style: context.bodyMedium.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
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
                                  onSelected:
                                      (selected) => setState(
                                        () => _difficulty = selected ? d : null,
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: SegmentedButton<ExerciseType>(
        segments: [
          ButtonSegment(
            value: ExerciseType.timedReps,
            label: Text('Timed reps', style: context.bodyMedium,),
          ),
          ButtonSegment(
            value: ExerciseType.fixedDuration,
            label: Text('Fixed duration', style: context.bodyMedium,),
          ),
          ButtonSegment(value: ExerciseType.manual, label: Text('Manual', style: context.bodyMedium,)),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity(horizontal: 0, vertical: -2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _OptionalRepsRow extends StatelessWidget {
  final bool enabled;
  final int reps;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _OptionalRepsRow({
    required this.enabled,
    required this.reps,
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
            Switch(value: enabled, onChanged: onToggle),
          ],
        ),
        if (enabled) ...[
          SizedBox(height: 8),
          _CounterRow(
            label: 'Reps',
            value: reps,
            minimum: 1,
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
                children: [Text(title, style: context.titleMedium), trailing!],
              )
              : Text(title, style: context.titleMedium),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  final String label;
  final int value;
  final int minimum;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _CounterRow({
    required this.label,
    required this.value,
    required this.minimum,
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
