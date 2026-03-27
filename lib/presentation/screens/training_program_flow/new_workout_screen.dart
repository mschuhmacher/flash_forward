import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NewWorkoutScreen extends StatefulWidget {
  final Workout? workout;

  const NewWorkoutScreen({super.key, this.workout});

  @override
  State<NewWorkoutScreen> createState() => _NewWorkoutScreenState();
}

class _NewWorkoutScreenState extends State<NewWorkoutScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get _isNew => widget.workout == null;

  bool get _canEditMetadata =>
      widget.workout == null || widget.workout!.userId != null;

  late Workout _workout =
      widget.workout ??
      Workout(
        title: 'title',
        label: 'label',
        exercises: [],
        timeBetweenExercises: 120,
      );

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
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );
      if (_isNew) {
        await presetProvider.addPresetWorkout(workout);
      } else {
        await presetProvider.updatePresetWorkout(workout);
      }
      if (mounted) Navigator.pop(context);
    }
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
                      enabled: _canEditMetadata,
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
                      validator:
                          _canEditMetadata
                              ? FieldValidators.workoutTitle
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
                          value:
                              _itemLabelController.text.isNotEmpty
                                  ? _itemLabelController.text
                                  : null,
                          onChanged: (value) {
                            setState(() {
                              _itemLabelController.text = value ?? '';
                            });
                          },
                          validator:
                              _canEditMetadata ? FieldValidators.label : null,
                        ),
                      ),
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
                      enabled: _canEditMetadata,
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
                      validator:
                          _canEditMetadata
                              ? FieldValidators.workoutDescription
                              : null,
                    ),
                  ),
                  // if (widget.itemName == 'workout') ...[],
                ],
              ),
              SizedBox(height: 8),
              // Expanded(child: Center(child: Text('No workouts added yet!'))),
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
                        return _ExerciseCard(
                          exercise: exercise,
                          key: ValueKey('$index-${exercise.id}'), // prefix index to exercise.id to allow multiple instances of same exercise in the reorderable list
                          onTap:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) =>
                                          NewExerciseScreen(exercise: exercise),
                                ),
                              ),
                        );
                      },
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -=
                                1; // Since the widget if removed from its old index
                          }
                          final Exercise exercise = workout.exercises.removeAt(
                            oldIndex,
                          );
                          workout.exercises.insert(newIndex, exercise);
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
          List<Exercise>? addedExercises = await Navigator.push(
            context,
            MaterialPageRoute<List<Exercise>>(
              builder:
                  (context) => AddItemScreen(
                    itemType: ItemType.exercises,
                    existingItemIds: existingExerciseIds,
                  ),
            ),
          );

          if (addedExercises != null && addedExercises.isNotEmpty) {
            setState(() {
              _workout = _workout.copyWith(
                exercises: [..._workout.exercises, ...addedExercises],
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

  const _ExerciseCard({super.key, required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(14),
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
              SizedBox(height: 2),
              Text(
                exercise.description,
                style: context.bodyMedium.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: 10),
            Divider(height: 1),
            SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _StatPill(label: 'Sets', value: '${exercise.sets}'),
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
                _StatPill(label: 'Rest', value: '${exercise.timeBetweenSets}s'),
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
