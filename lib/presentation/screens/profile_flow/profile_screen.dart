import 'package:flash_forward/presentation/screens/profile_flow/progress_chart.dart';
import 'package:flash_forward/presentation/screens/auth_flow/login_screen.dart';
import 'package:flash_forward/presentation/screens/auth_flow/signup_screen.dart';
import 'package:flash_forward/features/auth/auth_provider.dart';
import 'package:flash_forward/features/session_log/session_log_provider.dart';
import 'package:flash_forward/features/session_log/progress_extractor.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flash_forward/core/settings_provider.dart';
import 'package:flash_forward/data/grade_scales.dart';
import 'package:flash_forward/models/grade_entry.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  StrengthDisplayMode _strengthMode = StrengthDisplayMode.load;
  String? _selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    // Read from SettingsProvider so chart display updates when the user changes
    // preferences in the SettingsDrawer (which lives outside this widget tree).
    final settings = context.watch<SettingsProvider>();
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isGuest = !authProvider.isAuthenticated;
        final profile = authProvider.userProfile;
        // Authed users need a loaded profile; guests have none and show a CTA.
        if (!isGuest && profile == null) return const SizedBox.shrink();
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: user info, or a sign-up CTA for guests ──────────────
              if (isGuest)
                const _GuestProfileHeader()
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: context.colorScheme.primary,
                      child: Text(
                        authProvider.userProfile?.firstName.isNotEmpty == true
                            ? authProvider.userProfile!.firstName[0]
                                .toUpperCase()
                            : 'U',
                        style: context.h2.copyWith(
                          color: context.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${authProvider.userProfile!.firstName} ${authProvider.userProfile!.lastName}',
                            style: context.titleLarge,
                          ),
                          authProvider.userProfile!.country == null
                              ? const SizedBox.shrink()
                              : Text(
                                authProvider.userProfile!.country!,
                                style: context.bodyMedium,
                              ),
                          Text(
                            authProvider.userProfile!.email,
                            style: context.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ],
                ),

              const SizedBox(height: 32),

              // ── Progress charts (consumed from session log) ──────────────────
              Consumer<SessionLogProvider>(
                builder: (context, sessionLog, _) {
                  final sessions = sessionLog.loggedSessions;
                  final maxExercises = ProgressExtractor.discoverMaxExercises(
                    sessions,
                  );

                  // Default to first discovered exercise; remember user selection after that.
                  final effectiveId =
                      _selectedTemplateId ??
                      (maxExercises.isNotEmpty
                          ? maxExercises.first.templateId
                          : null);

                  final strengthPoints =
                      effectiveId != null
                          ? ProgressExtractor.extractLoads(
                            sessions,
                            effectiveId,
                          )
                          : <StrengthPoint>[];

                  final gradeClimbed = ProgressExtractor.extractGrades(
                    sessions,
                    GradeMetric.climbed,
                  );
                  final gradeFlashed = ProgressExtractor.extractGrades(
                    sessions,
                    GradeMetric.flashed,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Climbing grades section ────────────────────────────
                      Row(
                        children: [
                          Text('Climbing Grades', style: context.h3),
                          Spacer(),
                          IconButton(
                            onPressed:
                                () => _showGradeReference(context: context),
                            icon: Icon(
                              Icons.info_outline_rounded,
                              color: context.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GradeProgressChart(
                        climbed: gradeClimbed,
                        flashed: gradeFlashed,
                        gradeSystem:
                            settings.gradeSystem == 'fontainebleau'
                                ? GradeSystem.fontainebleau
                                : GradeSystem.vscale,
                      ),

                      // ── Strength section ───────────────────────────────────
                      const SizedBox(height: 28),
                      Text('Strength', style: context.h3),
                      const SizedBox(height: 12),
                      if (maxExercises.isEmpty)
                        _HintCard(
                          message:
                              'Add a "Max" exercise to a session and complete it to track strength progress.',
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: effectiveId,
                          decoration: const InputDecoration(
                            labelText: 'Exercise',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items:
                              maxExercises
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.templateId,
                                      child: Text(e.title),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (v) => setState(() => _selectedTemplateId = v),
                        ),
                        const SizedBox(height: 12),
                        if (strengthPoints.any(
                          (p) => p.bodyWeightKg != null,
                        )) ...[
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<StrengthDisplayMode>(
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: [
                                ButtonSegment(
                                  value: StrengthDisplayMode.load,
                                  label: Text(
                                    'Load',
                                    style: context.bodyMedium,
                                  ),
                                ),
                                ButtonSegment(
                                  value: StrengthDisplayMode.ratio,
                                  label: Text(
                                    'Ratio',
                                    style: context.bodyMedium,
                                  ),
                                ),
                              ],
                              showSelectedIcon: false,
                              selected: {_strengthMode},
                              onSelectionChanged:
                                  (s) =>
                                      setState(() => _strengthMode = s.first),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        StrengthProgressChart(
                          points: strengthPoints,
                          unit: settings.weightUnit,
                          displayMode: _strengthMode,
                        ),
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: context.bodyMedium),
    );
  }
}

void _showGradeReference({required BuildContext context}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colorScheme.surfaceBright,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('V-scale ↔ Font reference', style: context.h3),
              const SizedBox(height: 12),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerHighest,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'V-scale',
                          style: context.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'Fontainebleau',
                          style: context.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (var v = 0; v < kVToFontIndices.length; v++)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text('V$v', style: context.bodyMedium),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            fontEquivalentsForVGrade(v).join(' / '),
                            style: context.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Replaces the user header for a guest: a sign-up call to action. The settings
/// gear stays accessible so guests can still reach the drawer (and its sign-in
/// entry). Both buttons run the auth screens in detour mode.
class _GuestProfileHeader extends StatelessWidget {
  const _GuestProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.settings_rounded),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceBright,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.shadowMedium,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("You're exploring as a guest", style: context.h3),
              const SizedBox(height: 8),
              Text(
                'Create a free account to back up your sessions and build your '
                'own training.',
                style: context.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SignUpScreen(popOnSuccess: true),
                      ),
                    ),
                child: const Text('Create account'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => const LoginScreen(
                              popOnSuccess: true,
                              guestMode: true,
                            ),
                      ),
                    ),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
