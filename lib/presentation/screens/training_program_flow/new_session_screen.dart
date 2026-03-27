import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/session_select_listview.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/utils/nullable.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class NewSessionScreen extends StatefulWidget {
  final Session? session;

  const NewSessionScreen({super.key, this.session});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get _isNew => widget.session == null;

  // Title, label, workouts are required fields, so session must be initialized with them
  late Session _session =
      widget.session ?? Session(title: 'title', label: 'label', workouts: []);

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
      final presetProvider = Provider.of<PresetProvider>(
        context,
        listen: false,
      );
      if (_isNew) {
        await presetProvider.addPresetSession(session);
      } else {
        await presetProvider.updatePresetSession(session);
      }
      if (mounted) Navigator.pop(context);
    }
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
                      validator: FieldValidators.sessionTitle,
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
                  // if (widget.itemName == 'workout') ...[],
                ],
              ),
              SizedBox(height: 8),
              // Expanded(child: Center(child: Text('No workouts added yet!'))),
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
                        return _WorkoutCard(
                          workout: workout,
                          key: ValueKey(
                            '$index-${workout.id}',
                          ), // prefix index to workout.id to allow multiple instances of same workout in the reorderable list
                          onTap:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) =>
                                          NewWorkoutScreen(workout: workout),
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

  const _WorkoutCard({super.key, required this.workout, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Slidable(
        key: ValueKey(workout.id),
        endActionPane: ActionPane(
          motion: ScrollMotion(),
          children: [
            SizedBox(width: 8),
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (context) {}, //TODO: hookup to copy function
                backgroundColor: context.colorScheme.secondary,
                foregroundColor: context.colorScheme.onError,
                icon: Icons.copy_rounded,
                label: 'Copy',
              ),
            SizedBox(width: 8),
            SlidableAction(
              borderRadius: BorderRadius.circular(12),
              onPressed: (context) {}, //TODO: hookup to delete function
              backgroundColor: context.colorScheme.error,
              foregroundColor: context.colorScheme.onError,
              icon: Icons.delete_rounded,
              label: 'Delete',
            ),
          ],
        ),

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
                  Text(workout.title, style: context.titleMedium),
                  _LabelBadge(labelKey: workout.label),
                ],
              ),
              if (workout.description != null &&
                  workout.description!.isNotEmpty) ...[
                SizedBox(height: 2),
                Text(
                  workout.description!,
                  style: context.bodyMedium.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (workout.exercises.isNotEmpty) ...[
                SizedBox(height: 10),
                Divider(height: 1),
                SizedBox(height: 8),
                // Column headers
                Row(
                  children: [
                    Expanded(child: SizedBox.shrink()),
                    SizedBox(
                      width: 40,
                      child: Text(
                        'Sets',
                        style: context.bodyMedium.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        'Reps',
                        style: context.bodyMedium.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        'Load',
                        style: context.bodyMedium.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                // Exercise rows
                for (final exercise in workout.exercises)
                  Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            exercise.title,
                            style: context.bodyMedium,
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${exercise.sets}',
                            style: context.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${exercise.reps}',
                            style: context.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            exercise.load > 0
                                ? exercise.loadUnit != null
                                    ? '${exercise.load} ${exercise.loadUnit}'
                                    : '${exercise.load}'
                                : '—',
                            style: context.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
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
