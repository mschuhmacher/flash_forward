import 'package:flash_forward/constants/field_limits.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/session.dart';
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

  final _titleController = TextEditingController();
  final _itemLabelController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox.shrink(),
            Text(session?.title ?? 'New Session'),
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
              session == null
                  ? Center(child: Text('Add a workout!'))
                  : Expanded(
                    child: SessionSelectListView(item: session.workouts),

                    // ListView.builder(
                    //   itemCount: session.workouts.length,
                    //   itemBuilder: (BuildContext context, int index) {
                    //     return Card(
                    //       child: Column(
                    //         crossAxisAlignment: CrossAxisAlignment.start,
                    //         children: [
                    //           Row(
                    //             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //             children: [
                    //               Text(session.workouts[0].title),
                    //               Icon(Icons.more_horiz),
                    //             ],
                    //           ),
                    //           Text(session.workouts[index].description!),
                    //           Text(session.workouts[index].difficulty!),
                    //           Text(session.workouts[index].equipment!),
                    //           Text(session.workouts[index].label),
                    //           Text(
                    //             session.workouts[index].timeBetweenExercises
                    //                 .toString(),
                    //           ),
                    //           Text(
                    //             'Add edit button to the dots (replace with swiping later), which takes you to the workout to edit',
                    //           ),
                    //         ],
                    //       ),
                    //     );
                    //   },
                    // ),
                  ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: Icon(Icons.add),
      ),
    );
  }
}
