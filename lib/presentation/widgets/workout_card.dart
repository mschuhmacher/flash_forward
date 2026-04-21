import 'package:flash_forward/models/workout.dart';
import 'package:flash_forward/presentation/widgets/label_badge.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class SessionWorkoutCard extends StatelessWidget {
  final Workout workout;

  const SessionWorkoutCard({super.key, required this.workout});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
        boxShadow: context.shadowMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  workout.title,
                  style: context.titleMedium,
                  maxLines: 2,
                ),
              ),
              LabelBadge(labelKey: workout.label),
            ],
          ),
          if (workout.description != null && workout.description!.isNotEmpty) ...[
            SizedBox(height: 2),
            Text(
              workout.description!,
              style: context.bodyMedium.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (workout.exercises.isNotEmpty) ...[
            SizedBox(height: 10),
            Divider(height: 1),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: SizedBox.shrink()),
                SizedBox(
                  width: 40,
                  child: Text(
                    'Sets',
                    style: context.bodyMedium.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    'Reps',
                    style: context.bodyMedium.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    'Load',
                    style: context.bodyMedium.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            for (final exercise in workout.exercises)
              Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(exercise.title, style: context.bodyMedium),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${exercise.sets}',
                        style: context.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${exercise.reps}',
                        style: context.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        exercise.load > 0
                            ? exercise.loadUnit != null
                                ? '${exercise.load} ${exercise.loadUnit}'
                                : '${exercise.load}'
                            : '—',
                        style: context.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
