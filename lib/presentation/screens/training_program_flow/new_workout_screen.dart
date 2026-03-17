import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/add_item_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class NewWorkoutScreen extends StatefulWidget {
  final Workout? workout;

  const NewWorkoutScreen({super.key, this.workout});

  @override
  State<NewWorkoutScreen> createState() => _NewWorkoutScreenState();
}

class _NewWorkoutScreenState extends State<NewWorkoutScreen> {
  final _formKey = GlobalKey<FormState>();

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

  @override
  Widget build(BuildContext context) {
    final workout = _workout;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox.shrink(),
            Text(workout == null ? 'New workout' : 'Edit workout'),
            ElevatedButton(
              onPressed: () {},
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
                      // autofocus: true,
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
                      validator: FieldValidators.workoutTitle,
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
                      validator:
                          (value) =>
                              value == null || value.isEmpty
                                  ? 'Please select a label'
                                  : null,
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
              workout == null
                  ? Center(child: Text('Add a exercise!'))
                  : Expanded(
                    child: ListView.builder(
                      itemCount: workout.exercises.length,
                      itemBuilder: (BuildContext context, int index) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => NewExerciseScreen(
                                      exercise: workout.exercises[index],
                                    ),
                              ),
                            );
                          },
                          child: Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(workout.exercises[index].title),
                                    Text(workout.exercises[index].label),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        workout.exercises[index].description,
                                      ),
                                    ),
                                    Text(
                                      workout.exercises[index].timeBetweenSets
                                          .toString(),
                                    ),
                                  ],
                                ),
                                for (
                                  int i = 0;
                                  i < workout.exercises[index].sets;
                                  i++
                                )
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          'Sets: ${workout.exercises[index].sets}',
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          'Reps: ${workout.exercises[index].reps}',
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          'Load: ${workout.exercises[index].load}',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
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
          List<Exercise>? addedExercises = await Navigator.push(
            context,
            MaterialPageRoute<List<Exercise>>(
              builder:
                  (context) => AddWorkoutScreen(itemType: ItemType.exercises),
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
