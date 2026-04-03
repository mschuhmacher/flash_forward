import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/screens/session_flow/session_active_screen.dart';
import 'package:flash_forward/presentation/widgets/label_badge.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/presentation/screens/training_program_flow/_OLD_add_item_screen.dart';
import 'package:flash_forward/providers/preset_provider.dart';
import 'package:flash_forward/presentation/widgets/session_select_row.dart';
import 'package:flash_forward/presentation/widgets/session_select_listview.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

class SessionSelectScreen extends StatefulWidget {
  final dynamic index;

  const SessionSelectScreen({super.key, this.index});

  @override
  State<SessionSelectScreen> createState() => _SessionSelectScreenState();
}

class _SessionSelectScreenState extends State<SessionSelectScreen> {
  int index = 0;
  Set<String> isExpandedIds = {};
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final AppBar myAppBar = AppBar(
      title: Row(
        children: [
          SizedBox.shrink(),
          Spacer(),
          Text('Flash Forward', style: context.h3),
          Spacer(),
          IconButton(onPressed: () {}, icon: Icon(Icons.search_rounded)),
        ],
      ),
      centerTitle: true,
    );

    return Consumer2<PresetProvider, SessionStateProvider>(
      builder: (context, presetData, sessionStateData, child) {
        final currentSessionList = presetData.presetSessions;

        // Guard clause: show loading indicator if sessions are loading
        if (presetData.isLoading) {
          return Scaffold(
            appBar: myAppBar,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        // If done loading but sessionList remains empty due to error
        if (presetData.isLoading == false && currentSessionList.isEmpty) {
          return Scaffold(
            appBar: myAppBar,
            body: Center(
              child: Text('No sessions found...', style: context.h2),
            ),
          );
        }

        return Scaffold(
          appBar: myAppBar,
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8),
                Text("Select your", style: context.h1),
                SizedBox(height: 8),
                Text(
                  "momentum.",
                  style: context.h1.copyWith(
                    color: context.colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final session = currentSessionList[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedId =
                                selectedId == session.id ? null : session.id;
                          });
                        },
                        child: _SessionCard(
                          isSelected: selectedId == session.id,
                          session: session,
                          isExpanded: isExpandedIds.contains(session.id),
                          onTapExpanded: () {
                            isExpandedIds.contains(session.id)
                                ? setState(() {
                                  isExpandedIds.remove(session.id);
                                })
                                : setState(() {
                                  isExpandedIds.add(session.id);
                                });
                          },
                        ),
                      );
                    },
                    separatorBuilder: (context, index) => SizedBox(height: 12),
                    itemCount: currentSessionList.length,
                  ),
                ),
                SizedBox(
                  height: 80,
                ), //To ensure that the list listview item is not hidden by the start session button
              ],
            ),
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: StartSessionButton(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ActiveSessionScreen(
                                  session: currentSessionList.firstWhere(
                                    (s) => s.id == selectedId,
                                  ),
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                FloatingActionButton(
                  backgroundColor: context.colorScheme.secondary,
                  foregroundColor: context.colorScheme.onSecondary,
                  onPressed: () {},
                  child: Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    super.key,
    required this.isSelected,
    required this.session,
    required this.isExpanded,
    required this.onTapExpanded,
  });

  final bool isSelected;
  final Session session;
  final bool isExpanded;
  final VoidCallback onTapExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        border:
            isSelected
                ? Border.all(width: 2.5, color: context.colorScheme.primary)
                : null,
        color: context.colorScheme.surfaceBright,
        boxShadow: context.shadowSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LabelBadge(labelKey: session.label),
              IconButton(
                onPressed: onTapExpanded,
                icon:
                    isExpanded
                        ? Icon(Icons.keyboard_arrow_up_rounded, size: 30)
                        : Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(session.title, style: context.h2),
          SizedBox(height: 4),
          if (session.description != null) ...[
            Text(
              session.description!,
              style: context.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 12),
          ],
          if (isExpanded)
            ListView.separated(
              physics: NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemBuilder: (context, index) {
                return _WorkoutCard(workout: session.workouts[index]);
              },
              separatorBuilder: (context, index) => SizedBox(height: 8),
              itemCount: session.workouts.length,
            ),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({super.key, required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 32,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color:
                    kDefaultLabels[workout.label]?.color ??
                    context.colorScheme.surfaceDim,
              ),
            ),
            SizedBox(width: 8),
            Text(workout.title, style: context.titleLarge),
          ],
        ),
        SizedBox(height: 4),
        for (final exercise in workout.exercises) ...[
          _ExerciseCard(exercise: exercise),
          SizedBox(height: 4),
        ],
        SizedBox(height: 8),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text(exercise.title, style: context.bodyMedium),
      ),
    );
  }
}
