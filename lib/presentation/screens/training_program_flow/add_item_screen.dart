import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/search_filter_row_program_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum ItemType { workouts, exercises }

class AddItemScreen extends StatefulWidget {
  final ItemType itemType;

  const AddItemScreen({super.key, required this.itemType});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final Set<String> _selectedItemIds = {};
  final Set<String> _expandedItemIds = {};

  String _query = '';
  String _filterLabel = '';

  void _toggleSelected(String id) {
    setState(() {
      _selectedItemIds.contains(id)
          ? _selectedItemIds.remove(id)
          : _selectedItemIds.add(id);
    });
  }

  void _toggleExpanded(String id) {
    setState(() {
      _expandedItemIds.contains(id)
          ? _expandedItemIds.remove(id)
          : _expandedItemIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PresetProvider>(
      builder: (BuildContext context, presetData, Widget? child) {
        List<dynamic> listItems = [];

        switch (widget.itemType) {
          case ItemType.workouts:
            listItems = presetData.presetWorkouts;
          case ItemType.exercises:
            listItems = presetData.presetExercises;
        }

        final String labelFilter = _filterLabel.trim();

        final List<dynamic> filteredListItems =
            listItems.where((item) {
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

        final scrollController = ScrollController();

        final List<dynamic> selectedPresetItems =
            listItems
                .where((item) => _selectedItemIds.contains(item.id))
                .toList();

        String buttonLabel;
        String buttonLabelText;
        if (widget.itemType == ItemType.workouts) {
          buttonLabelText = 'workout';
        } else {
          buttonLabelText = 'exercise';
        }

        if (selectedPresetItems.isEmpty) {
          buttonLabel = 'Select ${buttonLabelText}s';
        } else if (selectedPresetItems.length == 1) {
          buttonLabel = 'Add 1 $buttonLabelText';
        } else {
          buttonLabel = 'Add ${selectedPresetItems.length} ${buttonLabelText}s';
        }

        return Scaffold(
          appBar: AppBar(title: Text('Add $buttonLabelText')),
          body: Column(
            children: [
              SearchFilterRow(
                onQueryChanged: (value) => setState(() => _query = value),
                onFilterLabelChanged:
                    (value) => setState(() => _filterLabel = value ?? ''),
              ),
              SizedBox(height: 8),
              Expanded(
                child: Stack(
                  children: [
                    Scrollbar(
                      controller: scrollController,
                      scrollbarOrientation: ScrollbarOrientation.left,
                      interactive: true,
                      thickness: 6,
                      radius: Radius.circular(3),
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredListItems.length,
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final id = filteredListItems[index].id;
                          return widget.itemType == ItemType.workouts
                              ? WorkoutCard(
                                workout: filteredListItems[index],
                                isSelected: _selectedItemIds.contains(id),
                                onTap: () => _toggleSelected(id),
                                isExpanded: _expandedItemIds.contains(id),
                                onIconTap: () => _toggleExpanded(id),
                              )
                              : ExerciseCard(
                                exercise: filteredListItems[index],
                                isSelected: _selectedItemIds.contains(id),
                                onTap: () => _toggleSelected(id),
                                isExpanded: _expandedItemIds.contains(id),
                                onIconTap: () => _toggleExpanded(id),
                              );
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: 200,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context, selectedPresetItems);
                            },
                            child: Text(buttonLabel),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({
    super.key,
    required this.workout,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.onIconTap,
  });

  final Workout workout;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onIconTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: context.colorScheme.surfaceBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(
            width: isSelected ? 2.5 : 1.5,
            color:
                isSelected
                    ? context.colorScheme.primary
                    : context.colorScheme.secondary,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(workout.title), Text(workout.label)],
              ),
              Row(
                children: [
                  Expanded(child: Text(workout.description!)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: onIconTap,
                    ),
                  ),
                ],
              ),

              if (isExpanded)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 4),
                    Text('Exercises:'),
                    ...workout.exercises.map(
                      (exercise) => Text(exercise.title),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.onIconTap,
  });

  final Exercise exercise;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onIconTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: context.colorScheme.surfaceBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(
            width: isSelected ? 2.5 : 1.5,
            color:
                isSelected
                    ? context.colorScheme.primary
                    : context.colorScheme.secondary,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(exercise.title), Text(exercise.label)],
              ),
              Row(
                children: [
                  Expanded(child: Text(exercise.description!)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: onIconTap,
                    ),
                  ),
                ],
              ),

              if (isExpanded)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [SizedBox(height: 4), Text('What to put here?')],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
