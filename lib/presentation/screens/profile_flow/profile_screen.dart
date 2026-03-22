import 'package:flash_forward/presentation/widgets/progress_chart.dart';
import 'package:flash_forward/providers/auth_provider.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/services/progress_extractor.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flash_forward/data/grade_scales.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _weightUnit = 'kg';
  String _gradeSystem = 'fontainebleau';
  bool _showRatio = false;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _weightUnit = prefs.getString('pref_weight_unit') ?? 'kg';
      _gradeSystem = prefs.getString('pref_grade_system') ?? 'fontainebleau';
    });
  }

  Future<void> _setWeightUnit(String unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_weight_unit', unit);
    if (!mounted) return;
    setState(() => _weightUnit = unit);
  }

  Future<void> _setGradeSystem(String system) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_grade_system', system);
    if (!mounted) return;
    setState(() => _gradeSystem = system);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── User header ─────────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: context.colorScheme.primary,
                  child: Text(
                    authProvider.userProfile?.firstName.isNotEmpty == true
                        ? authProvider.userProfile!.firstName[0].toUpperCase()
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
              ],
            ),

            const SizedBox(height: 32),

            // ── Progress charts (consumed from session log) ──────────────────
            Consumer<SessionLogProvider>(
              builder: (context, sessionLog, _) {
                final sessions = sessionLog.loggedSessions;
                final maxExercises =
                    ProgressExtractor.discoverMaxExercises(sessions);

                // Default to first discovered exercise; remember user selection after that.
                final effectiveId = _selectedTemplateId ??
                    (maxExercises.isNotEmpty
                        ? maxExercises.first.templateId
                        : null);

                final strengthPoints = effectiveId != null
                    ? ProgressExtractor.extractLoads(sessions, effectiveId)
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
                    Text('Climbing Grades', style: context.h3),
                    const SizedBox(height: 12),
                    GradeProgressChart(
                      climbed: gradeClimbed,
                      flashed: gradeFlashed,
                    ),
                    const SizedBox(height: 8),
                    _GradeReferenceSection(),

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
                        items: maxExercises
                            .map((e) => DropdownMenuItem(
                                  value: e.templateId,
                                  child: Text(e.title),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedTemplateId = v),
                      ),
                      const SizedBox(height: 12),
                      if (strengthPoints.any((p) => p.bodyWeightKg != null))
                        SwitchListTile(
                          title: Text(
                            'Show load / body weight ratio',
                            style: context.bodyMedium,
                          ),
                          value: _showRatio,
                          onChanged: (v) => setState(() => _showRatio = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                      StrengthProgressChart(
                        points: strengthPoints,
                        unit: _weightUnit,
                        showRatio: _showRatio,
                      ),
                    ],
                  ],
                );
              },
            ),

            // ── Preferences ───────────────────────────────────────────────────
            const SizedBox(height: 32),
            Text('Preferences', style: context.h3),
            const SizedBox(height: 16),

            Text('Weight unit', style: context.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'kg', label: Text('kg')),
                ButtonSegment(value: 'lbs', label: Text('lbs')),
              ],
              selected: {_weightUnit},
              onSelectionChanged: (s) => _setWeightUnit(s.first),
            ),

            const SizedBox(height: 20),

            Text('Grade system', style: context.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'fontainebleau',
                  label: Text('Fontainebleau'),
                ),
                ButtonSegment(value: 'vscale', label: Text('V-scale')),
              ],
              selected: {_gradeSystem},
              onSelectionChanged: (s) => _setGradeSystem(s.first),
            ),
            const SizedBox(height: 6),
            Text(
              'Past entries use their stored system and will still display correctly.',
              style: context.bodyMedium.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
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

/// Collapsible V-scale ↔ Fontainebleau reference grid.
class _GradeReferenceSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('V-scale ↔ Font reference', style: context.bodyMedium),
      tilePadding: EdgeInsets.zero,
      children: [
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
    );
  }
}
