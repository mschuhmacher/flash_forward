import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_exercise_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_session_screen.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/new_workout_screen.dart';
import 'package:flash_forward/presentation/widgets/search_filter_row_program_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

enum ItemType { sessions, workouts, exercises }

class ProgramScreen extends StatefulWidget {
  final TabController tabController;

  const ProgramScreen({super.key, required this.tabController});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: widget.tabController,
      children: const [
        ProgramListview(itemType: ItemType.sessions),
        ProgramListview(itemType: ItemType.workouts),
        ProgramListview(itemType: ItemType.exercises),
      ],
    );
  }
}

class ProgramListview extends StatefulWidget {
  const ProgramListview({super.key, required this.itemType});

  final ItemType itemType;

  @override
  State<ProgramListview> createState() => _ProgramListviewState();
}

class _ProgramListviewState extends State<ProgramListview> {
  String _query = '';
  String _filterLabel = '';

  Future<void> _copyItem(dynamic item) async {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    switch (widget.itemType) {
      case ItemType.sessions:
        final copy = (item as Session).deepCopy();
        await presetProvider.addPresetSession(copy.copyWith(title: '${copy.title} - copy'));
      case ItemType.workouts:
        final copy = (item as Workout).deepCopy();
        await presetProvider.addPresetWorkout(copy.copyWith(title: '${copy.title} - copy'));
      case ItemType.exercises:
        final copy = (item as Exercise).deepCopy();
        await presetProvider.addPresetExercise(copy.copyWith(title: '${copy.title} - copy'));
    }
  }

  Future<void> _deleteItem(dynamic item) async {
    final presetProvider = Provider.of<PresetProvider>(context, listen: false);
    switch (widget.itemType) {
      case ItemType.sessions:
        await presetProvider.deleteUserPresetSession((item as Session).id);
      case ItemType.workouts:
        await presetProvider.deleteUserPresetWorkout((item as Workout).id);
      case ItemType.exercises:
        await presetProvider.deleteUserPresetExercise((item as Exercise).id);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<PresetProvider>(
      builder: (BuildContext context, presetData, Widget? child) {
        List<dynamic> listItems = [];

        switch (widget.itemType) {
          case ItemType.sessions:
            listItems = presetData.presetSessions;
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

        return Column(
          children: [
            SearchFilterRow(
              onQueryChanged: (value) => setState(() => _query = value),
              onFilterLabelChanged:
                  (value) => setState(() => _filterLabel = value ?? ''),
            ),
            Expanded(
              child: Scrollbar(
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
                    final item = filteredListItems[index];

                    final bool isUserDefined;
                    switch (widget.itemType) {
                      case ItemType.sessions:
                        isUserDefined = presetData.presetUserSessionIDs.contains(item.id);
                      case ItemType.workouts:
                        isUserDefined = presetData.presetUserWorkoutsIDs.contains(item.id);
                      case ItemType.exercises:
                        isUserDefined = presetData.presetUserExerciseIDs.contains(item.id);
                    }

                    return ProgramListviewCard(
                      filteredListItem: item,
                      itemType: widget.itemType,
                      onCopy: () => _copyItem(item),
                      onDelete: isUserDefined ? () => _deleteItem(item) : null,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ProgramListviewCard extends StatelessWidget {
  const ProgramListviewCard({
    super.key,
    required this.filteredListItem,
    required this.itemType,
    required this.onCopy,
    this.onDelete,
  });

  final dynamic filteredListItem;
  final ItemType itemType;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () {
          switch (itemType) {
            case ItemType.sessions:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => NewSessionScreen(session: filteredListItem),
                ),
              );

            case ItemType.workouts:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => NewWorkoutScreen(workout: filteredListItem),
                ),
              );
            case ItemType.exercises:
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          NewExerciseScreen(exercise: filteredListItem),
                ),
              );
          }
        },
        child: Slidable(
          key: ValueKey(filteredListItem.id),
          endActionPane: ActionPane(
            motion: ScrollMotion(),
            children: [
              SizedBox(width: 8),
              SlidableAction(
                borderRadius: BorderRadius.circular(12),
                onPressed: (_) => onCopy(), 
                backgroundColor: context.colorScheme.secondary,
                foregroundColor: context.colorScheme.onError,
                icon: Icons.copy_rounded,
                label: 'Copy',
              ),
              if (onDelete != null) ...[
                SizedBox(width: 8),
                SlidableAction(
                  borderRadius: BorderRadius.circular(12),
                  onPressed: (_) => onDelete!(),
                  backgroundColor: context.colorScheme.error,
                  foregroundColor: context.colorScheme.onError,
                  icon: Icons.delete_rounded,
                  label: 'Delete',
                ),
              ],
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                width: 0.5,
                color: context.colorScheme.onSurface,
              ),
              color: context.colorScheme.surfaceBright,
              boxShadow: context.shadowSmall,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.fromLTRB(6, 0, 16, 0),
              minVerticalPadding: 6,
              minTileHeight: 90,

              horizontalTitleGap: 4,
              leading: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  kDefaultLabels[filteredListItem.label]?.icon,
                  color: kDefaultLabels[filteredListItem.label]?.color,
                  size: 24,
                ),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    filteredListItem.title,
                    style: context.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Icon(Icons.circle),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  filteredListItem.description != null
                      ? Text(
                        filteredListItem.description!,
                        style: context.bodyMedium,
                      )
                      : SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
