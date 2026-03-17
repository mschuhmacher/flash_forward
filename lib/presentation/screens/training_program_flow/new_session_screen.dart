import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/add_workout_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/presentation/widgets/session_select_listview.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class NewSessionScreen extends StatefulWidget {
  final Session? session;

  const NewSessionScreen({super.key, this.session});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();

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

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox.shrink(),
            Text(session.title == 'title' ? 'New Session' : 'Edit session'),
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
                      validator:
                          FieldValidators.sessionLabel
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
                  ? Expanded(child: Center(child: Text('Add a workout!')))
                  : Expanded(
                    child:
                    // SessionSelectListView(item: session.workouts),
                    ListView.builder(
                      itemCount: session.workouts.length,
                      itemBuilder: (BuildContext context, int index) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => NewWorkoutScreen(
                                      workout: session.workouts[index],
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
                                    Text(session.workouts[index].title),
                                    Text(session.workouts[index].label),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Text(
                                        session.workouts[index].description!,
                                        overflow: TextOverflow.fade,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        session
                                            .workouts[index]
                                            .timeBetweenExercises
                                            .toString(),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    SizedBox(width: 60, child: Text('Sets:')),
                                    SizedBox(width: 60, child: Text('Reps:')),
                                    SizedBox(width: 70, child: Text('Load:')),
                                  ],
                                ),
                                for (var exercise
                                    in session.workouts[index].exercises)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Expanded(child: Text(exercise.title)),
                                      SizedBox(
                                        width: 60,
                                        child: Text(exercise.sets.toString()),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(exercise.reps.toString()),
                                      ),
                                      SizedBox(
                                        width: 70,
                                        child: Text(exercise.load.toString()),
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
          List<Workout>? addedWorkouts = await Navigator.push(
            context,
            MaterialPageRoute<List<Workout>>(
              builder: (context) => AddWorkoutScreen(),
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
