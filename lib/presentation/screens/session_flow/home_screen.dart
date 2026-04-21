import 'package:flash_forward/presentation/screens/session_flow/session_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:flash_forward/data/grade_scales.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/presentation/widgets/label_badge.dart';
import 'package:flash_forward/presentation/widgets/my_calendar.dart';
import 'package:flash_forward/presentation/widgets/start_session_button.dart';
import 'package:flash_forward/presentation/widgets/workout_card.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<int, GlobalKey> _iconButtonKeys = {};

  @override
  Widget build(BuildContext context) {
    return Consumer2<SessionLogProvider, AuthProvider>(
      builder: (
        BuildContext context,
        sessionLogData,
        authProvider,
        Widget? child,
      ) {
        // Reverse the list to show the latest sessions first
        List<Session> selectedSessions =
            sessionLogData.selectedSessions.reversed.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hey ${authProvider.userProfile?.firstName.isNotEmpty == true ? authProvider.userProfile!.firstName : "Climber"}!',
                    style: context.h1,
                  ),
                  Text('Ready to climb?', style: context.bodyMedium),
                ],
              ),
            ),

            SizedBox(height: 32),
            StartSessionButton(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SessionSelectScreen(),
                  ),
                );
              },
            ),
            SizedBox(height: 32),
            MyCalendar(),
            SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Logged sessions',
                style: context.h3,
                textAlign: TextAlign.start,
              ),
            ),
            Expanded(
              child:
                  selectedSessions.isEmpty
                      ? Center(
                        child: Text(
                          'No climbing sessions logged yet.',
                          style: context.bodyLarge,
                        ),
                      )
                      : _buildListView(selectedSessions),
            ),
          ],
        );
      },
    );
  }

  ListView _buildListView(List<Session> selectedSessions) {
    return ListView.separated(
      itemCount: selectedSessions.length,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      separatorBuilder: (context, index) => SizedBox(height: 8),
      itemBuilder: (context, index) {
        final session = selectedSessions[index];
        final date = session.completedAt;

        // Ensure we have a GlobalKey for this index
        if (!_iconButtonKeys.containsKey(index)) {
          _iconButtonKeys[index] = GlobalKey();
        }
        final iconButtonKey = _iconButtonKeys[index]!;

        final formattedDate =
            date != null ? DateFormat('dd MMM yyyy').format(date) : '';
        final formattedTime =
            date != null ? DateFormat('HH:mm').format(date) : '';

        return GestureDetector(
          onTap: () => _showLoggedSessionDetails(context, session),
          child: Slidable(
            key: ValueKey(session.id),
            endActionPane: ActionPane(
              motion: ScrollMotion(),
              children: [
                SizedBox(width: 8),
                SlidableAction(
                  borderRadius: BorderRadius.circular(12),
                  onPressed: (context) async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Delete session?', style: ctx.h3),
                        content: Text(
                          'This will permanently delete this session.',
                          style: ctx.bodyMedium,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await context
                          .read<SessionLogProvider>()
                          .deleteLoggedSession(session.id);
                    }
                  },
                  backgroundColor: context.colorScheme.error,
                  foregroundColor: context.colorScheme.onError,
                  icon: Icons.delete_rounded,
                  label: 'Delete',
                ),
              ],
            ),
            child: Container(
              //ListTile is wrapped in a material widget so prevent the list from overflowing into the other widgets in the column. Known issue.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: context.colorScheme.surfaceBright,
                boxShadow: context.shadowSmall,
              ),

              child: ListTile(
                title: Text(session.title, style: context.titleMedium),
                subtitle: Text(
                  '$formattedDate at $formattedTime',
                  style: context.bodyMedium,
                ),
                trailing:
                    (kDefaultLabels.containsKey(session.label))
                        ? Icon(
                          key: iconButtonKey,
                          kDefaultLabels[session.label]!.icon,
                          color: kDefaultLabels[session.label]!.color,
                          size: 20,
                        )
                        : null,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLoggedSessionDetails(BuildContext context, Session session) {
    final date = session.completedAt;
    final formattedDate =
        date != null
            ? '${DateFormat('dd MMM yyyy').format(date)} at ${DateFormat('HH:mm').format(date)}'
            : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (BuildContext sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: context.colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.title, style: context.h3),
                        if (formattedDate != null) ...[
                          SizedBox(height: 4),
                          Text(formattedDate, style: context.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  LabelBadge(labelKey: session.label),
                ],
              ),
              if (session.description != null &&
                  session.description!.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(session.description!, style: context.bodyMedium),
              ],
              // Stats row
              if (session.rpe != null ||
                  session.maxGradeClimbed != null ||
                  session.maxGradeFlashed != null ||
                  session.bodyWeightKg != null) ...[
                SizedBox(height: 16),
                Divider(height: 1),
                SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (session.rpe != null)
                      _StatChip(label: 'RPE', value: '${session.rpe}/10'),
                    if (session.maxGradeClimbed != null)
                      _StatChip(
                        label: 'Max climbed',
                        value: gradeLabel(session.maxGradeClimbed!),
                      ),
                    if (session.maxGradeFlashed != null)
                      _StatChip(
                        label: 'Max flashed',
                        value: gradeLabel(session.maxGradeFlashed!),
                      ),
                    if (session.bodyWeightKg != null)
                      _StatChip(
                        label: 'Body weight',
                        value: '${session.bodyWeightKg} kg',
                      ),
                  ],
                ),
              ],
              if (session.notes != null && session.notes!.isNotEmpty) ...[
                SizedBox(height: 12),
                Text('Notes', style: context.titleMedium),
                SizedBox(height: 4),
                Text(session.notes!, style: context.bodyMedium),
              ],
              // Workouts
              if (session.workouts.isNotEmpty) ...[
                SizedBox(height: 16),
                Divider(height: 1),
                SizedBox(height: 12),
                Text('Workouts', style: context.titleMedium),
                SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: session.workouts.length,
                    itemBuilder:
                        (context, index) => SessionWorkoutCard(
                          workout: session.workouts[index],
                        ),
                  ),
                ),
              ] else ...[
                SizedBox(height: 16),
                Divider(height: 1),
                SizedBox(height: 12),
                Center(
                  child: Text('No workouts logged.', style: context.bodyMedium),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceBright,
        borderRadius: BorderRadius.circular(12),
        boxShadow: context.shadowSmall
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.bodyMedium.copyWith(
              color: context.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          Text(value, style: context.titleMedium),
        ],
      ),
    );
  }
}
