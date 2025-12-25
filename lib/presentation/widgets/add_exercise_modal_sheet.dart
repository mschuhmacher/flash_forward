import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:training_schedule_app/models/exercise.dart';
import 'package:training_schedule_app/presentation/widgets/label_dropdownbutton.dart';
import 'package:training_schedule_app/presentation/widgets/my_arrow_button.dart';
import 'package:training_schedule_app/providers/preset_provider.dart';
import 'package:training_schedule_app/themes/app_text_styles.dart';

class AddExerciseModalSheet extends StatefulWidget {
  const AddExerciseModalSheet({super.key});

  @override
  State<AddExerciseModalSheet> createState() => _AddExerciseModalSheetState();
}

class _AddExerciseModalSheetState extends State<AddExerciseModalSheet> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _timeBetweenRepsController = TextEditingController();
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _loadController = TextEditingController();
  final _timeBetweenSetsController = TextEditingController();
  final _timePerRepController = TextEditingController();

  int _numberOfSets = 1;
  int _numberOfReps = 1;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey, //not sure if this key is okay to use
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Consumer<PresetProvider>(
              builder: (context, presetData, child) {
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ), //Remove close button since it's a bottom modal sheet?
                    TextFormField(
                      controller: _titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 16),
                    MyLabelDropdownButton(
                      value:
                          _labelController.text.isNotEmpty
                              ? _labelController.text
                              : null,
                      onChanged: (value) {
                        setState(() {
                          _labelController.text = value ?? '';
                        });
                      },
                      validator:
                          (value) =>
                              value == null || value.isEmpty
                                  ? 'Please select a label'
                                  : null,
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text('Sets', style: context.titleMedium),
                          ),
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              if (_numberOfSets >= 1) {
                                setState(() {
                                  _numberOfSets--;
                                });
                              }
                            },
                            child: MyArrowButton(icon: Icons.remove),
                          ),
                          SizedBox(width: 8),
                          SizedBox(
                            width: 30,
                            child: Center(
                              child: Text(
                                '$_numberOfSets',
                                style: context.bodyLarge,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _numberOfSets++;
                              });
                            },
                            child: MyArrowButton(icon: Icons.add),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text('Reps', style: context.titleMedium),
                          ),
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              if (_numberOfReps >= 1) {
                                setState(() {
                                  _numberOfReps--;
                                });
                              }
                            },
                            child: MyArrowButton(icon: Icons.remove),
                          ),
                          SizedBox(width: 8),
                          SizedBox(
                            width: 30,
                            child: Center(
                              child: Text(
                                '$_numberOfReps',
                                style: context.bodyLarge,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _numberOfReps++;
                              });
                            },
                            child: MyArrowButton(icon: Icons.add),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _timeBetweenSetsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a number';
                        }

                        final int? number = int.tryParse(value);
                        if (number == null) {
                          return 'Please enter a valid integer';
                        }

                        if (number <= 0) {
                          return 'Number must be greater than zero';
                        }

                        return null; // valid input
                      },
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Time between sets',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _timePerRepController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a number';
                        }

                        final int? number = int.tryParse(value);
                        if (number == null) {
                          return 'Please enter a valid integer';
                        }

                        if (number <= 0) {
                          return 'Number must be greater than zero';
                        }

                        return null; // valid input
                      },

                      // onSaved: (value) {
                      //   final intValue = int.tryParse(value ?? '');
                      //   // store or use intValue
                      // },
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Time per rep',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _timeBetweenRepsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a number';
                        }

                        final int? number = int.tryParse(value);
                        if (number == null) {
                          return 'Please enter a valid integer';
                        }

                        return null; // valid input
                      },

                      // onSaved: (value) {
                      //   final intValue = int.tryParse(value ?? '');
                      //   // store or use intValue
                      // },
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Time between reps',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _loadController,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ), // allow digits + decimal point
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a number';
                        }

                        final double? number = double.tryParse(value);
                        if (number == null) {
                          return 'Please enter a valid number';
                        }

                        if (number <= 0) {
                          return 'Value must be greater than zero';
                        }

                        return null;
                      },
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Load',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          final newExercise = Exercise(
                            title: _titleController.text.trim(),
                            label: _labelController.text.trim(),
                            description: _descriptionController.text.trim(),
                            reps: _numberOfReps,
                            sets: _numberOfSets,
                            timeBetweenSets: int.parse(
                              _timeBetweenSetsController.text.trim(),
                            ),
                            timePerRep: int.parse(
                              _timePerRepController.text.trim(),
                            ),
                            timeBetweenReps: int.parse(
                              _timeBetweenRepsController.text.trim(),
                            ),
                            load: _loadController.text.trim(),
                          );
                          presetData.addPresetExercise(newExercise);
                        }
                      },
                      child: Text('Save'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
