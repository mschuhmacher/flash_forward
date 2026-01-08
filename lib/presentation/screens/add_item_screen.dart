import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/add_exercise_modal_sheet.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

class AddItemScreen extends StatefulWidget {
  final String itemName;

  const AddItemScreen({super.key, required this.itemName});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final Set<String> _selectedItemIds = {};

  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _itemLabelController = TextEditingController();
  final _filterLabelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _timeBetweenExercisesController = TextEditingController();

  bool _isSearching = false;
  bool _isFiltering = false;
  final _searchController = TextEditingController();

  String _query = '';
  late final String listItemName;

  bool _isListTileExpanded = false;

  @override
  void initState() {
    super.initState();
    listItemName = widget.itemName == 'session' ? 'workouts' : 'exercises';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _itemLabelController.dispose();
    _filterLabelController.dispose();
    _searchController.dispose();
    _descriptionController.dispose();
    _timeBetweenExercisesController.dispose();
    super.dispose();
  }

  void _onPressedAddButton() {
    if (widget.itemName == 'session') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddItemScreen(itemName: 'workout'),
        ),
      );
    } else if (widget.itemName == 'workout') {
      addExerciseModalSheet();
    }
  }

  Future<dynamic> addExerciseModalSheet() {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext builder) {
        return AddExerciseModalSheet();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PresetProvider>(
      builder: (BuildContext context, presetData, Widget? child) {
        final List<dynamic> allPresetItems =
            widget.itemName == 'session'
                ? presetData.presetWorkouts
                : presetData.presetExercises;

        final String labelFilter = _filterLabelController.text.trim();

        final List<dynamic> filteredPresetItems =
            allPresetItems.where((item) {
              // Check whether presetItems contains the search query typed by user
              final matchesTitle = item.title.toLowerCase().contains(
                _query.toLowerCase().trim(),
              );

              // Check whether presetItems contains the label selected
              final matchesLabel =
                  labelFilter.isEmpty
                      ? true
                      : (item.label ?? '').toLowerCase() ==
                          labelFilter.toLowerCase();

              return matchesTitle && matchesLabel;
            }).toList();

        final List<dynamic> selectedPresetItems =
            allPresetItems
                .where((item) => _selectedItemIds.contains(item.id))
                .toList();

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(
              title: Text('New ${widget.itemName}', style: context.h4),
              surfaceTintColor:
                  Colors
                      .transparent, //disables Material3 overlay. I.e. doesn't change the color of the appBar when the ListView scrolls
            ),
            body: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFormFields(), // TODO: fix spacing issues
                    SizedBox(height: 16),
                    _buildSearchFilterAddRow(context),
                    Expanded(
                      flex: 3,
                      child: _buildListView(filteredPresetItems),
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: Center(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            textStyle: context.h4,
                          ),
                          onPressed: () {
                            if (_formKey.currentState!.validate()) {
                              final title = _titleController.text.trim();
                              final label = _itemLabelController.text.trim();
                              final description =
                                  _descriptionController.text.trim();
                              final timeBetweenExercises =
                                  _timeBetweenExercisesController.text.trim();

                              if (widget.itemName == 'session') {
                                final newSession = Session(
                                  title: title,
                                  label: label,
                                  description: description,
                                  list:
                                      selectedPresetItems
                                          .cast<Workout>()
                                          .toList(),
                                );
                                presetData.addPresetSession(newSession);
                              } else if (widget.itemName == 'workout') {
                                final newWorkout = Workout(
                                  title: title,
                                  label: label,
                                  description: description,
                                  timeBetweenExercises: int.parse(
                                    timeBetweenExercises,
                                  ),
                                  list:
                                      selectedPresetItems
                                          .cast<Exercise>()
                                          .toList(),
                                );
                                presetData.addPresetWorkout(newWorkout);
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Form submitted successfully!'),
                                ),
                              );

                              Navigator.pop(context);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 4,
                            ),
                            child: Text('Save ${widget.itemName}'),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Column _buildFormFields() {
    return Column(
      children: [
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: _titleController,
                autofocus: true,
                decoration: InputDecoration(
                  fillColor: Theme.of(context).colorScheme.surfaceBright,
                  labelText: 'Title',
                  labelStyle: context.bodyMedium,
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Please enter a title'
                            : null,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
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
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _descriptionController,
                autofocus: true,
                decoration: InputDecoration(
                  fillColor: Theme.of(context).colorScheme.surfaceBright,
                  labelText: 'Description',
                  labelStyle: context.bodyMedium,
                ),
              ),
            ),
            if (widget.itemName == 'workout') ...[
              SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _timeBetweenExercisesController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    fillColor: Theme.of(context).colorScheme.surfaceBright,
                    labelText:
                        'Time between exercises', //TODO: too long, fix this
                    labelStyle: context.bodyMedium,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 24),
      ],
    );
  }

  Row _buildSearchFilterAddRow(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.35,
          child: Text(
            'All $listItemName',
            style: context.h4.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
        _isSearching || _isFiltering ? SizedBox.shrink() : Spacer(),
        // Spacer(),
        if (_isSearching)
          SizedBox(
            key: const ValueKey('searchField'),
            width: MediaQuery.of(context).size.width * 0.54,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: context.bodyMedium,
                      fillColor: Theme.of(context).colorScheme.surfaceBright,
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() => _query = value);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchController.clear();
                      _query = '';
                      FocusScope.of(context).unfocus();
                    });
                  },
                ),
              ],
            ),
          )
        else if (_isFiltering)
          SizedBox.shrink()
        else
          OutlinedButton(
            key: const ValueKey('searchButton'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSecondary,
              backgroundColor: Theme.of(context).colorScheme.surfaceBright,
              side: BorderSide(
                color: Theme.of(context).colorScheme.secondary,
                width: 1.5,
              ),
            ),
            onPressed: () {
              setState(() => _isSearching = true);
            },
            child: const Icon(Icons.search),
          ),

        _isSearching ? SizedBox.shrink() : SizedBox(width: 8),
        if (_isFiltering)
          SizedBox(
            key: const ValueKey('filterField'),
            height: 48,
            width: MediaQuery.of(context).size.width * 0.54,
            child: Row(
              children: [
                Expanded(
                  child: MyLabelDropdownButton(
                    value:
                        _filterLabelController.text.isNotEmpty
                            ? _filterLabelController.text
                            : null,
                    onChanged: (value) {
                      setState(() {
                        _filterLabelController.text = value ?? '';
                      });
                    },
                    validator:
                        (value) =>
                            value == null || value.isEmpty
                                ? 'Please select a label'
                                : null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isFiltering = false;
                      _filterLabelController.clear();
                      FocusScope.of(context).unfocus();
                    });
                  },
                ),
              ],
            ),
          )
        else if (_isSearching)
          SizedBox.shrink()
        else
          OutlinedButton(
            key: const ValueKey('filterButton'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSecondary,
              backgroundColor: Theme.of(context).colorScheme.surfaceBright,
              side: BorderSide(
                color: Theme.of(context).colorScheme.secondary,
                width: 1.5,
              ),
            ),
            onPressed: () {
              setState(() => _isFiltering = true);
            },
            child: const Icon(Icons.filter_alt_outlined),
          ),

        _isSearching || _isFiltering ? SizedBox.shrink() : SizedBox(width: 8),
        _isSearching || _isFiltering
            ? SizedBox.shrink()
            : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
                backgroundColor: Theme.of(context).colorScheme.surfaceBright,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.secondary,
                  width: 1.5,
                ),
              ),
              onPressed: _onPressedAddButton,
              child: Icon(Icons.add),
            ),
      ],
    );
  }

  ListView _buildListView(List<dynamic> filteredPresetItems) {
    return ListView.builder(
      itemCount: filteredPresetItems.length,
      padding: EdgeInsets.symmetric(horizontal: 8),
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                width: 0.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              color: Theme.of(context).colorScheme.surfaceBright,
              boxShadow: context.shadowSmall,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.fromLTRB(8, 8, 16, 0),
              minVerticalPadding: 0,
              leading: Checkbox(
                value: _selectedItemIds.contains(filteredPresetItems[index].id),
                onChanged: (bool? value) {
                  setState(() {
                    final id = filteredPresetItems[index].id;
                    value!
                        ? _selectedItemIds.add(id)
                        : _selectedItemIds.remove(id);
                    ;
                  });
                },
              ),
              title: Text(
                filteredPresetItems[index].title,
                style: context.titleMedium,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  filteredPresetItems[index].description != null
                      ? Text(
                        filteredPresetItems[index].description!,
                        style: context.bodyMedium,
                      )
                      : SizedBox.shrink(),
                  if (_isListTileExpanded &&
                      filteredPresetItems[index] is Workout) ...<Widget>[
                    SizedBox(height: 2),
                    Text('Exercises:'),
                    for (final exercise in filteredPresetItems[index].list)
                      Text(exercise.title),
                  ] else if (_isListTileExpanded &&
                      filteredPresetItems[index] is Exercise) ...<Widget>[
                    SizedBox(height: 2),
                    Text(
                      'Load:',
                    ), //TODO: edit to display more useful information
                    Text(filteredPresetItems[index].load),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _isListTileExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onPressed: () {
                        setState(() {
                          _isListTileExpanded = !_isListTileExpanded;
                        });
                      },
                    ),
                  ),
                ],
              ),
              trailing: Icon(Icons.edit), //TODO: make editable
            ),
          ),
        );
      },
    );
  }
}
