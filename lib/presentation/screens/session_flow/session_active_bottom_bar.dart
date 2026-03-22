import 'package:flash_forward/data/grade_scales.dart';
import 'package:flash_forward/models/grade_entry.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/my_icon_button.dart';
import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/session_state_provider.dart';
import 'package:flash_forward/services/progress_extractor.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ActiveSessionBottomBar extends StatefulWidget {
  const ActiveSessionBottomBar({super.key});

  @override
  State<ActiveSessionBottomBar> createState() => _ActiveSessionBottomBarState();
}

class _ActiveSessionBottomBarState extends State<ActiveSessionBottomBar> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<SessionLogProvider, SessionStateProvider>(
      builder: (context, sessionLogData, sessionStateData, child) {
        final activeSession = sessionStateData.activeSession!;

        final progress = sessionStateData.progress;
        Workout activeWorkout = activeSession.workouts[progress.workoutIndex];

        String nextExerciseString;
        if (progress.exerciseIndex + 1 < activeWorkout.exercises.length) {
          nextExerciseString =
              'Next exercise: \n${activeWorkout.exercises[progress.exerciseIndex + 1].title}';
        } else if (progress.exerciseIndex + 1 == activeWorkout.exercises.length &&
            progress.workoutIndex + 1 < activeSession.workouts.length) {
          nextExerciseString =
              'Next exercise: \n${activeSession.workouts[progress.workoutIndex + 1].exercises[0].title}';
        } else if (progress.exerciseIndex + 1 == activeWorkout.exercises.length &&
            progress.workoutIndex + 1 == activeSession.workouts.length) {
          nextExerciseString = 'Next exercise: \nDone';
        } else {
          nextExerciseString = '';
        }

        return SizedBox(
          height: 100,
          child: BottomAppBar(
            color: context.colorScheme.primary,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    (progress.exerciseIndex == 0 && progress.workoutIndex == 0)
                        ? SizedBox.shrink()
                        : GestureDetector(
                          onTap: () {
                            sessionStateData.jumpToExercise(
                              sessionStateData.exerciseIndex - 1,
                            );
                          },
                          child: MyIconButton(
                            icon: Icons.arrow_back,
                            size: 40,
                            foregroundColor: context.colorScheme.primary,
                          ),
                        ),
                    Expanded(
                      child: Center(
                        child: Text(
                          nextExerciseString,
                          style: context.bodyMedium.copyWith(
                            color: context.colorScheme.onPrimary,
                          ),
                          overflow: TextOverflow.fade,
                        ),
                      ),
                    ),

                    // Return true as long as there are more workouts or exercises to be completed. When last exercise of last workout, show complete button
                    (progress.workoutIndex >= 0 &&
                            (progress.workoutIndex + 1 <
                                    activeSession.workouts.length ||
                                progress.exerciseIndex + 1 <
                                    activeWorkout.exercises.length))
                        ? GestureDetector(
                          onTap: () {
                            sessionStateData.jumpToExercise(
                              sessionStateData.exerciseIndex + 1,
                            );
                          },
                          child: MyIconButton(
                            icon: Icons.arrow_forward,
                            size: 40,
                            foregroundColor: context.colorScheme.primary,
                          ),
                        )
                        : GestureDetector(
                          onTap: () {
                            _showFinishSessionDialog(
                              context,
                              activeSession,
                              sessionLogData,
                            );
                          },
                          child: MyIconButton(
                            icon: Icons.check,
                            size: 40,
                            foregroundColor: context.colorScheme.primary,
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFinishSessionDialog(
    BuildContext context,
    Session activeSession,
    SessionLogProvider sessionLogData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final gradeSystemName = prefs.getString('pref_grade_system') ?? 'fontainebleau';
    final gradeSystem = GradeSystem.values.byName(gradeSystemName);
    final weightUnit = prefs.getString('pref_weight_unit') ?? 'kg';
    final hasMaxExercise =
        ProgressExtractor.sessionHasMaxExercise(activeSession);
    final lastBodyWeightKg = ProgressExtractor.lastKnownBodyWeight(
      sessionLogData.loggedSessions,
    );

    if (!context.mounted) return;

    final labelController = TextEditingController(text: activeSession.label);
    final descriptionController = TextEditingController();

    // Pre-fill body weight converted to user's preferred unit
    String? bodyWeightPreFill;
    if (lastBodyWeightKg != null) {
      final displayValue = weightUnit == 'lbs'
          ? (lastBodyWeightKg * 2.20462)
          : lastBodyWeightKg;
      bodyWeightPreFill = displayValue.toStringAsFixed(1);
    }
    final bodyWeightController = TextEditingController(
      text: bodyWeightPreFill ?? '',
    );

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        GradeEntry? selectedGradeClimbed;
        GradeEntry? selectedGradeFlashed;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final gradeLabels = _gradeLabelsForSystem(gradeSystem);

            return AlertDialog(
              title: Text('Session summary', style: dialogContext.h3),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Workouts completed:', style: dialogContext.bodyLarge),
                    SizedBox(height: 8),
                    ...activeSession.workouts.map(
                      (workout) => Padding(
                        padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                        child: Text(
                          '• ${workout.title}',
                          style: dialogContext.bodyMedium,
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    MyLabelDropdownButton(
                      value: activeSession.label,
                      // labelController.text.isNotEmpty
                      //     ? labelController.text
                      //     : null,
                      onChanged: (value) {
                        setState(() {
                          labelController.text = value ?? '';
                        });
                      },
                      validator:
                          (value) =>
                              value == null || value.isEmpty
                                  ? 'Please select a label'
                                  : null,
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Add notes about your session...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      style: dialogContext.bodyMedium,
                    ),

                    // ── Grade section (always shown, optional) ────────────
                    const SizedBox(height: 20),
                    Text(
                      'Climbing grades (optional)',
                      style: dialogContext.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _GradePicker(
                      label: 'Max grade climbed',
                      gradeLabels: gradeLabels,
                      selected: selectedGradeClimbed,
                      gradeSystem: gradeSystem,
                      onChanged: (entry) =>
                          setDialogState(() => selectedGradeClimbed = entry),
                    ),
                    const SizedBox(height: 8),
                    _GradePicker(
                      label: 'Max grade flashed',
                      gradeLabels: gradeLabels,
                      selected: selectedGradeFlashed,
                      gradeSystem: gradeSystem,
                      onChanged: (entry) =>
                          setDialogState(() => selectedGradeFlashed = entry),
                    ),

                    // ── Body weight (only shown when session has Max exercises) ──
                    if (hasMaxExercise) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Body weight (optional)',
                        style: dialogContext.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bodyWeightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Weight ($weightUnit)',
                          hintText: weightUnit == 'lbs' ? 'e.g. 154.3' : 'e.g. 70.0',
                          border: const OutlineInputBorder(),
                          suffixText: weightUnit,
                        ),
                        style: dialogContext.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        // Parse body weight → always store internally as kg
                        double? bodyWeightKg;
                        final bwText = bodyWeightController.text.trim();
                        if (bwText.isNotEmpty) {
                          final parsed = double.tryParse(bwText);
                          if (parsed != null && parsed > 0) {
                            bodyWeightKg = weightUnit == 'lbs'
                                ? parsed / 2.20462
                                : parsed;
                          }
                        }

                        // Upon start, activeSession is newly created with deepCopy, call copyWith here for adding the label, description, and completion time
                        final finishedSession = activeSession.copyWith(
                          label: labelController.text,
                          description:
                              descriptionController.text.isEmpty
                                  ? null
                                  : descriptionController.text,
                          completedAt: DateTime.now(),
                          maxGradeClimbed: selectedGradeClimbed,
                          maxGradeFlashed: selectedGradeFlashed,
                          bodyWeightKg: bodyWeightKg,
                        );

                        Navigator.of(dialogContext).pop();

                        sessionLogData.refreshSelectedSessions(finishedSession);

                        // Only use the buildContext is it still mounted. Meaning, the widget is still in the Widgettree.
                        // If user leaves screen before await is done, mounted would be false
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Session saved to log!')),
                          );

                          // Reset the session state data
                          SessionStateProvider().reset();

                          // Disable keeping the screen awake.
                          WakelockPlus.disable();

                          // Keeps popping routes until the current route is the first route. Not named,so no errors.
                          Navigator.popUntil(context, (route) => route.isFirst);
                        }
                      },
                      child: Text('Finish'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Returns an ordered list of grade display strings for [system].
  List<String> _gradeLabelsForSystem(GradeSystem system) => switch (system) {
    GradeSystem.vscale => List.generate(18, (i) => 'V$i'),
    GradeSystem.fontainebleau => kFontScale,
  };
}

/// Dropdown that lets the user pick a grade (or leave it empty with '—').
class _GradePicker extends StatelessWidget {
  const _GradePicker({
    required this.label,
    required this.gradeLabels,
    required this.selected,
    required this.gradeSystem,
    required this.onChanged,
  });

  final String label;
  final List<String> gradeLabels;
  final GradeEntry? selected;
  final GradeSystem gradeSystem;
  final ValueChanged<GradeEntry?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: selected?.gradeIndex,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('—')),
        ...List.generate(
          gradeLabels.length,
          (i) => DropdownMenuItem<int?>(
            value: i,
            child: Text(gradeLabels[i]),
          ),
        ),
      ],
      onChanged: (index) => onChanged(
        index == null
            ? null
            : GradeEntry(system: gradeSystem, gradeIndex: index),
      ),
    );
  }
}
