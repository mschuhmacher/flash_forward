import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/presentation/widgets/search_filter_row_program_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum ItemType { sessions, workouts, exercises }

class ProgramListview extends StatefulWidget {
  const ProgramListview({super.key, required this.itemType});

  final ItemType itemType;

  @override
  State<ProgramListview> createState() => _ProgramListviewState();
}

class _ProgramListviewState extends State<ProgramListview> {
  String _query = '';
  String _filterLabel = '';

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
            listItems = presetData.presetExerciseTemplates;
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
                    // final isUserDefined = userIDs.contains(listItems[index].id);

                    return ProgramListviewCard(
                      filteredListItems: filteredListItems,
                      index: index,
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
    required this.filteredListItems,
    required this.index,
  });

  final List<dynamic> filteredListItems;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(width: 0.5, color: context.colorScheme.onSurface),
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
              kDefaultLabels[filteredListItems[index].label]?.icon,
              color: kDefaultLabels[filteredListItems[index].label]?.color,
              size: 24,
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(filteredListItems[index].title, style: context.titleMedium),
              // Icon(Icons.circle),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              filteredListItems[index].description != null
                  ? Text(
                    filteredListItems[index].description!,
                    style: context.bodyMedium,
                  )
                  : SizedBox.shrink(),
            ],
          ),
          trailing: SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              onPressed: () {
                // _openListItem(listItems[index]); //TODO: create this function
              },
              icon: Icon(Icons.more_vert_rounded),
              iconSize: 28,
            ),
          ),
        ),
      ),
    );
  }
}
