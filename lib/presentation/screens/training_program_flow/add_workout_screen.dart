import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/search_filter_row_program_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddWorkoutScreen extends StatefulWidget {
  const AddWorkoutScreen({super.key});

  @override
  State<AddWorkoutScreen> createState() => _AddWorkoutScreenState();
}

class _AddWorkoutScreenState extends State<AddWorkoutScreen> {
  final Set<String> _selectedItemIds = {};
  final Set<String> _expandedItemIds = {};

  String _query = '';
  String _filterLabel = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<PresetProvider>(
      builder: (BuildContext context, presetData, Widget? child) {
        List<dynamic> listItems = presetData.presetWorkouts;

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

        return Scaffold(
          appBar: AppBar(title: const Text('Add Workout')),
          body: Column(
            children: [
              SearchFilterRow(
                onQueryChanged: (value) => setState(() => _query = value),
                onFilterLabelChanged:
                    (value) => setState(() => _filterLabel = value ?? ''),
              ),
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
                          return WorkoutCard(
                            workout: filteredListItems[index],
                            isSelected: _selectedItemIds.contains(id),
                            onTap: () {
                              setState(() {
                                _selectedItemIds.contains(id)
                                    ? _selectedItemIds.remove(id)
                                    : _selectedItemIds.add(id);
                              });
                            },
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
                            // style: ElevatedButton.styleFrom(
                            //   backgroundColor: Colors.transparent,
                            //   shadowColor: Colors.transparent,
                            // ),
                            onPressed: () {},
                            child: Text(
                              'Add ${selectedPresetItems.length} workouts',
                            ),
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
    required this.onTap,
  });

  final Workout workout;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: BorderSide(
            color:
                isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black,
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
              Text(workout.description!),
              for (var exercise in workout.exercises) Text(exercise.title),
            ],
          ),
        ),
      ),
    );
  }
}
