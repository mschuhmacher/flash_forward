import 'package:flash_forward/presentation/widgets/listview_program_screen.dart';
import 'package:flash_forward/presentation/widgets/search_filter_row_program_screen.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  @override
  Widget build(BuildContext context) {
    return const TabBarView(
      children: [
        SessionTabBarView(),
        WorkoutTabBarView(),
        ExerciseTabBarView(),
      ],
    );
  }
}

class SessionTabBarView extends StatelessWidget {
  const SessionTabBarView({super.key});

  @override
  Widget build(BuildContext context) {
    return ProgramListview(itemType: ItemType.sessions);
  }
}

class WorkoutTabBarView extends StatelessWidget {
  const WorkoutTabBarView({super.key});

  @override
  Widget build(BuildContext context) {
    return ProgramListview(itemType: ItemType.workouts);
  }
}

class ExerciseTabBarView extends StatelessWidget {
  const ExerciseTabBarView({super.key});

  @override
  Widget build(BuildContext context) {
    return ProgramListview(itemType: ItemType.exercises);
  }
}
